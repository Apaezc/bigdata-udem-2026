"""Capa gold: métricas diarias por zona de recogida y empresa (gold/daily_zone_metrics)."""

from __future__ import annotations

from typing import Any

from pyspark.sql import DataFrame
from pyspark.sql import functions as F

from pipeline import io, quality

COLUMNAS = [
    "fecha",
    "zona",
    "empresa",
    "viajes",
    "ingreso_total",
    "propina_promedio",
    "distancia_promedio",
    "lluvia_mm",
]


def metricas_diarias_zona(silver: DataFrame) -> DataFrame:
    """Agrupa silver por fecha (pickup_date), zona y empresa.

    ingreso_total = suma de total_pagado; propina_promedio = promedio de propina;
    distancia_promedio = promedio de distancia_mi (millas); lluvia_mm = precipitación del día.
    """
    return (
        silver.groupBy(F.col("pickup_date").alias("fecha"), "zona", "empresa")
        .agg(
            F.count(F.lit(1)).alias("viajes"),
            F.round(F.sum("total_pagado"), 2).alias("ingreso_total"),
            F.round(F.avg("propina"), 2).alias("propina_promedio"),
            F.round(F.avg("distancia_mi"), 2).alias("distancia_promedio"),
            F.max("lluvia_mm").alias("lluvia_mm"),
        )
        .select(*COLUMNAS)
    )


def main(spark: Any, cfg: dict, args: Any) -> None:
    silver = io.leer_silver(spark, cfg, args.meses)
    gold = metricas_diarias_zona(silver)
    quality.validar(
        gold,
        nombre="gold",
        llaves=("fecha", "zona", "empresa"),
        rangos={"viajes": (1, None), "distancia_promedio": (0, 100)},
        clave_unica=("fecha", "zona", "empresa"),
    )
    io.escribir_gold(gold, cfg)
