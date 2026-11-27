"""Capa gold: las tablas de negocio. Cada una responde una pregunta.

Ejemplo de la casa (NO es una pregunta del Taller): «¿A qué hora del día y en qué barrio se paga
más por milla?». Se responde con `tarifa_por_milla_por_barrio`, que escribe
`gold/tarifa_por_milla_barrio/mes=AAAA-MM/`.

Cómo se arma una tabla de gold (la receta de `main`, por mes y por tabla):

    leer silver (fhvhv, taxi_zones, clima) -> silver.enriquecer(...) -> tu función
        -> validar -> escribir_capa (reemplaza mes=<mes>/)

Tu función recibe el `enriquecido` (viajes con barrio, zona y clima) y devuelve la tabla de gold.
Para agregar la tuya: escribe la función y súmala al diccionario TABLAS_GOLD (y su CREATE TABLE a
carga.py). Gold no tiene huecos.

Un detalle que se ve al reprocesar: `enriquecer` une zonas y clima, así que si silver trae las
tablas duplicadas (silver no deduplica todavía) cada viaje se repite una vez por cada fila
repetida de zonas y de clima: con dos copias de cada tabla, ×2 · ×2 · ×2 = ×8 viajes.
"""

from __future__ import annotations

from typing import Any

from pyspark.sql import DataFrame
from pyspark.sql import functions as F

from pipeline import quality, silver
from pipeline.herramientas.capas import escribir_capa, leer_capa
from pipeline.herramientas.control import con_control
from pipeline.herramientas.corrida import Resultado
from pipeline.herramientas.rutas import (
    TABLA_CLIMA,
    TABLA_VIAJES,
    TABLA_ZONAS,
    ruta_lake,
)

CAPA = "gold"

# --- el ejemplo de la casa: tarifa por milla por barrio y franja ------------------------------

COLUMNAS_TARIFA_POR_MILLA = [
    "fecha",
    "borough",
    "franja",
    "viajes",
    "distancia_total_mi",
    "ingreso_total",
    "tarifa_por_milla",
]

# Para los viajes cuya zona de recogida no está en el lookup (el barrio queda nulo).
BARRIO_DESCONOCIDO = "Desconocido"


def _franja_del_dia(hora: F.Column) -> F.Column:
    """madrugada (0 a 5 h), mañana (6 a 11), tarde (12 a 17) o noche (18 a 23)."""
    return (
        F.when(hora < 6, "madrugada")
        .when(hora < 12, "mañana")
        .when(hora < 18, "tarde")
        .otherwise("noche")
    )


def tarifa_por_milla_por_barrio(enriquecido: DataFrame) -> DataFrame:
    """Por fecha, barrio y franja del día: viajes, millas, ingreso y cuánto se paga por milla.

    tarifa_por_milla = ingreso_total / distancia_total_mi. Se calcula con las sumas completas y
    se redondea al final; así el redondeo de las sumas no mueve el cociente.
    """
    con_franja = enriquecido.select(
        F.col("pickup_date").alias("fecha"),
        F.coalesce(F.col("borough"), F.lit(BARRIO_DESCONOCIDO)).alias("borough"),
        _franja_del_dia(F.hour("pickup_datetime")).alias("franja"),
        F.col("distancia_mi"),
        F.col("total_pagado"),
    )
    return (
        con_franja.groupBy("fecha", "borough", "franja")
        .agg(
            F.count(F.lit(1)).alias("viajes"),
            F.sum("distancia_mi").alias("distancia"),
            F.sum("total_pagado").alias("ingreso"),
        )
        .select(
            "fecha",
            "borough",
            "franja",
            "viajes",
            F.round("distancia", 2).alias("distancia_total_mi"),
            F.round("ingreso", 2).alias("ingreso_total"),
            F.round(F.col("ingreso") / F.col("distancia"), 2).alias("tarifa_por_milla"),
        )
        .select(*COLUMNAS_TARIFA_POR_MILLA)
    )


