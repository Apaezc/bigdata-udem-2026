"""Leer y escribir las capas del lake: el crudo, bronze, silver y gold.

Las funciones que se enseñan en clase son `leer_crudo`, `escribir_bronze`, `leer_capa`,
`escribir_capa` y `hash_fila` (con `COLUMNAS_METADATOS`). Cada una dice en voz alta la ruta
completa que lee o escribe.

Reglas de cada capa:
    bronze  solo agrega: cada ingesta es un lote nuevo (lote=<id>/) con su marcador _LOTE_COMPLETO.
    silver  reemplaza el mes: se borra mes=<mes>/ y se escribe de nuevo.
    gold    reemplaza el mes, igual que silver.

pyspark se importa dentro de las funciones que lo usan, no arriba: así este módulo se puede
cargar en la VM de Airflow, que no tiene pyspark.
"""

from __future__ import annotations

from collections.abc import Callable
from typing import TYPE_CHECKING

from pipeline.herramientas import archivos
from pipeline.herramientas.rutas import (
    TABLA_CLIMA,
    TABLA_VIAJES,
    TABLA_ZONAS,
    dir_del_lote,
    ruta_del_crudo,
    ruta_lake,
)

if TYPE_CHECKING:
    from pyspark.sql import Column, DataFrame, SparkSession

# Columnas que bronze agrega a las originales, en este orden.
COLUMNAS_METADATOS = ["_fecha_ingesta", "_id_lote", "_hash_fila", "_fuente", "_archivo_origen"]

# Texto con el que el hash representa un valor nulo, y separador entre columnas.
MARCADOR_NULO = "<nulo>"
SEPARADOR_HASH = "||"


# --- hash de la fila -------------------------------------------------


def hash_fila(columnas: list[str]) -> Column:
    """SHA-256 (texto hexadecimal) de la fila completa.

    Cada columna se convierte a texto, el nulo se reemplaza por MARCADOR_NULO (así un nulo no
    se confunde con un texto vacío) y los textos se unen con '||'. Dos filas con los mismos
    valores en las mismas columnas dan el mismo hash; si cambia un solo valor, cambia el hash.
    """
    from pyspark.sql import functions as F

    textos = []
    for nombre in columnas:
        texto = F.col(nombre).cast("string")
        texto_sin_nulos = F.coalesce(texto, F.lit(MARCADOR_NULO))
        textos.append(texto_sin_nulos)
    fila_unida = F.concat_ws(SEPARADOR_HASH, *textos)
    return F.sha2(fila_unida, 256)


def clima_a_filas(clima_raw: DataFrame) -> DataFrame:
    """Convierte el JSON de Open-Meteo (listas dentro de 'daily') en una fila por día.

    Solo cambia la forma: (fecha, lluvia_mm, temperatura) con los mismos valores del JSON. Los
    dos números se declaran double para que todos los meses tengan el mismo tipo (Spark infiere
    long si en un mes todos los valores vienen sin decimales).
    """
    from pyspark.sql import functions as F

    # posexplode + element_at en lugar de explode(arrays_zip(...alias...)): Snowpark Connect
    # nombra los campos del struct "time AS fecha" y d.fecha deja de resolverse.
    dias = clima_raw.select(
        F.posexplode(F.col("daily.time")).alias("i", "fecha"),
        F.col("daily.precipitation_sum").alias("lluvia"),
        F.col("daily.temperature_2m_mean").alias("temp"),
    )
    return dias.select(
        F.col("fecha"),
        F.element_at("lluvia", F.col("i") + 1).cast("double").alias("lluvia_mm"),
        F.element_at("temp", F.col("i") + 1).cast("double").alias("temperatura"),
    )


# --- el crudo ---------------------------------------------------------------------------------


def leer_crudo(
    spark: SparkSession,
    entorno: str,
    tabla: str,
    mes: str | None = None,
    limite: int | None = None,
) -> DataFrame:
    """Lee el archivo crudo tal como se descargó.

    fhvhv: Parquet. taxi_zones: CSV con todas las columnas como texto. clima: JSON que ya sale
    en una fila por día.

    `limite` es el número de filas (Corrida.limite_filas) o None para leer todo. Se aplica de
    forma DETERMINISTA: coalesce(1).limit(n) toma las mismas n primeras filas del archivo en cada
    corrida. Con un limit suelto Spark podría tomar filas distintas cada vez, y entonces
    reprocesar el mismo mes no daría las mismas filas (y no se podría comprobar la deduplicación).
    """
    if tabla not in (TABLA_VIAJES, TABLA_ZONAS, TABLA_CLIMA):
        raise ValueError(f"No hay crudo para la tabla {tabla!r}")
    ruta = ruta_del_crudo(entorno, tabla, mes)
    archivos.anunciar("LEE", ruta, f"crudo de {tabla}")
    if tabla == TABLA_VIAJES:
        df = spark.read.parquet(ruta)
    elif tabla == TABLA_ZONAS:
        # Sin inferSchema: todas las columnas quedan como texto, igual que en el CSV.
        df = spark.read.option("header", True).csv(ruta)
    else:
        df = clima_a_filas(spark.read.option("multiLine", True).json(ruta))
    if limite is not None:
        df = df.coalesce(1).limit(limite)
    return df


