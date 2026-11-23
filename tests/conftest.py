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
