"""El paso snowflake (carga.py): verificar con Athena y cargar gold, con control (no crea tablas).

Athena y Snowflake son falsos (solo anotan cómo los llamaron); la tabla de control es la de memoria.
"""

from __future__ import annotations

import re
import subprocess
import sys

import pytest

from hueco import MES, corrida_a_mano
from pipeline import carga
from pipeline.gold import COLUMNAS_TARIFA_POR_MILLA
from pipeline.herramientas import bodega

pytest_plugins = ["p1_fixtures", "p4_fixtures"]


@pytest.fixture(autouse=True)
def lake_de_prueba(entorno_limpio, raiz_lake):
    """Las rutas del lake (la fuente que se anota en el control) salen del tmp_path, no de AWS."""


class Falsos:
    """Athena y cargar_gold falsos: guardan las llamadas en orden."""

    def __init__(self, monkeypatch, filas=7):
        self.llamadas: list[tuple] = []
        self.filas = filas
        monkeypatch.setattr(
            carga,
            "verificar_esquema_con_athena",
            lambda athena, snowflake, conexion=None: self.llamadas.append(
                ("athena", athena, snowflake)
            ),
        )

        def cargar(tabla, carpeta_gold, mes=None, conexion=None, **opciones):
            self.llamadas.append(("cargar", tabla, carpeta_gold, mes))
            self.opciones = opciones
            return self.filas

        monkeypatch.setattr(carga, "cargar_gold", cargar)


def test_main_verifica_y_carga_en_ese_orden(control_en_memoria, monkeypatch):
    falsos = Falsos(monkeypatch)
    resultados = carga.main(corrida_a_mano())

    assert [llamada[0] for llamada in falsos.llamadas] == ["athena", "cargar"]
    assert resultados == [
        carga.Resultado("tarifa_por_milla_barrio", "snowflake", MES, 7, 7, "REGISTRÓ")
    ]


def test_la_tabla_de_snowflake_es_la_del_entorno(control_en_memoria, monkeypatch):
    falsos = Falsos(monkeypatch)
    carga.main(corrida_a_mano())

    athena = falsos.llamadas[0]
    assert athena == (
        "athena",
        "dev_gold_tarifa_por_milla_barrio",
        "BIGDATA.DEV.TARIFA_POR_MILLA_BARRIO",
    )
    sql = falsos.opciones["sql_para_crearla"]
    assert sql.startswith(
        "USE ROLE BIGDATA_DEV;\nUSE WAREHOUSE BIGDATA_WH;\nUSE DATABASE BIGDATA;\n"
        "CREATE TABLE IF NOT EXISTS BIGDATA.DEV.TARIFA_POR_MILLA_BARRIO ("
    )
    assert falsos.llamadas[1] == (
        "cargar",
        "BIGDATA.DEV.TARIFA_POR_MILLA_BARRIO",
        "tarifa_por_milla_barrio",
        MES,
    )


def test_registra_en_la_tabla_de_control(control_en_memoria, monkeypatch):
    Falsos(monkeypatch)
    carga.main(corrida_a_mano())

    assert len(control_en_memoria.registros) == 1
    registro = control_en_memoria.registros[0]
    assert (registro["capa"], registro["tabla"], registro["mes"]) == (
        "snowflake",
        "tarifa_por_milla_barrio",
        MES,
    )
    assert registro["filas"] == 7
    assert registro["fuente"].endswith("/dev/gold/tarifa_por_milla_barrio/mes=2024-01")


def test_sin_reprocesar_la_segunda_vez_se_salta_y_no_toca_snowflake(
    control_en_memoria, monkeypatch
):
    falsos = Falsos(monkeypatch)
    carga.main(corrida_a_mano())
    llamadas_antes = len(falsos.llamadas)

    segunda = carga.main(corrida_a_mano())

    assert [r.decision for r in segunda] == ["SE SALTÓ"]
    assert len(falsos.llamadas) == llamadas_antes
    assert len(control_en_memoria.registros) == 1


