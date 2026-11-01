"""Muestra de desarrollo: pocas filas de todos los meses para validar la lógica en local.

- main (--step muestra, env dev/prod en Glue): lee bronze, toma una muestra aleatoria y
  reproducible (~objetivo_filas en total, repartida en todos los meses) y la escribe en
  muestra.destino con el mismo layout que bronze. Zonas y clima se copian tal cual.
- sincronizar (env local): copia s3://<lake>/<muestra.sincronizar_desde> a rutas.bronze si
  todavía no está en el disco del Code Editor.
- aplicar_muestra: recorte adicional (--limite o muestra.max_rows) para pruebas rapidísimas.
  Toda fuente nueva debe pasar por aquí en lugar de usar un .limit() fijo en la transformación.
"""

from __future__ import annotations

import logging
import os
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


def main(spark: Any, cfg: dict, args: Any) -> None:
    destino = (cfg.get("muestra") or {}).get("destino")
    if not destino:
        raise MuestraError(f"El entorno '{cfg['entorno']}' no define muestra.destino")
    objetivo = int(cfg["muestra"].get("objetivo_filas") or 100_000)
    base = cfg["rutas"]["bronze"]

    total = io.leer_viajes(spark, base, args.meses).count()
    fraccion = min(1.0, objetivo / total) if total else 1.0
    log.info("Muestra: %d filas en bronze, fracción %.6f (~%d filas)", total, fraccion, objetivo)

    for mes in args.meses:
        (
            io.leer_viajes(spark, base, [mes])
            .sample(withReplacement=False, fraction=fraccion, seed=SEMILLA)
            .coalesce(1)
            .write.mode("overwrite")
            .parquet(io.dir_viajes(destino, mes))
        )
        io.copiar(io.ruta_clima(base, mes), io.ruta_clima(destino, mes))
    io.copiar(io.ruta_zonas(base), io.ruta_zonas(destino))
    log.info("Muestra escrita en %s", destino)


def sincronizar(cfg: dict) -> None:
    """Descarga la muestra de S3 a rutas.bronze (local) si todavía no está."""
    prefijo = (cfg.get("muestra") or {}).get("sincronizar_desde")
    local = Path(cfg["rutas"]["bronze"])
    if not prefijo or (local / "taxi_zones").exists():
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
    for clave in claves:
        destino = local / clave[len(prefijo) + 1 :]
        destino.parent.mkdir(parents=True, exist_ok=True)
        s3.download_file(bucket, clave, str(destino))
    log.info(
        "Muestra descargada de s3://%s/%s a %s (%d archivos)", bucket, prefijo, local, len(claves)
    )
