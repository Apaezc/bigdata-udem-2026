"""Capa silver: el espejo de bronze, limpio. Una tabla por fuente, mismo nombre, sin join.

    silver/fhvhv/mes=AAAA-MM/     silver/clima/mes=AAAA-MM/     silver/taxi_zones/

Es la versión «lista para copiar» del cuaderno `01_construir_paso_a_paso`: el pipeline corre de
punta a punta con ella, pero trae un problema A PROPÓSITO que se dice en voz alta en clase:

    deduplicar NO deduplica (devuelve la tabla tal cual).

Silver lee TODOS los lotes de bronze del mes. Si el mes se ingestó dos veces (reprocesar=true),
silver ve cada fila dos veces y la guarda dos veces; gold las junta y las multiplica otra vez.
Tu trabajo es escribir `deduplicar` (la marca `# PENDIENTE(equipo)` es lo que buscan las pruebas
del equipo: bórrala cuando la tengas lista). Necesita que bronze haya agregado `_hash_fila`.

Funciones puras de la casa (DataFrame -> DataFrame): limpiar_viajes, clima_diario,
limpiar_taxi_zones y enriquecer. Las tres primeras conservan `_hash_fila`, `_id_lote` y
`_fecha_ingesta` cuando la entrada las trae (y no fallan si no las trae). `enriquecer` ya no es
parte de silver: lo usa gold para juntar viajes, zonas y clima.

main(spark, corrida): por mes y por tabla, la tabla de control decide si se salta; si no, lee todos
los lotes de bronze, limpia, deduplica, valida y reemplaza `mes=<mes>/` de silver.
"""

from __future__ import annotations

import logging
from typing import Any

from pyspark.sql import DataFrame
from pyspark.sql import functions as F

from pipeline import quality
from pipeline.herramientas.capas import mover_entre_capas
from pipeline.herramientas.control import con_control
from pipeline.herramientas.corrida import Resultado
from pipeline.herramientas.rutas import (
    MES_SIN_MES,
    TABLA_CLIMA,
    TABLA_VIAJES,
    TABLA_ZONAS,
    rango_meses,
    ruta_lake,
)

log = logging.getLogger(__name__)

CAPA = "silver"

# Metadatos de bronze que silver deja pasar si existen (los otros dos, _fuente y _archivo_origen,
# solo cuentan la historia del archivo y no se necesitan aguas abajo).
METADATOS_QUE_SE_CONSERVAN = ["_hash_fila", "_id_lote", "_fecha_ingesta"]

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


def _metadatos_presentes(df: DataFrame) -> list[F.Column]:
    """Las columnas de METADATOS_QUE_SE_CONSERVAN que `df` trae de verdad (quizá ninguna)."""
    presentes = []
    for nombre in METADATOS_QUE_SE_CONSERVAN:
        if nombre in df.columns:
            presentes.append(F.col(nombre))
    return presentes


# --- la función del equipo --------------------------------------------------------------------


def deduplicar(df: DataFrame) -> DataFrame:
    """Deja UNA fila por `_hash_fila`: si el mismo mes entró en dos lotes, queda una sola copia.

    Dos filas con el mismo hash tienen exactamente los mismos valores en las columnas originales,
    así que no importa cuál de las dos se conserva. Una tabla sin repetidos queda igual.
    """
    # PENDIENTE(equipo): hoy esta función devuelve df tal cual. Por eso, al reprocesar un mes,
    # silver tiene cada fila dos veces (una por lote de bronze) y gold las multiplica.
    return df


# --- funciones puras de la casa ---------------------------------------------------------------


