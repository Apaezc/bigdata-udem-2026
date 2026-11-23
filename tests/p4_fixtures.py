"""Fixtures de las pruebas de los pasos (P4): un lake de prueba en disco y la corrida a mano.

`lake` arma, dentro de un tmp_path, el crudo de la muestra (tests/data) y trae los cuatro pasos
como métodos. Todo corre con Spark local y con la tabla de control en memoria: no toca la red, ni
S3, ni Snowflake. Cada paso estrena una corrida (id de lote nuevo), como hace correr.py.
"""

from __future__ import annotations

import shutil
from pathlib import Path

import pytest

from hueco import ENTORNO, MES
from pipeline.herramientas import archivos
from pipeline.herramientas.capas import leer_capa
from pipeline.herramientas.corrida import Corrida, cargar_configuracion
from pipeline.herramientas.rutas import (
    TABLA_CLIMA,
    TABLA_VIAJES,
    TABLA_ZONAS,
    ruta_del_crudo,
    ruta_lake,
)

DATA = Path(__file__).resolve().parent / "data"


@pytest.fixture(scope="session")
def spark_equipo():
    """Spark para las pruebas del equipo.

    Si ya hay una sesión activa (la del cuaderno o la de otra prueba) se usa esa y NO se detiene:
    así probar_mis_funciones no le apaga el Spark al cuaderno. Si no hay, se crea una y se detiene
    al terminar.
    """
    from pyspark.sql import SparkSession

    activa = SparkSession.getActiveSession()
    if activa is not None:
        yield activa
        return
    from pipeline.engine import get_spark

    sesion = get_spark("code_editor")
    yield sesion
    sesion.stop()


def _poner_crudos_de_muestra(spark, tmp: Path) -> None:
    """Deja en <lake>/dev/bronze/_crudo los tres archivos de la muestra, como ya descargados."""
    viajes = (
        spark.read.option("header", True)
        .option("inferSchema", True)
        .csv(str(DATA / "fhvhv_tripdata_sample.csv"))
    )
    carpeta_parquet = tmp / "viajes_parquet"
    viajes.coalesce(1).write.mode("overwrite").parquet(str(carpeta_parquet))
    archivo_parquet = next(carpeta_parquet.glob("part-*.parquet"))

    destinos = {
        archivo_parquet: ruta_del_crudo(ENTORNO, TABLA_VIAJES, MES),
        DATA / "taxi_zone_lookup_sample.csv": ruta_del_crudo(ENTORNO, TABLA_ZONAS),
        DATA / "open_meteo_sample.json": ruta_del_crudo(ENTORNO, TABLA_CLIMA, MES),
    }
    for origen, destino in destinos.items():
        destino_local = archivos.a_ruta_local(destino)
        destino_local.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(origen, destino_local)


class LakeDePrueba:
    """El lake de la prueba con los cuatro pasos como métodos (cada uno con su corrida nueva)."""

    def __init__(self, spark, monkeypatch, control):
        self.spark = spark
        self.monkeypatch = monkeypatch
        self.control = control
        self.llamadas_a_snowflake: list[tuple] = []

    def corrida(self, reprocesar: bool = False) -> Corrida:
        return cargar_configuracion(
            mes=MES, computo="code_editor", limite="1000", reprocesar=reprocesar
        )

    def bronze(self, reprocesar: bool = False):
        from pipeline import bronze

        return bronze.main(self.spark, self.corrida(reprocesar))

    def silver(self, reprocesar: bool = False):
        from pipeline import silver

        return silver.main(self.spark, self.corrida(reprocesar))

    def gold(self, reprocesar: bool = False):
        from pipeline import gold

        return gold.main(self.spark, self.corrida(reprocesar))

    def carga(self, reprocesar: bool = False):
        """El paso snowflake con Athena y Snowflake falsos: solo anotan cómo los llamaron."""
        from pipeline import carga

        llamadas = self.llamadas_a_snowflake
        self.monkeypatch.setattr(
            carga, "verificar_esquema_con_athena", lambda *a, **k: llamadas.append(("athena", a))
        )

        def cargar_falso(tabla, carpeta, mes=None, conexion=None, **opciones):
            llamadas.append(("cargar", (tabla, carpeta, mes)))
            return 7

        self.monkeypatch.setattr(carga, "cargar_gold", cargar_falso)
        return carga.main(self.corrida(reprocesar), conexion=object())

    def tabla(self, capa: str, tabla: str):
        """La tabla de una capa como DataFrame (bronze: todos los lotes completos del mes)."""
        return leer_capa(self.spark, ENTORNO, capa, tabla, MES, lotes="todos")

    def lotes_de_bronze(self, tabla: str) -> list[str]:
        mes = None if tabla == TABLA_ZONAS else MES
        carpeta = archivos.a_ruta_local(ruta_lake(ENTORNO, "bronze", tabla, mes))
        return sorted(p.name for p in carpeta.iterdir() if p.name.startswith("lote="))


@pytest.fixture
def lake(entorno_limpio, raiz_lake, control_en_memoria, spark_equipo, monkeypatch, tmp_path):
    """Lake de prueba con el crudo de la muestra puesto y el control en memoria."""
    _poner_crudos_de_muestra(spark_equipo, tmp_path / "crudos_tmp")
    return LakeDePrueba(spark_equipo, monkeypatch, control_en_memoria)
