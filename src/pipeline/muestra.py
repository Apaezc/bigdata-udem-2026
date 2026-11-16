"""Muestra de desarrollo: pocas filas de todos los meses para validar la lógica en local.

- main (--step muestra, env dev/prod en Glue): lee el lote más reciente de bronze, toma una
  muestra aleatoria y reproducible (~objetivo_filas en total, repartida en todos los meses) y la
  escribe en muestra.destino con el mismo layout que bronze: <fuente>/mes=.../lote=<id>/, con
  el mismo id de lote y las columnas de metadatos (_hash_fila...) intactas. Zonas y clima se
  copian completos (son pequeños). La muestra no incluye _crudo/: no hace falta para leerla.
- sincronizar (env local): copia s3://<lake>/<muestra.sincronizar_desde> a rutas.bronze si
  todavía no está en el disco del Code Editor, o si es de la versión anterior (sin lotes).
- aplicar_muestra: recorte adicional (--limite o muestra.max_rows) para pruebas rapidísimas.
  Toda fuente nueva debe pasar por aquí en lugar de usar un .limit() fijo en la transformación.
"""

from __future__ import annotations

import logging
import os
import shutil
from pathlib import Path
from typing import Any

from pyspark.sql import DataFrame

from pipeline import io

log = logging.getLogger(__name__)

SEMILLA = 42


class MuestraError(RuntimeError):
    """La muestra no está disponible."""


def limite_efectivo(cfg: dict, limite: int | None = None) -> int | None:
    """--limite manda sobre muestra.max_rows; None o 0 = sin recorte."""
    n = limite if limite is not None else (cfg.get("muestra") or {}).get("max_rows")
    return int(n) if n else None


def aplicar_muestra(df: DataFrame, cfg: dict, limite: int | None = None) -> DataFrame:
    n = limite_efectivo(cfg, limite)
    if n:
        log.info("Muestra: se usan como máximo %d filas", n)
        return df.limit(n)
    return df


def copiar_lote(spark: Any, base: str, destino: str, fuente: str, mes: str | None) -> None:
    """Copia completo el lote más reciente de una fuente pequeña (zonas o clima) a la muestra."""
    id_lote = io.lote_mas_reciente(base, fuente, mes)
    lote = spark.read.parquet(io.dir_lote(base, fuente, id_lote, mes))
    io.escribir_lote(lote, io.dir_lote(destino, fuente, id_lote, mes), archivos=1)


def muestrear_viajes(spark: Any, base: str, destino: str, mes: str, fraccion: float) -> None:
    """Escribe una fracción aleatoria (semilla fija) del lote más reciente de viajes del mes."""
    id_lote = io.lote_mas_reciente(base, io.VIAJES, mes)
    lote = spark.read.parquet(io.dir_lote(base, io.VIAJES, id_lote, mes))
    muestra = lote.sample(withReplacement=False, fraction=fraccion, seed=SEMILLA)
    io.escribir_lote(muestra, io.dir_lote(destino, io.VIAJES, id_lote, mes), archivos=1)


def main(spark: Any, cfg: dict, args: Any) -> None:
    destino = (cfg.get("muestra") or {}).get("destino")
    if not destino:
        raise MuestraError(f"El entorno '{cfg['entorno']}' no define muestra.destino")
    objetivo = int(cfg["muestra"].get("objetivo_filas") or 100_000)
    base = cfg["rutas"]["bronze"]

    total = io.leer_viajes(spark, base, args.meses).count()
    fraccion = min(1.0, objetivo / total) if total else 1.0
    log.info("Muestra: %d filas en bronze, fracción %.6f (~%d filas)", total, fraccion, objetivo)

    # Se borra lo anterior de estos meses para que la muestra no mezcle lotes viejos con el nuevo
    # (y para limpiar la muestra de la versión anterior, que no tenía carpetas lote=).
    io.borrar_particiones(io.dir_fuente(destino, io.VIAJES), [f"mes={m}/" for m in args.meses])
    io.borrar_particiones(io.dir_fuente(destino, io.CLIMA), [f"mes={m}/" for m in args.meses])
    io.borrar_particiones(destino, [f"{io.ZONAS}/"])

    for mes in args.meses:
        muestrear_viajes(spark, base, destino, mes, fraccion)
        copiar_lote(spark, base, destino, io.CLIMA, mes)
    copiar_lote(spark, base, destino, io.ZONAS, None)
    log.info("Muestra escrita en %s", destino)


def muestra_local_vigente(local: Path) -> bool:
    """True si la muestra del disco tiene al menos un lote de zonas (layout con metadatos)."""
    carpeta_zonas = local / io.ZONAS
    if not carpeta_zonas.is_dir():
        return False
    for hijo in carpeta_zonas.iterdir():
        if hijo.name.startswith(io.PREFIJO_LOTE):
            return True
    return False


def sincronizar(cfg: dict) -> None:
    """Descarga la muestra de S3 a rutas.bronze (local) si todavía no está."""
    prefijo = (cfg.get("muestra") or {}).get("sincronizar_desde")
    local = Path(cfg["rutas"]["bronze"])
    if not prefijo or muestra_local_vigente(local):
        return
    bucket = os.environ.get("LAKE_BUCKET")
    if not bucket:
        raise MuestraError(
            f"No hay muestra en {local} y falta LAKE_BUCKET para descargarla de "
            f"s3://<lake>/{prefijo}. Genera la muestra (--step muestra en Glue) y define "
            "LAKE_BUCKET."
        )
    import boto3  # import perezoso

    s3 = boto3.client("s3")
    paginas = s3.get_paginator("list_objects_v2").paginate(Bucket=bucket, Prefix=f"{prefijo}/")
    claves = [
        o["Key"] for p in paginas for o in p.get("Contents", []) if not o["Key"].endswith("/")
    ]
    if not claves:
        raise MuestraError(f"s3://{bucket}/{prefijo}/ está vacío: genera la muestra primero.")
    if local.exists():
        # Muestra de la versión anterior (sin lotes): se borra justo antes de descargar la nueva.
        log.info("La muestra de %s es de la versión anterior; se descarga de nuevo", local)
        shutil.rmtree(local)
    for clave in claves:
        destino = local / clave[len(prefijo) + 1 :]
        destino.parent.mkdir(parents=True, exist_ok=True)
        s3.download_file(bucket, clave, str(destino))
    log.info(
        "Muestra descargada de s3://%s/%s a %s (%d archivos)", bucket, prefijo, local, len(claves)
    )
