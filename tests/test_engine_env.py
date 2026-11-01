from __future__ import annotations

from pipeline.engine import _parametros_snowflake


def test_parametros_snowflake_vacios_sin_entorno(monkeypatch):
    for k in (
        "SNOWFLAKE_CONNECTION_NAME",
        "SNOWFLAKE_DEFAULT_CONNECTION_NAME",
        "SNOWFLAKE_DATABASE",
        "SNOWFLAKE_SCHEMA",
        "SNOWFLAKE_WAREHOUSE",
        "SNOWFLAKE_ROLE",
    ):
        monkeypatch.delenv(k, raising=False)
    assert _parametros_snowflake() == {}


def test_parametros_snowflake_desde_entorno(monkeypatch):
    monkeypatch.setenv("SNOWFLAKE_CONNECTION_NAME", "mi-conexion")
    monkeypatch.setenv("SNOWFLAKE_DATABASE", "BIGDATA")
    monkeypatch.setenv("SNOWFLAKE_SCHEMA", "GOLD")
    assert _parametros_snowflake() == {
        "connection_name": "mi-conexion",
        "database": "BIGDATA",
        "schema": "GOLD",
    }