def limpiar_viajes(trips: DataFrame, meses: list[str] | None = None) -> DataFrame:
    """Tipos, duración, empresa, total pagado y filtros de outliers.

    Filtros: distancia > 0 y < 100 mi, tarifa base > 0, duración entre 1 y 180 min,
    pickup dentro del rango de meses (si se indica) y ubicación de recogida no nula.
    Agrega pickup_date (fecha de recogida). Conserva `_hash_fila`, `_id_lote` y `_fecha_ingesta`
    si la entrada las trae.
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
        *_metadatos_presentes(trips),
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


def clima_diario(clima_bronze: DataFrame) -> DataFrame:
    """Clima de bronze (fecha, lluvia_mm, temperatura) -> (fecha, lluvia_mm, temp_media_c).

    Bronze ya trae una fila por día; aquí solo se pone la fecha como date y la temperatura con
    el nombre que usa silver. Conserva `_hash_fila`, `_id_lote` y `_fecha_ingesta` si existen.
    """
    return clima_bronze.select(
        F.to_date("fecha").alias("fecha"),
        F.col("lluvia_mm").cast("double").alias("lluvia_mm"),
        F.col("temperatura").cast("double").alias("temp_media_c"),
        *_metadatos_presentes(clima_bronze),
    )


def limpiar_taxi_zones(df: DataFrame) -> DataFrame:
    """Zonas de bronze (todo texto) -> LocationID como entero y las otras tres columnas.

    Conserva `_hash_fila`, `_id_lote` y `_fecha_ingesta` si existen.
    """
    return df.select(
        F.col("LocationID").cast("int").alias("LocationID"),
        F.col("Borough"),
        F.col("Zone"),
        F.col("service_zone"),
        *_metadatos_presentes(df),
    )


def enriquecer(trips: DataFrame, zonas: DataFrame, clima: DataFrame) -> DataFrame:
    """Une zona (por PULocationID) y clima (por pickup_date). Left joins: no pierde viajes.

    zona = nombre de la zona de recogida; si no está en el lookup, 'Zona <id>'. Aquí es donde
    una tabla duplicada se multiplica: cada fila repetida de zonas o de clima repite el viaje.
    Gold la usa para armar la entrada de sus tablas (así el cambio que cada equipo firme en
    esta función sigue viviendo en silver.py).
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


# --- el paso ----------------------------------------------------------------------------------


def _preparar_viajes(mes: str):
    """Limpia, deduplica y valida los viajes del mes. Devuelve la función que usa el traslado."""

    def preparar(df: DataFrame) -> DataFrame:
        limpio = deduplicar(limpiar_viajes(df, [mes]))
        quality.validar(
            limpio,
            nombre="silver.fhvhv",
            llaves=("pickup_datetime", "pickup_date", "pu_location_id", "empresa"),
            rangos={
                "distancia_mi": (0, DISTANCIA_MAX_MI),
                "tarifa_base": (0, None),
                "duracion_min": (DURACION_MIN_MIN, DURACION_MAX_MIN),
            },
        )
        return limpio

    return preparar


def _preparar_clima(df: DataFrame) -> DataFrame:
    limpio = deduplicar(clima_diario(df))
    quality.validar(limpio, nombre="silver.clima", llaves=("fecha",))
    return limpio


def _preparar_zonas(df: DataFrame) -> DataFrame:
    limpio = deduplicar(limpiar_taxi_zones(df))
    quality.validar(limpio, nombre="silver.taxi_zones", llaves=("LocationID",))
    return limpio


def _silver_de_una_tabla(spark: Any, corrida: Any, tabla: str, mes: str, preparar) -> Resultado:
    """La puerta decide; si pasa, bronze -> preparar -> silver (reemplaza mes=<mes>/)."""
    entorno = corrida.entorno
    # taxi_zones no se parte por mes: en el lake no lleva mes y en la tabla de control es 'sin_mes'.
    if tabla == TABLA_ZONAS:
        mes_en_lake = None
        mes_en_control = MES_SIN_MES
    else:
        mes_en_lake = mes
        mes_en_control = mes

    fuente = ruta_lake(entorno, "bronze", tabla, mes_en_lake)

    def trabajo() -> tuple[int, int]:
        return mover_entre_capas(spark, entorno, mes, tabla, "bronze", "silver", preparar)

    return con_control(corrida, tabla, CAPA, mes_en_control, fuente, trabajo)


def main(spark: Any, corrida: Any) -> list[Resultado]:
    """Silver de los meses de la corrida (sin banner ni cierre); un Resultado por tabla."""
    resultados: list[Resultado] = []
    for mes in corrida.meses:
        resultados.append(
            _silver_de_una_tabla(spark, corrida, TABLA_VIAJES, mes, _preparar_viajes(mes))
        )
        resultados.append(_silver_de_una_tabla(spark, corrida, TABLA_ZONAS, mes, _preparar_zonas))
        resultados.append(_silver_de_una_tabla(spark, corrida, TABLA_CLIMA, mes, _preparar_clima))
    return resultados