def test_con_reprocesar_vuelve_a_cargar(control_en_memoria, monkeypatch):
    falsos = Falsos(monkeypatch)
    carga.main(corrida_a_mano())
    segunda = carga.main(corrida_a_mano(reprocesar=True))

    assert [r.decision for r in segunda] == ["REGISTRÓ"]
    assert [llamada[0] for llamada in falsos.llamadas].count("cargar") == 2


def test_si_la_carga_falla_no_queda_registro(control_en_memoria, monkeypatch):
    Falsos(monkeypatch)

    def cargar_roto(*argumentos, **opciones):
        raise RuntimeError("COPY falló")

    monkeypatch.setattr(carga, "cargar_gold", cargar_roto)
    try:
        carga.main(corrida_a_mano())
    except RuntimeError:
        pass
    assert control_en_memoria.registros == []


def test_el_ddl_de_la_casa_tiene_las_columnas_de_gold():
    """El CREATE TABLE y la tabla de gold hablan de las mismas columnas, en el mismo orden."""
    cuerpo = re.search(r"\((.*)\)", carga.DDL_TARIFA_POR_MILLA).group(1)
    columnas = [definicion.split()[0].lower() for definicion in cuerpo.split(", ")]
    assert columnas == COLUMNAS_TARIFA_POR_MILLA


def test_el_ddl_crea_solo_si_no_existe():
    assert "IF NOT EXISTS" in carga.DDL_TARIFA_POR_MILLA
    assert "{tabla}" in carga.DDL_TARIFA_POR_MILLA


def test_tablas_a_cargar_tiene_la_de_la_casa():
    assert [e["gold"] for e in carga.TABLAS_A_CARGAR] == ["tarifa_por_milla_barrio"]


def test_el_codigo_no_crea_tablas():
    assert not hasattr(carga, "crear_tabla")
    assert not hasattr(bodega, "crear_tabla")


def test_sin_la_tabla_el_error_imprime_el_create_para_snowsight(control_en_memoria):
    """cargar_gold real contra un Snowflake donde DESCRIBE TABLE falla: la tabla no existe."""

    class Cursor:
        sentencias: list[str] = []

        def execute(self, sql, valores=None):
            self.sentencias.append(sql)
            if sql.startswith("DESCRIBE"):
                raise RuntimeError("Table does not exist")

    class Conexion:
        def cursor(self):
            return cursor

    cursor = Cursor()
    sql = carga.sql_para_snowsight(
        "dev", "BIGDATA.DEV.TARIFA_POR_MILLA_BARRIO", carga.DDL_TARIFA_POR_MILLA
    )
    with pytest.raises(RuntimeError) as error:
        bodega.cargar_gold(
            "BIGDATA.DEV.TARIFA_POR_MILLA_BARRIO",
            "tarifa_por_milla_barrio",
            mes=MES,
            conexion=Conexion(),
            sql_para_crearla=sql,
        )

    mensaje = str(error.value)
    assert "USE ROLE BIGDATA_DEV;" in mensaje
    assert "USE WAREHOUSE BIGDATA_WH;" in mensaje
    assert "USE DATABASE BIGDATA;" in mensaje
    assert "CREATE TABLE IF NOT EXISTS BIGDATA.DEV.TARIFA_POR_MILLA_BARRIO (FECHA DATE" in mensaje
    assert "vuelve a correr cargar_snowflake" in mensaje
    assert not any(s.startswith(("CREATE", "COPY")) for s in cursor.sentencias)


def test_el_paso_snowflake_no_importa_pyspark():
    """La VM de Airflow no tiene Spark: carga.py tiene que cargar sin él."""
    codigo = "import sys, pipeline.carga; sys.exit(1 if 'pyspark' in sys.modules else 0)"
    resultado = subprocess.run(
        [sys.executable, "-c", codigo], capture_output=True, text=True, env=_entorno_con_src()
    )
    assert resultado.returncode == 0, resultado.stderr


def _entorno_con_src() -> dict:
    """El proceso hijo no hereda el sys.path de pytest: se le pasa src/ por PYTHONPATH."""
    import os
    from pathlib import Path

    src = str(Path(__file__).resolve().parents[1] / "src")
    entorno = dict(os.environ)
    entorno["PYTHONPATH"] = src + os.pathsep + entorno.get("PYTHONPATH", "")
    return entorno
