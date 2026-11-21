"""Lectura y escritura de las capas (archivos locales o s3://) y carpetas de bronze y la muestra.

Las rutas base (<bronze>, <silver>, <gold>) las arma settings.ruta_lake() según el entorno; aquí
solo se arma lo que cuelga de ellas. Cada función de este archivo que lee o escribe dice en voz
alta la ruta completa (LEE, ESCRIBE, BORRA...): fíjate en la salida para saber dónde estás.

    dev  -> <bronze> = s3://<lake>/dev/bronze     <silver> = s3://<lake>/dev/silver
    prod -> <bronze> = s3://<lake>/prod/bronze    <silver> = s3://<lake>/prod/silver
    (la muestra es s3://<lake>/<entorno>/muestra; en local, ./lake/muestra, ./lake/silver...)
    donde_estoy("dev") imprime la tabla completa de un entorno.

Layout dentro de cada base (igual en bronze y en la muestra, para que local lea la muestra con el
mismo código):
    <bronze>/_crudo/fhvhv/mes=YYYY-MM/fhvhv_tripdata_YYYY-MM.parquet   archivo tal como se descargó
    <bronze>/_crudo/clima/mes=YYYY-MM/open_meteo_YYYY-MM.json
    <bronze>/_crudo/taxi_zones/taxi_zone_lookup.csv
    <bronze>/fhvhv/mes=YYYY-MM/lote=<id_lote>/      Parquet + columnas de metadatos (_hash_fila...)
    <bronze>/clima/mes=YYYY-MM/lote=<id_lote>/      una fila por día
    <bronze>/taxi_zones/lote=<id_lote>/
    <silver>/fhvhv_trips/pickup_date=.../  particionado por día (overwrite dinámico)
    <gold>/daily_zone_metrics/mes=YYYY-MM/ particionado por mes; la columna `fecha` queda dentro
                                           de los Parquet porque Snowflake los carga con
                                           MATCH_BY_COLUMN_NAME (airflow/dags/sql/copy_gold.sql).
Cada ingesta de bronze crea un lote nuevo; silver y gold leen siempre el lote más reciente de
cada mes (ver lote_mas_reciente). Los pasos leen y escriben todos los meses del rango en una sola
pasada de Spark.
"""

from __future__ import annotations

import logging
import shutil
import tempfile
from pathlib import Path

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F

from pipeline.settings import (
    TABLA_CLIMA,
    TABLA_GOLD,
    TABLA_SILVER,
    TABLA_VIAJES,
    TABLA_ZONAS,
    rango_meses,
)

# Las funciones para armar rutas del lake viven en settings; se reexportan aquí para que los
# notebooks las encuentren con `from pipeline import io as pio` (pio.ruta_lake, pio.donde_estoy).
from pipeline.settings import describir_rutas as describir_rutas
from pipeline.settings import donde_estoy as donde_estoy
from pipeline.settings import prefijo_lake as prefijo_lake
from pipeline.settings import ruta_lake as ruta_lake

log = logging.getLogger(__name__)

CARPETA_CAPA = {"silver": TABLA_SILVER, "gold": TABLA_GOLD}


def anunciar(verbo: str, ruta: str, detalle: str = "") -> None:
    """Dice en voz alta qué ruta completa se lee, se escribe o se borra.

    Va al log. Si nadie configuró el logging (lo normal en un notebook), se imprime para que
    el estudiante lo vea en la salida de la celda.
    """
    mensaje = f"{verbo:<8} {ruta}"
    if detalle:
        mensaje += f"  ({detalle})"
    log.info(mensaje)
    if not log.hasHandlers():
        print(mensaje)


def unir(base: str, *partes: str) -> str:
    return "/".join([base.rstrip("/"), *partes])


# --- rutas bronze / muestra ------------------------------------------------------------------

# Carpeta de cada fuente dentro de bronze.
VIAJES = TABLA_VIAJES
ZONAS = TABLA_ZONAS
CLIMA = TABLA_CLIMA

NOMBRE_ZONAS = "taxi_zone_lookup.csv"
CARPETA_CRUDO = "_crudo"
PREFIJO_LOTE = "lote="
# Marcador propio: se publica cuando el lote ya se escribió completo. No se usa _SUCCESS porque
# Glue no siempre lo escribe en S3.
MARCA_LOTE_COMPLETO = "_LOTE_COMPLETO"


