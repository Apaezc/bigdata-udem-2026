"""Capa bronze: ingesta con metadatos (solo env dev/prod).

Fuentes:
- NYC TLC High Volume For-Hire Vehicles (FHVHV: Uber, Lyft...), Parquet mensual (~450 MB).
- NYC taxi zone lookup (CSV).
- Open-Meteo archive API (JSON diario, NYC).

La ingesta tiene dos pasos:

1. Crudo intacto. El archivo se descarga con urllib en el driver y se guarda tal cual en
   <bronze>/_crudo/... Si el archivo ya está ahí no se descarga otra vez. Si está en la ruta de la
   versión anterior del pipeline (<bronze>/<fuente>/mes=.../<archivo>) se mueve a _crudo en lugar
   de descargarlo de nuevo.
2. Bronze en Parquet. Spark lee el crudo y lo escribe en <bronze>/<fuente>/mes=.../lote=<id>/ con
   las columnas originales sin transformar más cinco columnas de metadatos (_fecha_ingesta,
   _id_lote, _hash_fila, _fuente, _archivo_origen). Cada ejecución crea un lote nuevo y nunca
   borra los anteriores: silver lee siempre el lote más reciente de cada mes.

Bronze es compartido por dev y prod. En local no hay bronze: se trabaja sobre la muestra
(ver pipeline/muestra.py).
"""

from __future__ import annotations

import logging
import secrets
import shutil
import tempfile
import urllib.request
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from pyspark.sql import Column, DataFrame, SparkSession
from pyspark.sql import functions as F

from pipeline import io
from pipeline.settings import ultimo_dia_mes

log = logging.getLogger(__name__)

URL_VIAJES = "https://d37ci6vzurychx.cloudfront.net/trip-data/fhvhv_tripdata_{mes}.parquet"
URL_ZONAS = "https://d37ci6vzurychx.cloudfront.net/misc/taxi_zone_lookup.csv"
URL_CLIMA = (
    "https://archive-api.open-meteo.com/v1/archive"
    "?latitude=40.71&longitude=-74.01"
    "&start_date={inicio}&end_date={fin}"
    "&daily=precipitation_sum,temperature_2m_mean"
    "&timezone=America%2FNew_York"
)
TIMEOUT_S = 300

# Columnas que bronze agrega a las originales, en este orden.
COLUMNAS_METADATOS = ["_fecha_ingesta", "_id_lote", "_hash_fila", "_fuente", "_archivo_origen"]

# Texto con el que el hash representa un valor nulo, y separador entre columnas.
MARCADOR_NULO = "<nulo>"
SEPARADOR_HASH = "||"


# --- identificador del lote y URLs -----------------------------------------------------------


def url_clima(mes: str) -> str:
    inicio = f"{mes}-01"
    fin = ultimo_dia_mes(mes).isoformat()
    return URL_CLIMA.format(inicio=inicio, fin=fin)


def nuevo_id_lote(ahora: datetime) -> str:
    """Id de un lote: fecha UTC de la ingesta y 6 caracteres hexadecimales al azar.

    Ejemplo: 20260115T143005Z_a3f9c1. Empieza con la fecha para que ordenar los ids como texto
    los ordene también en el tiempo; el sufijo evita choques entre dos ingestas del mismo segundo.
    """
    fecha = ahora.strftime("%Y%m%dT%H%M%SZ")
    sufijo = secrets.token_hex(3)
    return f"{fecha}_{sufijo}"


# --- paso 1: el archivo crudo ---------------------------------------------------------------


def descargar(url: str, destino: str) -> None:
    """Descarga url a un archivo temporal y lo publica en destino (ruta local o s3://)."""
    with tempfile.TemporaryDirectory(prefix="bronze-") as tmp:
        local = Path(tmp) / "archivo"
        log.info("Descargando %s", url)
        with urllib.request.urlopen(url, timeout=TIMEOUT_S) as resp, local.open("wb") as f:
            shutil.copyfileobj(resp, f)
        io.publicar(local, destino)


def asegurar_crudo(url: str, destino: str, ruta_anterior: str) -> str:
    """Deja el archivo crudo en destino, con el menor trabajo posible.

    En orden: (1) si ya está en destino, no se hace nada; (2) si está en la ruta de la versión
    anterior, se mueve a destino (así no se vuelven a descargar los 5.4 GB del año); (3) si no,
    se descarga de la fuente.
    """
    if io.existe(destino):
        log.info("El crudo ya existe, no se descarga: %s", destino)
        return destino
    if io.existe(ruta_anterior):
        log.info("Se mueve el archivo de la versión anterior: %s -> %s", ruta_anterior, destino)
        io.mover(ruta_anterior, destino)
        return destino
    descargar(url, destino)
    log.info("Crudo descargado en %s", destino)
    return destino


# --- paso 2: columnas de metadatos ------------------------------------------------------------


