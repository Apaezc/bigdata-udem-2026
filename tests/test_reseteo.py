"""Reseteo de un entorno: S3, Snowflake y tabla de control, con boto3 y cursor falsos.

Nada toca AWS ni Snowflake. Lo que se vigila:
- nunca se arma una ruta o un esquema del otro entorno;
- `solo_listar` no borra nada;
- `conservar_crudo` deja bronze/_crudo/;
- el stage y el formato de Snowflake no se tocan;
- el rol del entorno se exige antes de borrar.
"""

from __future__ import annotations

import pytest

from pipeline.herramientas import bodega, reseteo
from pipeline.herramientas.corrida import EntornoNoPermitido
from pipeline.herramientas.rutas import ConfigError

BUCKET = "bucket-de-prueba"


# --- S3 falso -----------------------------------------------------------------------------------


class S3Falso:
    """Un bucket en memoria con la parte de la API de boto3 que usa reseteo.py."""

    def __init__(self, claves: dict[str, int], errores: list[dict] | None = None):
        self.claves = dict(claves)
        self.errores = errores or []
        self.prefijos_listados: list[str] = []
        self.llamadas_de_borrado: list[list[str]] = []

    def get_paginator(self, nombre):
        assert nombre == "list_objects_v2"
        return self

    def paginate(self, Bucket, Prefix):  # noqa: N803 - firma de boto3
        assert Bucket == BUCKET
        self.prefijos_listados.append(Prefix)
        encontrados = sorted(k for k in self.claves if k.startswith(Prefix))
        # dos páginas, para comprobar que se recorren todas
        mitad = max(1, len(encontrados) // 2)
        for trozo in (encontrados[:mitad], encontrados[mitad:]):
            yield {"Contents": [{"Key": k, "Size": self.claves[k]} for k in trozo]}

    def delete_objects(self, Bucket, Delete):  # noqa: N803
        assert Bucket == BUCKET
        claves = [o["Key"] for o in Delete["Objects"]]
        assert len(claves) <= 1000
        self.llamadas_de_borrado.append(claves)
        if self.errores:
            return {"Errors": self.errores}
        for clave in claves:
            self.claves.pop(clave)
        return {}


def lake_de_prueba() -> dict[str, int]:
    return {
        "dev/bronze/_crudo/fhvhv/mes=2024-01/fhvhv_tripdata_2024-01.parquet": 450,
        "dev/bronze/fhvhv/mes=2024-01/lote=1/part-0.parquet": 10,
        "dev/bronze/fhvhv/mes=2024-01/lote=1/_LOTE_COMPLETO": 0,
        "dev/silver/fhvhv/mes=2024-01/part-0.parquet": 5,
        "dev/gold/tarifa_por_milla_barrio/mes=2024-01/part-0.parquet": 1,
        "dev/silver_$folder$": 0,
        "prod/bronze/fhvhv/mes=2024-01/lote=9/part-0.parquet": 99,
        "prod/silver/fhvhv/mes=2024-01/part-0.parquet": 99,
        "code/pipeline.zip": 7,
        "dags/pipeline_taxi.py": 3,
        "dev_otro/archivo": 1,  # empieza igual que «dev» pero no es del entorno
    }


@pytest.fixture
def s3(monkeypatch):
    falso = S3Falso(lake_de_prueba())
    monkeypatch.setenv("LAKE_BUCKET", BUCKET)
    monkeypatch.delenv("PIPELINE_RAIZ_LAKE", raising=False)
    monkeypatch.setattr(reseteo, "_cliente_s3", lambda: falso)
    return falso


def test_solo_listar_cuenta_y_no_borra(s3):
    antes = dict(s3.claves)
    resumen = reseteo.borrar_capas_s3("dev")  # solo_listar es True por defecto
    assert s3.claves == antes
    assert s3.llamadas_de_borrado == []
    assert resumen["solo_listar"] is True
    assert resumen["objetos"] == 6
    assert resumen["borrados"] == 0
    assert resumen["bytes"] == 450 + 10 + 5 + 1
    assert resumen["por_capa"] == {"bronze": 3, "silver": 1, "gold": 1, "otros": 1}
    assert resumen["prefijo"] == f"s3://{BUCKET}/dev/"


def test_nunca_se_lista_ni_se_borra_el_otro_entorno(s3):
    reseteo.borrar_capas_s3("dev", solo_listar=False)
    assert s3.prefijos_listados and all(p == "dev/" for p in s3.prefijos_listados)
    borradas = [k for lote in s3.llamadas_de_borrado for k in lote]
    assert borradas and all(k.startswith("dev/") for k in borradas)
    # sigue todo lo ajeno: prod, code/, dags/ y la carpeta que solo se parece a dev
    assert {k for k in s3.claves} == {
        "prod/bronze/fhvhv/mes=2024-01/lote=9/part-0.parquet",
        "prod/silver/fhvhv/mes=2024-01/part-0.parquet",
        "code/pipeline.zip",
        "dags/pipeline_taxi.py",
        "dev_otro/archivo",
    }


def test_en_prod_solo_se_arma_el_prefijo_de_prod(s3):
    resumen = reseteo.borrar_capas_s3("prod", solo_listar=False)
    assert s3.prefijos_listados == ["prod/"]
    assert resumen["borrados"] == 2
    assert not any(k.startswith("prod/") for k in s3.claves)
    assert "dev/silver/fhvhv/mes=2024-01/part-0.parquet" in s3.claves


def test_conservar_crudo_deja_bronze_crudo(s3):
    resumen = reseteo.borrar_capas_s3("dev", solo_listar=False, conservar_crudo=True)
    crudo = "dev/bronze/_crudo/fhvhv/mes=2024-01/fhvhv_tripdata_2024-01.parquet"
    assert crudo in s3.claves
    assert resumen["conservados"] == 1
    assert resumen["borrados"] == 5
    assert not any(k.startswith("dev/silver") or k.startswith("dev/gold") for k in s3.claves)


def test_conservar_crudo_tambien_se_refleja_al_solo_listar(s3):
    resumen = reseteo.borrar_capas_s3("dev", conservar_crudo=True)
    assert resumen["objetos"] == 5
    assert resumen["conservados"] == 1


def test_borra_por_lotes_de_a_mil(monkeypatch):
    muchas = {f"dev/silver/fhvhv/mes=2024-01/part-{i}.parquet": 1 for i in range(2500)}
    falso = S3Falso(muchas)
    monkeypatch.setenv("LAKE_BUCKET", BUCKET)
    monkeypatch.setattr(reseteo, "_cliente_s3", lambda: falso)
    resumen = reseteo.borrar_capas_s3("dev", solo_listar=False)
    assert [len(lote) for lote in falso.llamadas_de_borrado] == [1000, 1000, 500]
    assert resumen["borrados"] == 2500 and falso.claves == {}


def test_un_error_de_s3_detiene_el_borrado(monkeypatch):
    falso = S3Falso(
        {"dev/silver/a": 1},
        errores=[{"Key": "dev/silver/a", "Code": "AccessDenied", "Message": "no"}],
    )
    monkeypatch.setenv("LAKE_BUCKET", BUCKET)
    monkeypatch.setattr(reseteo, "_cliente_s3", lambda: falso)
    with pytest.raises(RuntimeError, match="AccessDenied"):
        reseteo.borrar_capas_s3("dev", solo_listar=False)


def test_si_s3_devuelve_claves_ajenas_se_detiene(monkeypatch):
    class Descontrolado(S3Falso):
        def paginate(self, Bucket, Prefix):  # noqa: N803
            yield {"Contents": [{"Key": "prod/silver/x", "Size": 1}]}

    falso = Descontrolado({})
    monkeypatch.setenv("LAKE_BUCKET", BUCKET)
    monkeypatch.setattr(reseteo, "_cliente_s3", lambda: falso)
    with pytest.raises(RuntimeError, match="fuera de dev/"):
        reseteo.borrar_capas_s3("dev", solo_listar=False)
    assert falso.llamadas_de_borrado == []


@pytest.mark.parametrize("entorno", ["local", "staging", "", "DEV", "dev/../prod"])
def test_un_entorno_raro_no_pasa(s3, entorno):
    with pytest.raises(ConfigError):
        reseteo.borrar_capas_s3(entorno, solo_listar=False)
    with pytest.raises(ConfigError):
        reseteo.borrar_tablas_snowflake(entorno, solo_listar=False, conexion=object())
    with pytest.raises(ConfigError):
        reseteo.esquema_del_entorno(entorno)
    assert s3.prefijos_listados == [] and s3.llamadas_de_borrado == []


def test_con_raiz_de_prueba_file_no_se_resetea_s3(s3, monkeypatch, tmp_path):
    monkeypatch.setenv("PIPELINE_RAIZ_LAKE", f"file://{tmp_path}")
    with pytest.raises(ConfigError, match="PIPELINE_RAIZ_LAKE"):
        reseteo.borrar_capas_s3("dev", solo_listar=False)
    assert s3.llamadas_de_borrado == []


# --- Snowflake falso ----------------------------------------------------------------------------


class CursorFalso:
    def __init__(self, conexion):
        self.conexion = conexion
        self._ultimo = ""

    def execute(self, sql, valores=()):
        self._ultimo = sql
        self.conexion.sentencias.append(sql)

    def fetchall(self):
        sql = self._ultimo
        esquema = sql.rsplit(" ", 1)[-1]
        if sql.startswith("SHOW TABLES"):
            return [
                ("ts", nombre, "BIGDATA", esquema.split(".")[1]) for nombre in self.conexion.tablas
            ]
        if sql.startswith("SHOW VIEWS"):
            return [
                ("ts", nombre, "BIGDATA", esquema.split(".")[1]) for nombre in self.conexion.vistas
            ]
        raise AssertionError(f"fetchall inesperado para: {sql}")

    def fetchone(self):
        if self._ultimo.startswith("SELECT CURRENT_ROLE"):
            return (self.conexion.rol,)
        if self._ultimo.startswith("SELECT COUNT"):
            return (self.conexion.registros,)
        raise AssertionError(f"fetchone inesperado para: {self._ultimo}")


class ConexionFalsa:
    def __init__(self, rol="BIGDATA_DEV", tablas=(), vistas=(), registros=0):
        self.rol = rol
        self.tablas = list(tablas)
        self.vistas = list(vistas)
        self.registros = registros
        self.sentencias: list[str] = []
        self.cerrada = False

    def cursor(self):
        return CursorFalso(self)

    def close(self):
        self.cerrada = True

    @property
    def drops(self):
        return [s for s in self.sentencias if s.startswith("DROP")]


def test_snowflake_solo_listar_nombra_y_no_borra():
    con = ConexionFalsa(tablas=["TARIFA_POR_MILLA_BARRIO", "DAILY_ZONE_METRICS"], vistas=["V1"])
    nombres = reseteo.borrar_tablas_snowflake("dev", conexion=con)
    assert nombres == [
        "BIGDATA.DEV.TARIFA_POR_MILLA_BARRIO",
        "BIGDATA.DEV.DAILY_ZONE_METRICS",
        "BIGDATA.DEV.V1",
    ]
    assert con.drops == []
    assert con.cerrada is False  # la conexión que llega de fuera no se cierra


def test_snowflake_borra_tablas_y_vistas_solo_del_esquema_del_entorno():
    con = ConexionFalsa(tablas=["T1", "T2"], vistas=["V1"])
    nombres = reseteo.borrar_tablas_snowflake("dev", solo_listar=False, conexion=con)
    assert len(nombres) == 3
    assert con.drops == [
        'DROP TABLE IF EXISTS BIGDATA.DEV."T1"',
        'DROP TABLE IF EXISTS BIGDATA.DEV."T2"',
        'DROP VIEW IF EXISTS BIGDATA.DEV."V1"',
    ]
    assert not any("PROD" in s for s in con.sentencias)


def test_snowflake_en_prod_solo_toca_prod():
    con = ConexionFalsa(rol="BIGDATA_PROD", tablas=["T1"])
    reseteo.borrar_tablas_snowflake("prod", solo_listar=False, conexion=con)
    assert con.drops == ['DROP TABLE IF EXISTS BIGDATA.PROD."T1"']
    assert not any("DEV" in s for s in con.sentencias)


def test_el_stage_y_el_formato_no_se_tocan():
    con = ConexionFalsa(tablas=["T1"])
    reseteo.borrar_tablas_snowflake("dev", solo_listar=False, conexion=con)
    texto = " ".join(con.sentencias).upper()
    for prohibido in ("STAGE", "LAKE_GOLD", "FILE FORMAT", "PARQUET_FF", "DROP SCHEMA", "DATABASE"):
        assert prohibido not in texto


def test_el_rol_se_exige_antes_de_borrar():
    # una conexión de prod no puede resetear dev, y ACCOUNTADMIN tampoco
    for rol in ("BIGDATA_PROD", "ACCOUNTADMIN"):
        con = ConexionFalsa(rol=rol, tablas=["T1"])
        with pytest.raises(EntornoNoPermitido):
            reseteo.borrar_tablas_snowflake("dev", solo_listar=False, conexion=con)
        assert con.drops == []
        assert not any(s.startswith("SHOW") for s in con.sentencias)


def test_un_nombre_con_comillas_se_escapa():
    con = ConexionFalsa(tablas=['RARA"; DROP TABLE X; --'])
    reseteo.borrar_tablas_snowflake("dev", solo_listar=False, conexion=con)
    assert con.drops == ['DROP TABLE IF EXISTS BIGDATA.DEV."RARA""; DROP TABLE X; --"']


def test_sin_conexion_abre_la_del_entorno_y_la_cierra(monkeypatch):
    con = ConexionFalsa(tablas=["T1"])
    pedidas = []
    monkeypatch.setattr(bodega, "abrir_conexion_de_entorno", lambda e: pedidas.append(e) or con)
    reseteo.borrar_tablas_snowflake("dev")
    assert pedidas == ["dev"]
    assert con.cerrada is True


def test_esquema_del_entorno_solo_es_dev_o_prod():
    assert reseteo.esquema_del_entorno("dev") == "BIGDATA.DEV"
    assert reseteo.esquema_del_entorno("prod") == "BIGDATA.PROD"


# --- tabla de control ---------------------------------------------------------------------------


def test_contar_control_cuenta_solo_la_tabla_del_entorno():
    con = ConexionFalsa(registros=12)
    assert reseteo.contar_control("dev", con) == 12
    consultas = [s for s in con.sentencias if s.startswith("SELECT COUNT")]
    assert consultas == ["SELECT COUNT(*) FROM BIGDATA.CONTROL_DEV.WATERMARK"]


def test_contar_control_exige_el_rol_del_entorno():
    con = ConexionFalsa(rol="BIGDATA_DEV", registros=3)
    with pytest.raises(EntornoNoPermitido):
        reseteo.contar_control("prod", con)
