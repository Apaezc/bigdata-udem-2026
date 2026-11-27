"""Fixtures comunes. Las tres primeras (spark, raiz_lake, control_en_memoria) son el contrato de la
clase 7: están congeladas y todos los paquetes las usan. Las demás fixtures van en
tests/<paquete>_fixtures.py.

Las que siguen después de la línea «TRANSITORIO» son las muestras de tests/data que usan
test_silver y test_gold. Se borran cuando esos archivos migren a sus propias fixtures.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from pipeline.herramientas.capas import clima_a_filas

DATA = Path(__file__).resolve().parent / "data"
MES = "2024-01"


@pytest.fixture(scope="session")
def spark():
    """Spark del Code Editor (local[2]) SIN S3: sirve para todo lo que lee y escribe file://."""
    from pipeline.engine import get_spark

    session = get_spark("code_editor")
    yield session
    session.stop()


@pytest.fixture
def raiz_lake(tmp_path, monkeypatch):
    """El lake de la prueba vive en tmp_path: PIPELINE_RAIZ_LAKE=file://<tmp_path>.

    ruta_lake("dev", "silver", "fhvhv", "2024-01") queda en file://<tmp_path>/dev/silver/fhvhv/mes=2024-01.
    Devuelve el Path de la raíz.
    """
    monkeypatch.setenv("PIPELINE_RAIZ_LAKE", f"file://{tmp_path}")
    return tmp_path


@pytest.fixture
def control_en_memoria():
    """La tabla de control en memoria (sin Snowflake). Devuelve el ControlEnMemoria instalado."""
    from pipeline.herramientas.control import ControlEnMemoria, instalar_backend

    backend = ControlEnMemoria()
    instalar_backend(backend)
    yield backend
    instalar_backend(None)


# --- TRANSITORIO: muestras de tests/data ---------------------------------------------------


@pytest.fixture(scope="session")
def muestra_viajes(spark):
    return spark.read.option("header", True).csv(str(DATA / "fhvhv_tripdata_sample.csv"))


@pytest.fixture(scope="session")
def muestra_zonas(spark):
    return spark.read.option("header", True).csv(str(DATA / "taxi_zone_lookup_sample.csv"))


@pytest.fixture(scope="session")
def muestra_clima_raw(spark):
    return spark.read.option("multiLine", True).json(str(DATA / "open_meteo_sample.json"))


@pytest.fixture(scope="session")
def muestra_clima(muestra_clima_raw):
    """El clima de la muestra como queda en bronze: una fila por día (fecha, lluvia_mm, ...)."""
    return clima_a_filas(muestra_clima_raw)


# --- EQUIPO 4: las pruebas de la casa corren solo con la tabla de la casa -------------------


@pytest.fixture(autouse=True)
def solo_la_tabla_de_la_casa(monkeypatch):
    """TABLAS_GOLD y TABLAS_A_CARGAR quedan, en cada prueba, solo con la tabla de la casa.

    Las pruebas del flujo (test_pasos, test_carga, test_correr) cuentan los resultados de UNA tabla.
    La tabla del equipo 4 sigue la misma receta; su registro se comprueba en test_gold y test_carga
    con los diccionarios originales.
    """
    from pipeline import carga

    monkeypatch.setattr(
        carga,
        "TABLAS_A_CARGAR",
        [e for e in carga.TABLAS_A_CARGAR if e["gold"] == "tarifa_por_milla_barrio"],
    )
    try:
        from pipeline import gold
    except ImportError:  # sin pyspark (VM de Airflow): no hay gold que recortar
        return
    monkeypatch.setattr(
        gold, "TABLAS_GOLD", {"tarifa_por_milla_barrio": gold.tarifa_por_milla_por_barrio}
    )
