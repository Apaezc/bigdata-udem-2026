from __future__ import annotations

from pathlib import Path

import pytest

DATA = Path(__file__).resolve().parent / "data"
MES = "2024-01"


@pytest.fixture(scope="session")
def spark():
    from pipeline.engine import get_spark

    session = get_spark("local")
    yield session
    session.stop()


@pytest.fixture(scope="session")
def muestra_viajes(spark):
    return spark.read.option("header", True).csv(str(DATA / "fhvhv_tripdata_sample.csv"))


@pytest.fixture(scope="session")
def muestra_zonas(spark):
    return spark.read.option("header", True).csv(str(DATA / "taxi_zone_lookup_sample.csv"))


@pytest.fixture(scope="session")
def muestra_clima_raw(spark):
    return spark.read.option("multiLine", True).json(str(DATA / "open_meteo_sample.json"))