class LoteNoEncontrado(RuntimeError):
    """No hay ningún lote completo de bronze para la fuente (y el mes) pedidos."""


def nombre_viajes(mes: str) -> str:
    return f"fhvhv_tripdata_{mes}.parquet"


def nombre_clima(mes: str) -> str:
    return f"open_meteo_{mes}.json"


def dir_fuente(base: str, fuente: str, mes: str | None = None) -> str:
    """Carpeta de una fuente; las fuentes con meses (viajes, clima) llevan una por mes."""
    if mes is None:
        return unir(base, fuente)
    return unir(base, fuente, f"mes={mes}")


def dir_crudo(base: str, fuente: str, mes: str | None = None) -> str:
    """Carpeta del archivo descargado tal cual: <bronze>/_crudo/<fuente>[/mes=AAAA-MM]."""
    return dir_fuente(unir(base, CARPETA_CRUDO), fuente, mes)


def ruta_crudo(base: str, fuente: str, nombre: str, mes: str | None = None) -> str:
    return unir(dir_crudo(base, fuente, mes), nombre)


def ruta_anterior(base: str, fuente: str, nombre: str, mes: str | None = None) -> str:
    """Dónde guardaba el archivo la versión anterior del pipeline (sin _crudo ni lote)."""
    return unir(dir_fuente(base, fuente, mes), nombre)


def dir_lote(base: str, fuente: str, id_lote: str, mes: str | None = None) -> str:
    return unir(dir_fuente(base, fuente, mes), f"{PREFIJO_LOTE}{id_lote}")


# --- lotes ------------------------------------------------------------------------------------


def listar_subcarpetas(ruta: str) -> list[str]:
    """Nombres de las carpetas que cuelgan directamente de `ruta` (local o s3://)."""
    nombres = []
    if ruta.startswith("s3://"):
        import boto3

        bucket, _, prefijo = ruta[len("s3://") :].partition("/")
        prefijo = prefijo.rstrip("/") + "/"
        paginas = (
            boto3.client("s3")
            .get_paginator("list_objects_v2")
            .paginate(Bucket=bucket, Prefix=prefijo, Delimiter="/")
        )
        for pagina in paginas:
            for carpeta in pagina.get("CommonPrefixes", []):
                nombres.append(carpeta["Prefix"][len(prefijo) :].rstrip("/"))
        return nombres
    raiz = Path(ruta)
    if not raiz.is_dir():
        return nombres
    for hijo in raiz.iterdir():
        if hijo.is_dir():
            nombres.append(hijo.name)
    return nombres


def lote_mas_reciente(base: str, fuente: str, mes: str | None = None) -> str:
    """Id del lote completo más reciente de la fuente (y el mes).

    El id empieza con la fecha (AAAAMMDDTHHMMSSZ_...), así que ordenar los nombres como texto
    equivale a ordenarlos por fecha. Un lote sin el marcador _LOTE_COMPLETO quedó a medias (la
    ingesta falló al escribirlo): se ignora y se usa el anterior.
    """
    carpeta = dir_fuente(base, fuente, mes)
    lotes = []
    for nombre in listar_subcarpetas(carpeta):
        if nombre.startswith(PREFIJO_LOTE):
            lotes.append(nombre)
    for nombre in sorted(lotes, reverse=True):
        if existe(unir(carpeta, nombre, MARCA_LOTE_COMPLETO)):
            return nombre[len(PREFIJO_LOTE) :]
    raise LoteNoEncontrado(
        f"No hay ningún lote completo en {carpeta}. Ejecuta primero --step bronze "
        "(en la nube) o, si trabajas en local, vuelve a generar la muestra con make muestra."
    )


def dir_lote_reciente(base: str, fuente: str, mes: str | None = None) -> str:
    return dir_lote(base, fuente, lote_mas_reciente(base, fuente, mes), mes)


def marcar_lote_completo(carpeta_lote: str) -> None:
    """Publica el marcador que dice que el lote se escribió completo (local o s3://)."""
    with tempfile.TemporaryDirectory(prefix="marca-") as tmp:
        marca = Path(tmp) / MARCA_LOTE_COMPLETO
        marca.write_text("lote completo\n", encoding="utf-8")
        publicar(marca, unir(carpeta_lote, MARCA_LOTE_COMPLETO))


