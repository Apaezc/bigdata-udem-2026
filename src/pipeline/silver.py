"""Capa silver: limpieza de viajes FHVHV y enriquecimiento con zonas y clima.

Funciones puras (DataFrame -> DataFrame): limpiar_viajes, clima_diario, enriquecer.
main(spark, cfg, args) lee los viajes de todos los meses, transforma, valida y escribe silver
particionado por pickup_date.
"""

from __future__ import annotations

import logging
from typing import Any

from pyspark.sql import DataFrame
from pyspark.sql import functions as F

from pipeline import io, quality
from pipeline.settings import rango_meses

log = logging.getLogger(__name__)


class EntradaDemasiadoGrande(RuntimeError):
    """La entrada supera el máximo configurado para el entorno (p. ej. Spark local)."""


DISTANCIA_MAX_MI = 100.0  # trip_miles está en millas
DURACION_MIN_MIN = 1.0
DURACION_MAX_MIN = 180.0

# hvfhs_license_num -> empresa (diccionario de datos de NYC TLC).
EMPRESAS = {"HV0002": "Juno", "HV0003": "Uber", "HV0004": "Via", "HV0005": "Lyft"}

# Componentes de lo que paga el pasajero (columnas FHVHV; nulos cuentan como 0).
CARGOS = ["base_passenger_fare", "tolls", "bcf", "sales_tax", "congestion_surcharge", "airport_fee"]


def _empresa(col: str) -> F.Column:
    expr = F.lit(None).cast("string")
    for licencia, nombre in EMPRESAS.items():
        expr = F.when(F.col(col) == licencia, nombre).otherwise(expr)
    return F.coalesce(expr, F.concat(F.lit("Otra "), F.col(col)))


def limpiar_viajes(trips: DataFrame, meses: list[str] | None = None) -> DataFrame:
    """Tipos, duración, empresa, total pagado y filtros de outliers.

    Filtros: distancia > 0 y < 100 mi, tarifa base > 0, duración entre 1 y 180 min,
    pickup dentro del rango de meses (si se indica) y ubicación de recogida no nula.
    Agrega pickup_date (fecha de recogida, clave de partición).
    """
    total = sum((F.coalesce(F.col(c).cast("double"), F.lit(0.0)) for c in CARGOS), F.lit(0.0))
    base = trips.select(
        F.to_timestamp("pickup_datetime").alias("pickup_datetime"),
        F.to_timestamp("dropoff_datetime").alias("dropoff_datetime"),
        F.col("PULocationID").cast("int").alias("pu_location_id"),
        F.col("DOLocationID").cast("int").alias("do_location_id"),
        _empresa("hvfhs_license_num").alias("empresa"),
        F.col("trip_miles").cast("double").alias("distancia_mi"),
        (F.col("trip_time").cast("double") / 60.0).alias("duracion_min"),
        F.col("base_passenger_fare").cast("double").alias("tarifa_base"),
        F.coalesce(F.col("tips").cast("double"), F.lit(0.0)).alias("propina"),
        F.col("driver_pay").cast("double").alias("pago_conductor"),
        (total + F.coalesce(F.col("tips").cast("double"), F.lit(0.0))).alias("total_pagado"),
    )

    condicion = (
        F.col("pickup_datetime").isNotNull()
        & F.col("pu_location_id").isNotNull()
        & (F.col("distancia_mi") > 0)
        & (F.col("distancia_mi") < DISTANCIA_MAX_MI)
        & (F.col("tarifa_base") > 0)
        & F.col("duracion_min").between(DURACION_MIN_MIN, DURACION_MAX_MIN)
    )
    if meses:
        inicio, fin = rango_meses(meses)
        condicion = (
            condicion
            & (F.col("pickup_datetime") >= F.lit(inicio.isoformat()).cast("timestamp"))
            & (F.col("pickup_datetime") < F.lit(fin.isoformat()).cast("timestamp"))
        )

    return base.where(condicion).withColumn("pickup_date", F.to_date("pickup_datetime"))