# --- bronze -----------------------------------------------------------------------------------


def _contar_lo_escrito(spark: SparkSession, carpeta: str) -> int:
    """Cuenta las filas leyendo la carpeta de vuelta.

    En Parquet el count sale del pie de cada archivo (no lee las columnas), así que es barato y
    cuenta lo que de verdad quedó escrito, no lo que creíamos escribir.
    """
    return spark.read.parquet(carpeta).count()


def escribir_bronze(df: DataFrame, entorno: str, tabla: str, mes: str | None, id_lote: str) -> int:
    """Escribe un lote nuevo en bronze (más su _LOTE_COMPLETO) y devuelve las filas escritas."""
    carpeta = dir_del_lote(entorno, tabla, id_lote, mes)
    # Las fuentes pequeñas (zonas, clima) caben en un solo archivo.
    cuantos_archivos = None
    if tabla != TABLA_VIAJES:
        cuantos_archivos = 1
    archivos.escribir_lote(df, carpeta, cuantos_archivos)
    return _contar_lo_escrito(df.sparkSession, carpeta)


def _lotes_completos(carpeta_tabla: str) -> list[str]:
    """Nombres 'lote=<id>' con marcador _LOTE_COMPLETO, del más antiguo al más reciente.

    Un lote sin marcador quedó a medias (la escritura falló): se ignora.
    """
    nombres = []
    for nombre in archivos.listar_subcarpetas(carpeta_tabla):
        if nombre.startswith(archivos.PREFIJO_LOTE):
            nombres.append(nombre)
    completos = []
    for nombre in sorted(nombres):
        if archivos.existe(archivos.unir(carpeta_tabla, nombre, archivos.MARCA_LOTE_COMPLETO)):
            completos.append(nombre)
    return completos


def _mes_de_la_tabla(tabla: str, mes: str | None) -> str | None:
    """taxi_zones no tiene mes: su carpeta es siempre <capa>/taxi_zones/."""
    if tabla == TABLA_ZONAS:
        return None
    return mes


def leer_capa(
    spark: SparkSession,
    entorno: str,
    capa: str,
    tabla: str,
    mes: str | None = None,
    lotes: str = "todos",
) -> DataFrame:
    """Lee una tabla de una capa.

    bronze: `lotes="todos"` junta todos los lotes completos del mes; `lotes="ultimo"` lee solo el
    más reciente. silver y gold: lee la carpeta del mes (`lotes` no se usa).
    """
    mes = _mes_de_la_tabla(tabla, mes)
    carpeta_tabla = ruta_lake(entorno, capa, tabla, mes)
    if capa != "bronze":
        archivos.anunciar("LEE", carpeta_tabla, f"{capa} de {tabla}")
        return spark.read.parquet(carpeta_tabla)

    if lotes not in ("todos", "ultimo"):
        raise ValueError(f"lotes debe ser 'todos' o 'ultimo', no {lotes!r}")
    completos = _lotes_completos(carpeta_tabla)
    if len(completos) == 0:
        raise archivos.LoteNoEncontrado(
            f"No hay ningún lote completo en {carpeta_tabla}. "
            "Ejecuta primero el paso bronze (make correr PASO=bronze)."
        )
    if lotes == "ultimo":
        completos = completos[-1:]
    carpetas = []
    for nombre in completos:
        carpeta = archivos.unir(carpeta_tabla, nombre)
        archivos.anunciar("LEE", carpeta, f"bronze de {tabla}")
        carpetas.append(carpeta)
    return spark.read.parquet(*carpetas)


# --- silver y gold ----------------------------------------------------------------------------


def escribir_capa(
    df: DataFrame, entorno: str, capa: str, tabla: str, mes: str | None = None
) -> int:
    """Escribe silver o gold REEMPLAZANDO el mes: borra mes=<mes>/ y escribe de nuevo.

    Se borra antes de escribir para que un reproceso con menos filas no deje filas viejas
    mezcladas. Devuelve las filas que quedaron escritas.
    """
    if capa == "bronze":
        raise ValueError("bronze solo agrega lotes: usa escribir_bronze")
    mes = _mes_de_la_tabla(tabla, mes)
    carpeta = ruta_lake(entorno, capa, tabla, mes)
    archivos.borrar_carpeta(carpeta)
    archivos.anunciar("ESCRIBE", carpeta, f"{capa} de {tabla}")
    df.write.mode("overwrite").parquet(carpeta)
    return _contar_lo_escrito(df.sparkSession, carpeta)


def mover_entre_capas(
    spark: SparkSession,
    entorno: str,
    mes: str | None,
    tabla: str,
    de: str,
    a: str,
    transformar: Callable[[DataFrame], DataFrame] | None = None,
) -> tuple[int, int]:
    """Lee `tabla` de la capa `de`, la transforma (si hay función) y la escribe en la capa `a`.

    Devuelve (filas leídas, filas escritas). Al leer de bronze junta todos los lotes completos
    del mes: por eso silver necesita deduplicar.
    """
    df = leer_capa(spark, entorno, de, tabla, mes, lotes="todos")
    leidas = df.count()
    if transformar is not None:
        df = transformar(df)
    escritas = escribir_capa(df, entorno, a, tabla, mes)
    return leidas, escritas