# --- la tabla del EQUIPO 4: viajes por rango de distancia y día --------------------------------
#
# Pregunta: «En enero de 2024, ¿los viajes largos caen más que los cortos los días con lluvia?»
# Grano: una fila por fecha de recogida y rango de distancia (3 rangos x 31 días = 93 filas).
# La lluvia del día se guarda en cada fila de ese día (la misma en los 3 rangos): para contar días
# con lluvia se usa COUNT(DISTINCT fecha) y no se suma lluvia_mm (trampa 1 del Taller 1).

COLUMNAS_RANGO_DISTANCIA = [
    "fecha",
    "rango_distancia",
    "lluvia_mm",
    "viajes",
    "distancia_total_mi",
    "ingreso_total",
]

# Límites de los rangos, en millas. silver ya dejó solo viajes con 0 < distancia < 100 mi, así que
# todo viaje cae en un rango y no hay nulos.
LIMITE_CORTO_MI = 2.0
LIMITE_LARGO_MI = 5.0


def _rango_distancia(distancia: F.Column) -> F.Column:
    """corto (menos de 2 mi), medio (de 2 a menos de 5 mi) o largo (5 mi o más)."""
    return (
        F.when(distancia < LIMITE_CORTO_MI, "corto")
        .when(distancia < LIMITE_LARGO_MI, "medio")
        .otherwise("largo")
    )


def equipo_4_rango_distancia(enriquecido: DataFrame) -> DataFrame:
    """Por fecha y rango de distancia: lluvia del día, viajes, millas e ingreso.

    lluvia_mm es la del día (llega por enriquecer); si el clima de un día faltara, queda nula y
    no se inventa. Viajes, millas e ingreso son sumas: se pueden sumar entre días y rangos.
    """
    con_rango = enriquecido.select(
        F.col("pickup_date").alias("fecha"),
        _rango_distancia(F.col("distancia_mi")).alias("rango_distancia"),
        F.col("lluvia_mm"),
        F.col("distancia_mi"),
        F.col("total_pagado"),
    )
    return (
        con_rango.groupBy("fecha", "rango_distancia")
        .agg(
            F.max("lluvia_mm").alias("lluvia_mm"),
            F.count(F.lit(1)).alias("viajes"),
            F.round(F.sum("distancia_mi"), 2).alias("distancia_total_mi"),
            F.round(F.sum("total_pagado"), 2).alias("ingreso_total"),
        )
        .select(*COLUMNAS_RANGO_DISTANCIA)
    )


# nombre de la tabla en gold -> función que la arma a partir del enriquecido. El equipo agrega la
# suya aquí.
TABLAS_GOLD = {
    "tarifa_por_milla_barrio": tarifa_por_milla_por_barrio,
    "equipo_4_rango_distancia": equipo_4_rango_distancia,
}


# --- el paso ----------------------------------------------------------------------------------


def _gold_de_una_tabla(spark: Any, corrida: Any, mes: str, nombre: str, construir) -> Resultado:
    """La puerta decide; si pasa, silver -> enriquecer -> tu función -> validar -> gold."""
    entorno = corrida.entorno
    fuente = ruta_lake(entorno, "silver", TABLA_VIAJES, mes)

    def trabajo() -> tuple[int, int]:
        viajes = leer_capa(spark, entorno, "silver", TABLA_VIAJES, mes)
        zonas = leer_capa(spark, entorno, "silver", TABLA_ZONAS, mes)
        clima = leer_capa(spark, entorno, "silver", TABLA_CLIMA, mes)
        enriquecido = silver.enriquecer(viajes, zonas, clima)
        # Las filas que entran al cálculo: aquí se nota si silver duplicó (cada tabla repetida
        # multiplica los viajes).
        leidas = enriquecido.count()

        gold = construir(enriquecido)
        quality.validar(gold, nombre=f"gold.{nombre}")
        escritas = escribir_capa(gold, entorno, CAPA, nombre, mes)
        return leidas, escritas

    return con_control(corrida, nombre, CAPA, mes, fuente, trabajo)


def main(spark: Any, corrida: Any) -> list[Resultado]:
    """Gold de los meses de la corrida (sin banner ni cierre); un Resultado por tabla."""
    resultados: list[Resultado] = []
    for mes in corrida.meses:
        for nombre, construir in TABLAS_GOLD.items():
            resultados.append(_gold_de_una_tabla(spark, corrida, mes, nombre, construir))
    return resultados


# Comentario al final de src
