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


# --- elección de la conexión: connections.toml o Secrets Manager -------------------------------


def secreto_de_airflow(**cambios):
    """JSON de conexión de Airflow como lo escribe scripts/snowflake.sh (sin llave real)."""
    conexion = {
        "conn_type": "snowflake",
        "login": "AIRFLOW_SVC",
        "extra": {
            "account": "org-cuenta",
            "warehouse": "BIGDATA_WH",
            "database": "BIGDATA",
            "role": "BIGDATA_DEV",
            "private_key_content": "PEM",
        },
    }
    conexion.update(cambios)
    return json.dumps(conexion)


def test_el_secreto_se_convierte_en_parametros_del_conector(monkeypatch):
    monkeypatch.setattr(watermark, "_llave_privada_der", lambda pem: b"der:" + pem.encode())
    parametros = watermark._parametros_de_secreto(secreto_de_airflow())
    assert parametros == {
        "account": "org-cuenta",
        "user": "AIRFLOW_SVC",
        "role": "BIGDATA_DEV",
        "warehouse": "BIGDATA_WH",
        "database": "BIGDATA",
        "private_key": b"der:PEM",
    }


def test_el_secreto_con_password_y_sin_llave_usa_password():
    texto = secreto_de_airflow(password="clave", extra={"account": "a"})
    parametros = watermark._parametros_de_secreto(texto)
    assert parametros == {"account": "a", "user": "AIRFLOW_SVC", "password": "clave"}


def test_el_secreto_sin_llave_ni_password_falla_con_mensaje_claro():
    with pytest.raises(ValueError, match="private_key_content ni password"):
        watermark._parametros_de_secreto(secreto_de_airflow(extra={"account": "a"}))


def test_con_la_variable_del_secreto_se_conecta_por_secrets_manager(conexion, monkeypatch):
    pedidos = []

    def abrir_con_secreto(nombre):
        pedidos.append(nombre)
        return conexion

    monkeypatch.setattr(watermark, "_abrir_conexion_con_secreto", abrir_con_secreto)
    monkeypatch.setenv(watermark.VARIABLE_SECRETO, "bigdata-udem/snowflake")
    watermark.consultar_watermark("clima", "bronze", "2024-01")
    assert pedidos == ["bigdata-udem/snowflake"]
    assert conexion.nombres == []  # no se abrió connections.toml


def test_un_nombre_de_conexion_explicito_gana_sobre_el_secreto(conexion, monkeypatch):
    monkeypatch.setenv(watermark.VARIABLE_SECRETO, "bigdata-udem/snowflake")
    watermark.consultar_watermark("clima", "bronze", "2024-01", connection_name="otra")
    assert conexion.nombres == ["otra"]


def test_si_la_conexion_trae_rol_y_warehouse_no_se_usa_el_respaldo(conexion):
    conexion.role = "BIGDATA_DEV"
    conexion.warehouse = "BIGDATA_WH"
    watermark.consultar_watermark("clima", "bronze", "2024-01")
    assert not any(sql.startswith("USE ") for sql in textos(conexion))


def test_si_falta_solo_el_warehouse_se_fija_solo_el_warehouse(conexion):
    conexion.role = "BIGDATA_DEV"
    conexion.warehouse = None
    watermark.consultar_watermark("clima", "bronze", "2024-01")
    assert [s for s in textos(conexion) if s.startswith("USE ")] == ["USE WAREHOUSE COMPUTE_WH"]


def test_nombre_de_tabla_lleva_el_entorno():
    assert watermark.nombre_de_tabla("dev", "fhvhv_trips") == "dev/fhvhv_trips"
    assert watermark.nombre_de_tabla("prod", "daily_zone_metrics") == "prod/daily_zone_metrics"


# --- conexión por entorno (la usan control.py y bodega.py) ----------------------------------------


def test_el_secreto_por_defecto_de_cada_entorno(monkeypatch):
    monkeypatch.delenv(watermark.VARIABLE_SECRETO, raising=False)
    monkeypatch.delenv("PREFIX", raising=False)
    assert watermark.nombre_del_secreto("dev") == "bigdata/snowflake"
    assert watermark.nombre_del_secreto("prod") == "bigdata/snowflake_prod"

    monkeypatch.setenv("PREFIX", "curso")
    assert watermark.nombre_del_secreto("dev") == "curso/snowflake"
    assert watermark.nombre_del_secreto("prod") == "curso/snowflake_prod"


def test_la_variable_del_secreto_gana_sobre_el_defecto(monkeypatch):
    monkeypatch.setenv(watermark.VARIABLE_SECRETO, "otro/secreto")
    assert watermark.nombre_del_secreto("prod") == "otro/secreto"


def test_la_conexion_de_entorno_usa_el_secreto_y_nunca_connections_toml(monkeypatch):
    monkeypatch.delenv(watermark.VARIABLE_SECRETO, raising=False)
    monkeypatch.delenv("PREFIX", raising=False)
    abiertos = []
    monkeypatch.setattr(watermark, "_abrir_conexion_con_secreto", lambda n: abiertos.append(n) or n)
    monkeypatch.setattr(watermark, "_abrir_conexion", lambda n: pytest.fail("connections.toml"))

    assert watermark.abrir_conexion_de_entorno("dev") == "bigdata/snowflake"
    assert watermark.abrir_conexion_de_entorno("prod") == "bigdata/snowflake_prod"
    assert abiertos == ["bigdata/snowflake", "bigdata/snowflake_prod"]
