from __future__ import annotations

from datetime import date

import pytest

from pipeline import quality
from pipeline.gold import COLUMNAS, metricas_diarias_zona
from pipeline.silver import clima_diario, enriquecer, limpiar_viajes

MESES = ["2024-01"]

ESQUEMA_SILVER = (
    "pickup_date date, zona string, empresa string, total_pagado double, propina double, "
    "distancia_mi double, lluvia_mm double"
)
LLAVES_GOLD = ("fecha", "zona", "empresa")


def _gold_de_muestra(muestra_viajes, muestra_zonas, muestra_clima_raw):
    return metricas_diarias_zona(
        enriquecer(
            limpiar_viajes(muestra_viajes, MESES), muestra_zonas, clima_diario(muestra_clima_raw)
        )
    )


def test_metricas_valores_conocidos(spark):
    silver = spark.createDataFrame(
        [
            (date(2024, 1, 1), "A", "Uber", 10.0, 1.0, 2.0, 3.5),
            (date(2024, 1, 1), "A", "Uber", 20.0, 3.0, 4.0, 3.5),
            (date(2024, 1, 1), "A", "Lyft", 8.0, 0.0, 1.0, 3.5),
            (date(2024, 1, 1), "B", "Uber", 5.0, 0.0, 1.0, 3.5),
            (date(2024, 1, 2), "A", "Uber", 7.0, 0.5, 6.0, None),
        ],
        ESQUEMA_SILVER,
    )

    gold = metricas_diarias_zona(silver)
    assert gold.columns == COLUMNAS

    filas = {(r["fecha"], r["zona"], r["empresa"]): r for r in gold.collect()}
    a1 = filas[(date(2024, 1, 1), "A", "Uber")]
    assert a1["viajes"] == 2
    assert a1["ingreso_total"] == 30.0
    assert a1["propina_promedio"] == 2.0
    assert a1["distancia_promedio"] == 3.0
    assert a1["lluvia_mm"] == 3.5

    assert filas[(date(2024, 1, 1), "A", "Lyft")]["viajes"] == 1  # misma zona, otra empresa
    b1 = filas[(date(2024, 1, 1), "B", "Uber")]
    assert b1["viajes"] == 1 and b1["propina_promedio"] == 0.0
    assert filas[(date(2024, 1, 2), "A", "Uber")]["lluvia_mm"] is None


def test_metricas_pasan_calidad_y_clave_unica(spark):
    silver = spark.createDataFrame(
        [
            (date(2024, 1, 1), "A", "Uber", 10.0, 1.0, 2.0, 3.5),
            (date(2024, 1, 1), "A", "Uber", 20.0, 3.0, 4.0, 3.5),
        ],
        ESQUEMA_SILVER,
    )
    gold = metricas_diarias_zona(silver)
    quality.validar(
        gold,
        nombre="gold",
        llaves=LLAVES_GOLD,
        rangos={"viajes": (1, None), "distancia_promedio": (0, 100)},
        clave_unica=LLAVES_GOLD,
    )
    assert gold.count() == 1


def test_pipeline_muestra_de_punta_a_punta(muestra_viajes, muestra_zonas, muestra_clima_raw):
    gold = _gold_de_muestra(muestra_viajes, muestra_zonas, muestra_clima_raw)

    assert gold.columns == COLUMNAS
    assert gold.agg({"viajes": "sum"}).first()[0] == 90
    quality.validar(
        gold,
        nombre="gold",
        llaves=LLAVES_GOLD,
        rangos={"viajes": (1, None), "distancia_promedio": (0, 100)},
        clave_unica=LLAVES_GOLD,
    )


@pytest.mark.parametrize("columna", LLAVES_GOLD)
def test_llaves_gold_no_nulas_en_muestra(muestra_viajes, muestra_zonas, muestra_clima_raw, columna):
    gold = _gold_de_muestra(muestra_viajes, muestra_zonas, muestra_clima_raw)
    assert gold.where(f"{columna} IS NULL").count() == 0


def test_escribir_gold_particiona_por_mes_y_conserva_columnas_en_el_archivo(spark, tmp_path):
    """Snowflake carga los Parquet con MATCH_BY_COLUMN_NAME: el archivo debe traer todas
    las columnas del contrato (incluida fecha) en orden, y la carpeta debe ser mes=YYYY-MM."""
    from pipeline import io

    silver = spark.createDataFrame(
        [
            (date(2024, 1, 1), "A", "Uber", 10.0, 1.0, 2.0, 3.5),
            (date(2024, 2, 1), "B", "Lyft", 5.0, 0.0, 1.0, 0.0),
        ],
        ESQUEMA_SILVER,
    )
    cfg = {"rutas": {"gold": str(tmp_path)}}
    io.escribir_gold(metricas_diarias_zona(silver), cfg)

    carpeta = tmp_path / "daily_zone_metrics" / "mes=2024-01"
    assert carpeta.is_dir()
    assert (tmp_path / "daily_zone_metrics" / "mes=2024-02").is_dir()
    archivos = sorted(carpeta.glob("*.parquet"))
    assert archivos
    assert spark.read.parquet(str(archivos[0])).columns == COLUMNAS