def escribir_lote(df: DataFrame, carpeta_lote: str, archivos: int | None = None) -> None:
    """Escribe un lote en Parquet y, solo si la escritura terminó bien, publica el marcador.

    Con `archivos` el lote se junta en esa cantidad de archivos (fuentes pequeñas).
    """
    salida = df
    if archivos:
        salida = df.coalesce(archivos)
    anunciar("ESCRIBE", carpeta_lote, "lote en Parquet")
    salida.write.mode("overwrite").parquet(carpeta_lote)
    marcar_lote_completo(carpeta_lote)


# --- lectura ----------------------------------------------------------------------------------


def leer_viajes(spark: SparkSession, base: str, meses: list[str]) -> DataFrame:
    """Viajes de todos los meses, cada uno desde su lote más reciente (bronze y muestra)."""
    carpetas = []
    for mes in meses:
        carpetas.append(dir_lote_reciente(base, VIAJES, mes))
    for carpeta in carpetas:
        anunciar("LEE", carpeta, "viajes")
    return spark.read.parquet(*carpetas)


def leer_zonas(spark: SparkSession, base: str) -> DataFrame:
    carpeta = dir_lote_reciente(base, ZONAS)
    anunciar("LEE", carpeta, "zonas")
    return spark.read.parquet(carpeta)


def leer_clima(spark: SparkSession, base: str, meses: list[str]) -> DataFrame:
    """Clima diario (una fila por día) de todos los meses, desde su lote más reciente."""
    carpetas = []
    for mes in meses:
        carpetas.append(dir_lote_reciente(base, CLIMA, mes))
    for carpeta in carpetas:
        anunciar("LEE", carpeta, "clima")
    return spark.read.parquet(*carpetas)


def leer_fuente(
    spark: SparkSession, cfg: dict, fuente: str, meses: list[str], limite: int | None = None
) -> DataFrame:
    """Puerta única de lectura de fuentes crudas (bronze en dev/prod, la muestra en local).

    Aplica el límite de filas de la corrida (--limite / preparar_entorno del DAG). Toda fuente
    nueva se agrega a LECTORES y se lee con esta función, nunca con spark.read directo: así el
    límite de spark_local y el cambio entre entornos funcionan solos.
    """
    from pipeline.muestra import aplicar_muestra  # import tardío: muestra importa io

    if fuente not in LECTORES:
        raise ValueError(
            f"Fuente desconocida {fuente!r}. Declárala en io.LECTORES: {sorted(LECTORES)}"
        )
    df = LECTORES[fuente](spark, cfg["rutas"]["bronze"], meses)
    return aplicar_muestra(df, cfg, limite)


# Fuentes crudas: nombre -> lector(spark, base, meses).
LECTORES = {
    "viajes": leer_viajes,
    "zonas": lambda spark, base, meses: leer_zonas(spark, base),
    "clima": leer_clima,
}


def leer_silver(spark: SparkSession, cfg: dict, meses: list[str]) -> DataFrame:
    """Silver filtrado al rango de meses (partition pruning por pickup_date)."""
    ruta = unir(cfg["rutas"]["silver"], CARPETA_CAPA["silver"])
    anunciar("LEE", ruta, f"silver, meses {','.join(meses)}")
    df = spark.read.parquet(ruta)
    inicio, fin = rango_meses(meses)
    return df.where((F.col("pickup_date") >= F.lit(inicio)) & (F.col("pickup_date") < F.lit(fin)))


# --- escritura --------------------------------------------------------------------------------


def escribir_silver(df: DataFrame, cfg: dict, meses: list[str]) -> None:
    """Reemplaza silver de los meses procesados (todas sus particiones, no solo las que llegan).

    Con overwrite dinámico solo se reescriben los días presentes en df: si un reproceso trae menos
    días (filtro nuevo, --limite), los días viejos quedarían mezclados. Por eso se borran antes.
    """
    ruta = unir(cfg["rutas"]["silver"], CARPETA_CAPA["silver"])
    borrar_particiones(ruta, [f"pickup_date={m}-" for m in meses])
    anunciar("ESCRIBE", ruta, f"silver, meses {','.join(meses)}")
    df.write.mode("overwrite").partitionBy("pickup_date").parquet(ruta)


