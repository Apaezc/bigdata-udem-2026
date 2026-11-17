"""Tabla de control (pipeline.watermark): consultas y registros sin tocar la red.

El conector de Snowflake se reemplaza por uno falso que guarda cada sentencia con sus valores.
"""

from __future__ import annotations

import json
from datetime import UTC, datetime, timedelta, timezone

import pytest

from pipeline import watermark


class CursorFalso:
    def __init__(self, conexion):
        self.conexion = conexion
        self.rowcount = 0

    def execute(self, sql, valores=None):
        self.conexion.sentencias.append((" ".join(sql.split()), valores))
        if "DELETE" in sql:
            self.rowcount = 2

    def fetchall(self):
        return self.conexion.filas


class ConexionFalsa:
    def __init__(self, filas=None):
        self.filas = filas or []
        self.sentencias = []
        self.cerrada = False

    def cursor(self):
        return CursorFalso(self)

    def close(self):
        self.cerrada = True


@pytest.fixture
def conexion(monkeypatch):
    """Reemplaza la apertura de la conexión; guarda los nombres de conexión que se pidieron."""
    falsa = ConexionFalsa()
    falsa.nombres = []

    def abrir(connection_name):
        falsa.nombres.append(connection_name)
        return falsa

    monkeypatch.setattr(watermark, "_abrir_conexion", abrir)
    monkeypatch.delenv(watermark.VARIABLE_CONEXION, raising=False)
    return falsa


def textos(conexion):
    return [sql for sql, _ in conexion.sentencias]


def test_conectar_fija_rol_y_warehouse_y_no_crea_nada(conexion):
    watermark.consultar_watermark("clima", "bronze", "2024-01")
    sentencias = textos(conexion)
    assert sentencias[0] == "USE ROLE ACCOUNTADMIN"
    assert sentencias[1] == "USE WAREHOUSE COMPUTE_WH"
    # El esquema y la tabla los crea Terraform: el módulo no ejecuta DDL ni otorga permisos.
    assert not any(sql.startswith(("CREATE", "GRANT")) for sql in sentencias)


def test_tabla_inexistente_o_sin_permiso_explica_que_hay_que_correr_make_snowflake(conexion):
    class ObjetoNoExiste(Exception):
        errno = 2003

    class CursorSinTabla(CursorFalso):
        def execute(self, sql, valores=None):
            if "BIGDATA.CONTROL.WATERMARK" in sql:
                raise ObjetoNoExiste("does not exist or not authorized")
            super().execute(sql, valores)

    conexion.cursor = lambda: CursorSinTabla(conexion)
    with pytest.raises(RuntimeError, match="make snowflake"):
        watermark.consultar_watermark("clima", "bronze", "2024-01")
    assert conexion.cerrada


def test_consultar_sin_registros_devuelve_lista_vacia(conexion):
    assert watermark.consultar_watermark("clima", "bronze", "2024-01") == "[]"
    assert conexion.cerrada


def test_consultar_parametriza_y_ordena_por_inicio(conexion):
    watermark.consultar_watermark("clima", "bronze", "2024-01")
    sql, valores = conexion.sentencias[-1]
    assert valores == ("clima", "bronze", "2024-01")
    assert "WHERE TABLA = %s AND CAPA = %s AND MES = %s" in sql
    assert sql.endswith("ORDER BY INICIO")
    assert "clima" not in sql and "2024-01" not in sql


def test_consultar_devuelve_json_con_los_registros(conexion):
    conexion.filas = [
        ("https://x/a", "bronze", "clima", "2024-01", 31, datetime(2026, 11, 17, 14, 3, 22), False),
        ("https://x/a", "bronze", "clima", "2024-01", 31, datetime(2026, 11, 18, 9, 0, 0), True),
    ]
    registros = json.loads(watermark.consultar_watermark("clima", "bronze", "2024-01"))
    assert [r["reprocesar"] for r in registros] == [False, True]
    assert registros[0] == {
        "fuente": "https://x/a",
        "capa": "bronze",
        "tabla": "clima",
        "mes": "2024-01",
        "filas": 31,
        "inicio": "2026-11-17T14:03:22",
        "reprocesar": False,
    }


def test_registrar_inserta_una_fila_con_consulta_parametrizada(conexion):
    inicio = datetime(2026, 11, 17, 14, 3, 22)
    watermark.registrar_watermark("https://x/a", "bronze", "clima", "2024-01", 31, inicio, False)
    sql, valores = conexion.sentencias[-1]
    assert sql.startswith("INSERT INTO BIGDATA.CONTROL.WATERMARK")
    assert sql.endswith("VALUES (%s, %s, %s, %s, %s, %s, %s)")
    assert valores == ("https://x/a", "bronze", "clima", "2024-01", 31, inicio, False)
    assert conexion.cerrada


def test_registrar_guarda_el_inicio_en_utc_sin_zona(conexion):
    colombia = timezone(timedelta(hours=-5))
    inicio = datetime(2026, 11, 17, 9, 0, 0, tzinfo=colombia)
    watermark.registrar_watermark("f", "bronze", "clima", "2024-01", 31, inicio, True)
    _, valores = conexion.sentencias[-1]
    assert valores[5] == datetime(2026, 11, 17, 14, 0, 0)
    assert valores[5].tzinfo is None
    assert valores[6] is True


def test_el_nombre_de_la_conexion_se_puede_configurar(conexion, monkeypatch):
    watermark.consultar_watermark("clima", "bronze", "2024-01")
    monkeypatch.setenv(watermark.VARIABLE_CONEXION, "bigdata-test")
    watermark.consultar_watermark("clima", "bronze", "2024-01")
    watermark.consultar_watermark("clima", "bronze", "2024-01", connection_name="otra")
    assert conexion.nombres == ["default", "bigdata-test", "otra"]


def test_la_conexion_se_cierra_aunque_falle_la_consulta(conexion):
    conexion.cursor = lambda: (_ for _ in ()).throw(RuntimeError("sin red"))
    with pytest.raises(RuntimeError):
        watermark.registrar_watermark("f", "bronze", "t", "2024-01", 1, datetime.now(UTC), False)
    assert conexion.cerrada


def test_borrar_solo_acepta_tablas_de_prueba(conexion):
    with pytest.raises(ValueError, match="tablas de prueba"):
        watermark.borrar_registros_de_prueba("clima")
    assert conexion.sentencias == []
    assert watermark.borrar_registros_de_prueba("demo") == 2
    assert watermark.borrar_registros_de_prueba("prueba_clima") == 2
    sql, valores = conexion.sentencias[-1]
    assert sql == "DELETE FROM BIGDATA.CONTROL.WATERMARK WHERE TABLA = %s"
    assert valores == ("prueba_clima",)