def clima_diario(clima_raw: DataFrame) -> DataFrame:
    """Aplana el bloque 'daily' de Open-Meteo a filas (fecha, lluvia_mm, temp_media_c)."""
    # posexplode + element_at en lugar de explode(arrays_zip(...alias...)): Snowpark Connect
    # nombra los campos del struct "time AS fecha" y d.fecha deja de resolverse.
    base = clima_raw.select(
        F.posexplode(F.col("daily.time")).alias("i", "fecha"),
        F.col("daily.precipitation_sum").alias("lluvia"),
        F.col("daily.temperature_2m_mean").alias("temp"),
    )
    return base.select(
        F.to_date("fecha").alias("fecha"),
        F.element_at("lluvia", F.col("i") + 1).cast("double").alias("lluvia_mm"),
        F.element_at("temp", F.col("i") + 1).cast("double").alias("temp_media_c"),
    )


def enriquecer(trips: DataFrame, zonas: DataFrame, clima: DataFrame) -> DataFrame:
    """Une zona (por PULocationID) y clima (por pickup_date). Left joins: no pierde viajes.

    zona = nombre de la zona de recogida; si no está en el lookup, 'Zona <id>'.
    """
    zonas_sel = zonas.select(
        F.col("LocationID").cast("int").alias("pu_location_id"),
        F.col("Borough").alias("borough"),
        F.col("Zone").alias("zone_name"),
    )
    clima_sel = clima.select(F.col("fecha").alias("pickup_date"), "lluvia_mm", "temp_media_c")
    return (
        trips.join(F.broadcast(zonas_sel), "pu_location_id", "left")
        .join(F.broadcast(clima_sel), "pickup_date", "left")
        .withColumn(
            "zona",
            F.coalesce(
                F.col("zone_name"),
                F.concat(F.lit("Zona "), F.col("pu_location_id").cast("string")),
            ),
        )
        .drop("zone_name")
    )


def revisar_tamano(cfg: dict, meses: list[str]) -> float:
    """MB de viajes a leer; error claro si superan limites.max_mb_entrada del entorno."""
    base = cfg["rutas"]["bronze"]
    mb = io.tamano_mb([io.dir_viajes(base, m) for m in meses])
    maximo = (cfg.get("limites") or {}).get("max_mb_entrada")
    if maximo and mb > maximo:
        raise EntradaDemasiadoGrande(
            f"La entrada pesa {mb:.0f} MB y el máximo para '{cfg['entorno']}' es {maximo} MB. "
            "Spark local tiene ~2 GB de memoria: usa Glue (computo glue_small o mayor) o recorta "
            "con --limite / LIMITE."
        )
    return mb


def main(spark: Any, cfg: dict, args: Any) -> None:
    base = cfg["rutas"]["bronze"]
    mb = revisar_tamano(cfg, args.meses)
    # Resumen de lectura: cuánto entra (con el límite de la corrida) y cuánto descarta la limpieza.
    viajes = io.leer_fuente(spark, cfg, "viajes", args.meses, args.limite)
    leidas = viajes.count()
    log.info(
        "Lectura viajes: %d filas (archivos %.1f MB, límite %s) desde %s, meses %s",
        leidas,
        mb,
        args.limite or "ninguno",
        base,
        ",".join(args.meses),
    )
    zonas = io.leer_fuente(spark, cfg, "zonas", args.meses, args.limite)
    clima = clima_diario(io.leer_fuente(spark, cfg, "clima", args.meses, args.limite))

    silver = enriquecer(limpiar_viajes(viajes, args.meses), zonas, clima)
    total = quality.validar(
        silver,
        nombre="silver",
        llaves=("pickup_datetime", "pickup_date", "pu_location_id", "zona", "empresa"),
        rangos={
            "distancia_mi": (0, DISTANCIA_MAX_MI),
            "tarifa_base": (0, None),
            "duracion_min": (DURACION_MIN_MIN, DURACION_MAX_MIN),
        },
    )["total"]
    log.info("Limpieza: %d -> %d filas (%d descartadas)", leidas, total, leidas - total)
    io.escribir_silver(silver, cfg, args.meses)