def hash_fila(columnas: list[str]) -> Column:
    """SHA-256 (texto hexadecimal) de la fila completa.

    Cada columna se convierte a texto, el nulo se reemplaza por MARCADOR_NULO (así un nulo no
    se confunde con un texto vacío) y los textos se unen con '||'. Dos filas con los mismos
    valores en las mismas columnas dan el mismo hash; si cambia un solo valor, cambia el hash.
    """
    textos = []
    for nombre in columnas:
        texto = F.col(nombre).cast("string")
        texto_sin_nulos = F.coalesce(texto, F.lit(MARCADOR_NULO))
        textos.append(texto_sin_nulos)
    fila_unida = F.concat_ws(SEPARADOR_HASH, *textos)
    return F.sha2(fila_unida, 256)


def agregar_metadatos(
    df: DataFrame, fuente: str, archivo_origen: str, id_lote: str, fecha_ingesta: datetime
) -> DataFrame:
    """Agrega las cinco columnas de metadatos a las columnas originales (que no se tocan).

    El hash se calcula primero, solo con las columnas originales; por eso no depende de las
    otras columnas de metadatos.
    """
    originales = df.columns
    con_hash = df.withColumn("_hash_fila", hash_fila(originales))
    return (
        con_hash.withColumn("_fecha_ingesta", F.lit(fecha_ingesta).cast("timestamp"))
        .withColumn("_id_lote", F.lit(id_lote))
        .withColumn("_fuente", F.lit(fuente))
        .withColumn("_archivo_origen", F.lit(archivo_origen))
        .select(*originales, *COLUMNAS_METADATOS)
    )


def clima_a_filas(clima_raw: DataFrame) -> DataFrame:
    """Convierte el JSON de Open-Meteo (listas dentro de 'daily') en una fila por día.

    Solo cambia la forma: (fecha, lluvia_mm, temperatura) con los mismos valores del JSON. Los
    dos números se declaran double para que todos los meses tengan el mismo tipo (Spark infiere
    long si en un mes todos los valores vienen sin decimales).
    """
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


def escribir_lote(df: DataFrame, carpeta_lote: str, archivos: int | None = None) -> None:
    """Escribe el lote (Parquet + marcador de lote completo) y lo anota en el log."""
    io.escribir_lote(df, carpeta_lote, archivos)
    log.info("Lote escrito en %s", carpeta_lote)


# --- una función por fuente -------------------------------------------------------------------


def ingestar_viajes(
    spark: SparkSession, base: str, mes: str, id_lote: str, fecha_ingesta: datetime
) -> None:
    nombre = io.nombre_viajes(mes)
    url = URL_VIAJES.format(mes=mes)
    crudo = asegurar_crudo(
        url,
        io.ruta_crudo(base, io.VIAJES, nombre, mes),
        io.ruta_anterior(base, io.VIAJES, nombre, mes),
    )
    original = spark.read.parquet(crudo)
    con_metadatos = agregar_metadatos(original, url, nombre, id_lote, fecha_ingesta)
    escribir_lote(con_metadatos, io.dir_lote(base, io.VIAJES, id_lote, mes))


def ingestar_zonas(spark: SparkSession, base: str, id_lote: str, fecha_ingesta: datetime) -> None:
    crudo = asegurar_crudo(
        URL_ZONAS,
        io.ruta_crudo(base, io.ZONAS, io.NOMBRE_ZONAS),
        io.ruta_anterior(base, io.ZONAS, io.NOMBRE_ZONAS),
    )
    # Sin inferSchema: todas las columnas quedan como texto, igual que en el CSV.
    original = spark.read.option("header", True).csv(crudo)
    con_metadatos = agregar_metadatos(original, URL_ZONAS, io.NOMBRE_ZONAS, id_lote, fecha_ingesta)
    escribir_lote(con_metadatos, io.dir_lote(base, io.ZONAS, id_lote), archivos=1)


def ingestar_clima(
    spark: SparkSession, base: str, mes: str, id_lote: str, fecha_ingesta: datetime
) -> None:
    nombre = io.nombre_clima(mes)
    url = url_clima(mes)
    crudo = asegurar_crudo(
        url,
        io.ruta_crudo(base, io.CLIMA, nombre, mes),
        io.ruta_anterior(base, io.CLIMA, nombre, mes),
    )
    json_crudo = spark.read.option("multiLine", True).json(crudo)
    original = clima_a_filas(json_crudo)
    con_metadatos = agregar_metadatos(original, url, nombre, id_lote, fecha_ingesta)
    escribir_lote(con_metadatos, io.dir_lote(base, io.CLIMA, id_lote, mes), archivos=1)


def main(spark: Any, cfg: dict, args: Any) -> None:
    base = cfg["rutas"]["bronze"]
    # Un solo id y una sola fecha para toda la ejecución: todo lo que se ingesta junto
    # queda con el mismo lote.
    fecha_ingesta = datetime.now(UTC).replace(microsecond=0)
    id_lote = nuevo_id_lote(fecha_ingesta)
    log.info("Ingesta con lote %s en %s, meses %s", id_lote, base, ",".join(args.meses))

    ingestar_zonas(spark, base, id_lote, fecha_ingesta)
    # Un mes a la vez: cada mes escribe su propia carpeta lote= y la memoria no crece con el rango.
    for mes in args.meses:
        ingestar_viajes(spark, base, mes, id_lote, fecha_ingesta)
        ingestar_clima(spark, base, mes, id_lote, fecha_ingesta)