def escribir_gold(df: DataFrame, cfg: dict, meses: list[str]) -> None:
    ruta = unir(cfg["rutas"]["gold"], CARPETA_CAPA["gold"])
    borrar_particiones(ruta, [f"mes={m}/" for m in meses])
    anunciar("ESCRIBE", ruta, f"gold, meses {','.join(meses)}")
    df.withColumn("mes", F.date_format("fecha", "yyyy-MM")).write.mode("overwrite").partitionBy(
        "mes"
    ).parquet(ruta)


def borrar_particiones(ruta: str, prefijos: list[str]) -> None:
    """Borra las carpetas de partición de `ruta` cuyo nombre empieza con alguno de los prefijos."""
    for prefijo in prefijos:
        anunciar("BORRA", unir(ruta, prefijo.rstrip("/") + "*"))
    if ruta.startswith("s3://"):
        import boto3

        bucket, _, base = ruta[len("s3://") :].partition("/")
        s3 = boto3.client("s3")
        paginador = s3.get_paginator("list_objects_v2")
        for prefijo in prefijos:
            claves = [
                {"Key": o["Key"]}
                for pagina in paginador.paginate(
                    Bucket=bucket, Prefix=f"{base.rstrip('/')}/{prefijo}"
                )
                for o in pagina.get("Contents", [])
            ]
            for i in range(0, len(claves), 1000):
                s3.delete_objects(Bucket=bucket, Delete={"Objects": claves[i : i + 1000]})
        return
    carpeta = Path(ruta)
    if not carpeta.is_dir():
        return
    for hijo in carpeta.iterdir():
        if hijo.is_dir() and any(hijo.name.startswith(p.rstrip("/")) for p in prefijos):
            shutil.rmtree(hijo)


def tamano_mb(rutas: list[str]) -> float:
    """Tamaño total (MB) de los archivos bajo las rutas (carpetas o archivos; locales o s3://)."""
    total = 0
    for ruta in rutas:
        anunciar("LISTA", ruta, "para sumar el tamaño")
        if ruta.startswith("s3://"):
            import boto3

            bucket, _, prefijo = ruta[len("s3://") :].partition("/")
            paginas = (
                boto3.client("s3")
                .get_paginator("list_objects_v2")
                .paginate(Bucket=bucket, Prefix=prefijo)
            )
            total += sum(o["Size"] for p in paginas for o in p.get("Contents", []))
        else:
            r = Path(ruta)
            archivos = [r] if r.is_file() else [f for f in r.rglob("*") if f.is_file()]
            total += sum(f.stat().st_size for f in archivos)
    return total / 1_048_576


# --- archivos (bronze y muestra) -------------------------------------------------------------


def existe(ruta: str) -> bool:
    if ruta.startswith("s3://"):
        import boto3  # import perezoso: solo se necesita con S3
        from botocore.exceptions import ClientError

        bucket, _, key = ruta[len("s3://") :].partition("/")
        try:
            boto3.client("s3").head_object(Bucket=bucket, Key=key)
        except ClientError:
            return False
        return True
    return Path(ruta).exists()


def publicar(local: Path, destino: str) -> None:
    """Copia un archivo local a destino (ruta local o s3://)."""
    anunciar("SUBE", destino, f"desde {local}")
    if destino.startswith("s3://"):
        import boto3

        bucket, _, key = destino[len("s3://") :].partition("/")
        boto3.client("s3").upload_file(str(local), bucket, key)
    else:
        Path(destino).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(local, destino)


def copiar(origen: str, destino: str) -> None:
    """Copia un archivo entre rutas (s3:// -> s3:// del lado del servidor, o locales)."""
    anunciar("COPIA", destino, f"desde {origen}")
    if origen.startswith("s3://") and destino.startswith("s3://"):
        import boto3

        ob, _, ok = origen[len("s3://") :].partition("/")
        db, _, dk = destino[len("s3://") :].partition("/")
        boto3.client("s3").copy({"Bucket": ob, "Key": ok}, db, dk)
    else:
        Path(destino).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(origen, destino)


def borrar(ruta: str) -> None:
    """Borra un archivo (local o s3://)."""
    anunciar("BORRA", ruta)
    if ruta.startswith("s3://"):
        import boto3

        bucket, _, key = ruta[len("s3://") :].partition("/")
        boto3.client("s3").delete_object(Bucket=bucket, Key=key)
    else:
        Path(ruta).unlink()


def mover(origen: str, destino: str) -> None:
    """Mueve un archivo: lo copia y solo borra el original si la copia terminó bien."""
    copiar(origen, destino)
    borrar(origen)
