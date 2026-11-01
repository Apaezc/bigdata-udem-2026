"""Rutas y lectura/escritura de las capas (archivos locales o s3://, según config/<env>.yaml).

Layout (igual en bronze y en la muestra, para que local lea la muestra con el mismo código):
    <bronze>/fhvhv/mes=YYYY-MM/            viajes FHVHV (Parquet; en bronze, el archivo original)
    <bronze>/taxi_zones/taxi_zone_lookup.csv
    <bronze>/clima/mes=YYYY-MM/open_meteo_YYYY-MM.json
    <silver>/fhvhv_trips/pickup_date=.../  particionado por día (overwrite dinámico)
    <gold>/daily_zone_metrics/mes=YYYY-MM/ particionado por mes; la columna `fecha` queda dentro
                                           de los Parquet porque Snowflake los carga con
                                           MATCH_BY_COLUMN_NAME (airflow/dags/sql/copy_gold.sql).
Los pasos leen y escriben todos los meses del rango en una sola pasada de Spark.
"""

from __future__ import annotations

import shutil
from pathlib import Path

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F

from pipeline.settings import rango_meses

CARPETA_CAPA = {"silver": "fhvhv_trips", "gold": "daily_zone_metrics"}


def unir(base: str, *partes: str) -> str:
    return "/".join([base.rstrip("/"), *partes])


# --- rutas bronze / muestra ------------------------------------------------------------------


def dir_viajes(base: str, mes: str) -> str:
    return unir(base, "fhvhv", f"mes={mes}")


def ruta_bronze_viajes(cfg: dict, mes: str) -> str:
    return unir(dir_viajes(cfg["rutas"]["bronze"], mes), f"fhvhv_tripdata_{mes}.parquet")


def ruta_zonas(base: str) -> str:
    return unir(base, "taxi_zones", "taxi_zone_lookup.csv")


def ruta_clima(base: str, mes: str) -> str:
    return unir(base, "clima", f"mes={mes}", f"open_meteo_{mes}.json")


# --- lectura ----------------------------------------------------------------------------------


def leer_viajes(spark: SparkSession, base: str, meses: list[str]) -> DataFrame:
    """Viajes de todos los meses (una carpeta por mes; sirve para bronze y para la muestra)."""
    return spark.read.parquet(*[dir_viajes(base, m) for m in meses])


def leer_zonas(spark: SparkSession, base: str) -> DataFrame:
    return spark.read.option("header", True).csv(ruta_zonas(base))


def leer_clima(spark: SparkSession, base: str, meses: list[str]) -> DataFrame:
    """JSON crudo de Open-Meteo (un objeto con bloque 'daily' por mes)."""
    return spark.read.option("multiLine", True).json([ruta_clima(base, m) for m in meses])


def leer_silver(spark: SparkSession, cfg: dict, meses: list[str]) -> DataFrame:
    """Silver filtrado al rango de meses (partition pruning por pickup_date)."""
    df = spark.read.parquet(unir(cfg["rutas"]["silver"], CARPETA_CAPA["silver"]))
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
    df.write.mode("overwrite").partitionBy("pickup_date").parquet(ruta)


def escribir_gold(df: DataFrame, cfg: dict, meses: list[str]) -> None:
    ruta = unir(cfg["rutas"]["gold"], CARPETA_CAPA["gold"])
    borrar_particiones(ruta, [f"mes={m}/" for m in meses])
    df.withColumn("mes", F.date_format("fecha", "yyyy-MM")).write.mode("overwrite").partitionBy(
        "mes"
    ).parquet(ruta)


def borrar_particiones(ruta: str, prefijos: list[str]) -> None:
    """Borra las carpetas de partición de `ruta` cuyo nombre empieza con alguno de los prefijos."""
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
    if destino.startswith("s3://"):
        import boto3

        bucket, _, key = destino[len("s3://") :].partition("/")
        boto3.client("s3").upload_file(str(local), bucket, key)
    else:
        Path(destino).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(local, destino)


def copiar(origen: str, destino: str) -> None:
    """Copia un archivo entre rutas (s3:// -> s3:// del lado del servidor, o locales)."""
    if origen.startswith("s3://") and destino.startswith("s3://"):
        import boto3

        ob, _, ok = origen[len("s3://") :].partition("/")
        db, _, dk = destino[len("s3://") :].partition("/")
        boto3.client("s3").copy({"Bucket": ob, "Key": ok}, db, dk)
    else:
        Path(destino).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(origen, destino)
