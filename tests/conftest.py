"""Fixtures comunes. Las tres primeras (spark, raiz_lake, control_en_memoria) son el contrato de la
clase 7: están congeladas y todos los paquetes las usan. Las demás fixtures van en
tests/<paquete>_fixtures.py.

Las que siguen después de la línea «TRANSITORIO» son de las clases 1 a 6: las pruebas viejas
(test_bronze, test_silver, test_gold, test_ingesta_alumno) todavía las usan. Se borran cuando esos
archivos migren a sus propias fixtures (P2 y P4).
"""

from __future__ import annotations

import shutil
from argparse import Namespace
from pathlib import Path

import pytest

from pipeline import bronze, io

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


# --- TRANSITORIO: fixtures de las clases 1 a 6 ---------------------------------------------------


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
    return bronze.clima_a_filas(muestra_clima_raw)


def poner_crudos(spark, base: Path, tmp: Path) -> None:
    """Deja en <base>/_crudo los tres archivos de la muestra, como si ya se hubieran descargado."""
    viajes = (
        spark.read.option("header", True)
        .option("inferSchema", True)
        .csv(str(DATA / "fhvhv_tripdata_sample.csv"))
    )
    carpeta_parquet = tmp / "viajes_parquet"
    viajes.coalesce(1).write.mode("overwrite").parquet(str(carpeta_parquet))
    archivo_parquet = next(carpeta_parquet.glob("part-*.parquet"))

    destino_viajes = Path(io.ruta_crudo(str(base), io.VIAJES, io.nombre_viajes(MES), MES))
    destino_zonas = Path(io.ruta_crudo(str(base), io.ZONAS, io.NOMBRE_ZONAS))
    destino_clima = Path(io.ruta_crudo(str(base), io.CLIMA, io.nombre_clima(MES), MES))
    for destino in (destino_viajes, destino_zonas, destino_clima):
        destino.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(archivo_parquet, destino_viajes)
    shutil.copyfile(DATA / "taxi_zone_lookup_sample.csv", destino_zonas)
    shutil.copyfile(DATA / "open_meteo_sample.json", destino_clima)


@pytest.fixture
def armar_bronze(spark, tmp_path, monkeypatch):
    """Función que arma un bronze local completo (crudo + un lote) a partir de tests/data.

    Se pasa por bronze.main, igual que en la nube; descargar falla para probar que no se usa la red.
    """

    def sin_red(url, destino):
        raise AssertionError(f"No debería descargar nada, pero se pidió {url}")

    monkeypatch.setattr(bronze, "descargar", sin_red)

    def _armar(base: Path) -> None:
        poner_crudos(spark, base, tmp_path / "crudos_tmp")
        cfg = {"rutas": {"bronze": str(base)}}
        bronze.main(spark, cfg, Namespace(meses=[MES]))

    return _armar
