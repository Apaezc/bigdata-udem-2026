"""Pruebas de las funciones del equipo en bronze (agregar_metadatos, la puerta y el registro).

Son las mismas en `make test` y en `probar_mis_funciones(...)` del cuaderno. Sin red ni Snowflake:
la tabla de control es la de memoria. Mientras agregar_metadatos traiga la marca
`# PENDIENTE(equipo)`, sus pruebas salen omitidas con «PENDIENTE: ...» (usa `pytest -rs`).
"""

from __future__ import annotations

from datetime import UTC, datetime

import pytest

from hueco import corrida_a_mano, saltar_si_pendiente
from pipeline import bronze
from pipeline.herramientas.capas import COLUMNAS_METADATOS

pytest_plugins = ["p1_fixtures", "p4_fixtures"]

FECHA = datetime(2026, 11, 23, 15, 0, 0, tzinfo=UTC)
ESQUEMA = "letra string, numero int"


def _entrada(spark_equipo):
    return spark_equipo.createDataFrame([("a", 1), ("b", None), ("c", 3)], ESQUEMA)


def _con_metadatos(spark_equipo, df=None):
    saltar_si_pendiente(
        bronze.agregar_metadatos, "agregar_metadatos todavía no agrega las columnas de metadatos"
    )
    if df is None:
        df = _entrada(spark_equipo)
    return bronze.agregar_metadatos(df, "https://fuente/x", "x.parquet", "lote1", FECHA)


# --- agregar_metadatos --------------------------------------------------------------------------


def test_agregar_metadatos_deja_las_cinco_columnas_en_orden(spark_equipo):
    resultado = _con_metadatos(spark_equipo)
    assert resultado.columns == ["letra", "numero", *COLUMNAS_METADATOS]


def test_agregar_metadatos_no_toca_las_columnas_originales(spark_equipo):
    resultado = _con_metadatos(spark_equipo)
    originales = {tuple(f) for f in _entrada(spark_equipo).collect()}
    despues = {tuple(f) for f in resultado.select("letra", "numero").collect()}
    assert despues == originales
    assert resultado.count() == 3


def test_agregar_metadatos_llena_fuente_archivo_lote_y_fecha(spark_equipo):
    fila = _con_metadatos(spark_equipo).first()
    assert fila["_fuente"] == "https://fuente/x"
    assert fila["_archivo_origen"] == "x.parquet"
    assert fila["_id_lote"] == "lote1"
    assert fila["_fecha_ingesta"] is not None


def test_el_hash_es_igual_para_filas_iguales_y_distinto_si_cambia_un_valor(spark_equipo):
    saltar_si_pendiente(bronze.agregar_metadatos, "agregar_metadatos todavía no calcula _hash_fila")
    filas = [("a", 1), ("a", 1), ("a", 2), ("b", None), ("b", 0)]
    df = spark_equipo.createDataFrame(filas, ESQUEMA)
    hashes = [f["_hash_fila"] for f in _con_metadatos(spark_equipo, df).collect()]

    assert hashes[0] == hashes[1]  # filas iguales
    assert hashes[0] != hashes[2]  # cambia un valor
    assert hashes[3] != hashes[4]  # nulo y cero no son lo mismo


def test_el_hash_no_depende_del_lote(spark_equipo):
    saltar_si_pendiente(bronze.agregar_metadatos, "agregar_metadatos todavía no calcula _hash_fila")
    df = _entrada(spark_equipo)
    uno = bronze.agregar_metadatos(df, "f", "a", "lote1", FECHA).select("_hash_fila").collect()
    dos = bronze.agregar_metadatos(df, "f", "a", "lote2", FECHA).select("_hash_fila").collect()
    assert uno == dos  # por eso un reproceso del mismo archivo se puede deduplicar


# --- la puerta: debe_ingestar y registrar_ingesta -----------------------------------------------


def _registrar(corrida, tabla="fhvhv", mes="2024-01"):
    bronze.registrar_ingesta(corrida, tabla, mes, "https://fuente/x", 100, 100, FECHA)


def test_debe_ingestar_ingesta_si_no_hay_registro(control_en_memoria):
    assert bronze.debe_ingestar(corrida_a_mano(), "fhvhv", "2024-01") is True


def test_debe_ingestar_salta_si_hay_registro_y_no_se_reprocesa(control_en_memoria):
    _registrar(corrida_a_mano())
    assert bronze.debe_ingestar(corrida_a_mano(reprocesar=False), "fhvhv", "2024-01") is False


def test_debe_ingestar_ingesta_con_reprocesar_aunque_haya_registro(control_en_memoria):
    _registrar(corrida_a_mano())
    assert bronze.debe_ingestar(corrida_a_mano(reprocesar=True), "fhvhv", "2024-01") is True


def test_debe_ingestar_distingue_tabla_y_mes(control_en_memoria):
    _registrar(corrida_a_mano())
    assert bronze.debe_ingestar(corrida_a_mano(), "clima", "2024-01") is True
    assert bronze.debe_ingestar(corrida_a_mano(mes="2024-02"), "fhvhv", "2024-02") is True


def test_registrar_ingesta_llama_a_registrar_control_con_tabla_capa_mes_filas_y_leidas(
    control_en_memoria,
):
    bronze.registrar_ingesta(
        corrida_a_mano(), "fhvhv", "2024-01", "https://fuente/x", 1000, 990, FECHA
    )
    assert len(control_en_memoria.registros) == 1
    registro = control_en_memoria.registros[0]
    assert registro["tabla"] == "fhvhv"
    assert registro["capa"] == "bronze"
    assert registro["mes"] == "2024-01"
    assert registro["filas"] == 990
    assert registro["leidas"] == 1000
    assert registro["fuente"] == "https://fuente/x"
    assert registro["entorno"] == "dev"


def test_despues_de_registrar_la_puerta_salta(control_en_memoria):
    corrida = corrida_a_mano()
    assert bronze.debe_ingestar(corrida, "fhvhv", "2024-01") is True
    _registrar(corrida)
    assert bronze.debe_ingestar(corrida, "fhvhv", "2024-01") is False


@pytest.mark.parametrize("nombre", ["agregar_metadatos", "debe_ingestar", "registrar_ingesta"])
def test_las_firmas_son_las_del_contrato(nombre):
    import inspect

    esperadas = {
        "agregar_metadatos": ["df", "fuente", "archivo_origen", "id_lote", "fecha_ingesta"],
        "debe_ingestar": ["corrida", "tabla", "mes"],
        "registrar_ingesta": ["corrida", "tabla", "mes", "fuente", "leidas", "filas", "inicio"],
    }
    assert list(inspect.signature(getattr(bronze, nombre)).parameters) == esperadas[nombre]
