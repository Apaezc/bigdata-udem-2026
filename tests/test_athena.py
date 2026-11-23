"""Athena como catálogo: nombres, esquema desde Glue y verificación contra Snowflake, sin red."""

from __future__ import annotations

import pytest

from pipeline.herramientas import athena
from pipeline.herramientas.bodega import ColumnasDistintas
from pipeline.herramientas.rutas import ConfigError

TABLA_ATHENA = "dev_gold_tarifa_por_milla_barrio"
TABLA_SNOWFLAKE = "BIGDATA.DEV.TARIFA_POR_MILLA_BARRIO"

COLUMNAS_GLUE = [
    {"Name": "fecha", "Type": "date"},
    {"Name": "borough", "Type": "string"},
    {"Name": "franja", "Type": "string"},
    {"Name": "viajes", "Type": "bigint"},
    {"Name": "distancia_total_mi", "Type": "double"},
    {"Name": "ingreso_total", "Type": "double"},
    {"Name": "tarifa_por_milla", "Type": "double"},
]
TABLA_EN_SNOWFLAKE = {
    "FECHA": "DATE",
    "BOROUGH": "VARCHAR(16777216)",
    "FRANJA": "VARCHAR(16777216)",
    "VIAJES": "NUMBER(38,0)",
    "DISTANCIA_TOTAL_MI": "FLOAT",
    "INGRESO_TOTAL": "FLOAT",
    "TARIFA_POR_MILLA": "FLOAT",
}


class GlueFalso:
    def __init__(self, columnas=None, error=None):
        self.columnas = columnas
        self.error = error
        self.pedidos = []

    def get_table(self, DatabaseName, Name):  # noqa: N803 (así se llama en boto3)
        self.pedidos.append((DatabaseName, Name))
        if self.error:
            raise self.error
        return {
            "Table": {
                "StorageDescriptor": {"Columns": self.columnas},
                "PartitionKeys": [{"Name": "mes", "Type": "string"}],
            }
        }


class ErrorDeAws(Exception):
    def __init__(self, codigo):
        super().__init__(codigo)
        self.response = {"Error": {"Code": codigo}}


class CursorFalso:
    def __init__(self, tabla):
        self.tabla = tabla
        self._filas = []

    def execute(self, sql, valores=None):
        if self.tabla is None:
            raise RuntimeError("Object does not exist")
        self._filas = [(nombre, tipo, "COLUMN") for nombre, tipo in self.tabla.items()]

    def fetchall(self):
        return self._filas


class ConexionFalsa:
    def __init__(self, tabla):
        self.tabla = tabla

    def cursor(self):
        return CursorFalso(self.tabla)

    def close(self):
        pass


@pytest.fixture
def glue(monkeypatch):
    falso = GlueFalso(COLUMNAS_GLUE)
    monkeypatch.setattr(athena, "_cliente_de_glue", lambda: falso)
    return falso


# --- nombres ------------------------------------------------------------------------------------


def test_nombre_de_la_tabla_en_athena():
    assert athena.nombre_tabla_athena("dev", "silver", "fhvhv") == "dev_silver_fhvhv"
    assert (
        athena.nombre_tabla_athena("prod", "gold", "tarifa_por_milla_barrio")
        == "prod_gold_tarifa_por_milla_barrio"
    )


def test_nombre_con_entorno_o_capa_desconocidos_falla():
    with pytest.raises(ConfigError, match="Entorno desconocido"):
        athena.nombre_tabla_athena("qa", "silver", "fhvhv")
    with pytest.raises(ConfigError, match="Capa desconocida"):
        athena.nombre_tabla_athena("dev", "platino", "fhvhv")


# --- esquema_de_athena --------------------------------------------------------------------------


def test_esquema_de_athena_lee_el_catalogo_y_deja_fuera_la_particion(glue):
    esquema = athena.esquema_de_athena(TABLA_ATHENA)

    assert glue.pedidos == [("bigdata_lake", TABLA_ATHENA)]
    assert esquema["viajes"] == "bigint"
    assert "mes" not in esquema
    assert list(esquema) == [c["Name"] for c in COLUMNAS_GLUE]


def test_esquema_de_athena_sin_la_tabla_devuelve_none_y_avisa(monkeypatch, capsys):
    falso = GlueFalso(error=ErrorDeAws("EntityNotFoundException"))
    monkeypatch.setattr(athena, "_cliente_de_glue", lambda: falso)

    assert athena.esquema_de_athena(TABLA_ATHENA) is None
    assert "la tabla no existe" in capsys.readouterr().out


def test_esquema_de_athena_sin_permiso_devuelve_none_y_avisa(monkeypatch, capsys):
    falso = GlueFalso(error=ErrorDeAws("AccessDeniedException"))
    monkeypatch.setattr(athena, "_cliente_de_glue", lambda: falso)

    assert athena.esquema_de_athena(TABLA_ATHENA, base="otra_base") is None
    salida = capsys.readouterr().out
    assert "otra_base." + TABLA_ATHENA in salida
    assert "no tiene permiso" in salida


def test_esquema_de_athena_sin_credenciales_tampoco_lanza(monkeypatch, capsys):
    def sin_credenciales():
        raise RuntimeError("Unable to locate credentials")

    monkeypatch.setattr(athena, "_cliente_de_glue", sin_credenciales)

    assert athena.esquema_de_athena(TABLA_ATHENA) is None
    assert "AVISO" in capsys.readouterr().out


# --- verificar_esquema_con_athena ---------------------------------------------------------------


def test_columnas_iguales_pasan_aunque_los_tipos_se_escriban_distinto(glue):
    athena.verificar_esquema_con_athena(
        TABLA_ATHENA, TABLA_SNOWFLAKE, ConexionFalsa(TABLA_EN_SNOWFLAKE)
    )


def test_columna_nueva_en_gold_lanza_con_el_tipo_real_en_el_alter(glue):
    glue.columnas = [*COLUMNAS_GLUE, {"Name": "pasajeros", "Type": "bigint"}]

    with pytest.raises(ColumnasDistintas) as error:
        athena.verificar_esquema_con_athena(
            TABLA_ATHENA, TABLA_SNOWFLAKE, ConexionFalsa(TABLA_EN_SNOWFLAKE)
        )

    mensaje = str(error.value)
    assert "Solo en S3" in mensaje and "PASAJEROS" in mensaje
    assert f"ALTER TABLE {TABLA_SNOWFLAKE} ADD COLUMN PASAJEROS NUMBER(38,0);" in mensaje


def test_alter_traduce_decimal_y_otros_tipos_de_glue(glue):
    glue.columnas = [
        *COLUMNAS_GLUE,
        {"Name": "propina", "Type": "decimal(10,2)"},
        {"Name": "inicio", "Type": "timestamp"},
        {"Name": "nota", "Type": "string"},
    ]

    with pytest.raises(ColumnasDistintas) as error:
        athena.verificar_esquema_con_athena(
            TABLA_ATHENA, TABLA_SNOWFLAKE, ConexionFalsa(TABLA_EN_SNOWFLAKE)
        )

    mensaje = str(error.value)
    assert "ADD COLUMN PROPINA NUMBER(10,2);" in mensaje
    assert "ADD COLUMN INICIO TIMESTAMP_NTZ;" in mensaje
    assert "ADD COLUMN NOTA VARCHAR;" in mensaje


def test_columna_que_gold_ya_no_trae_lanza(glue):
    glue.columnas = COLUMNAS_GLUE[:-1]

    with pytest.raises(ColumnasDistintas, match="Solo en Snowflake"):
        athena.verificar_esquema_con_athena(
            TABLA_ATHENA, TABLA_SNOWFLAKE, ConexionFalsa(TABLA_EN_SNOWFLAKE)
        )


def test_tipo_distinto_lanza(glue):
    tabla = {**TABLA_EN_SNOWFLAKE, "VIAJES": "VARCHAR"}

    with pytest.raises(ColumnasDistintas, match="Tipo distinto en VIAJES"):
        athena.verificar_esquema_con_athena(TABLA_ATHENA, TABLA_SNOWFLAKE, ConexionFalsa(tabla))


def test_si_athena_no_responde_avisa_y_sigue(monkeypatch, capsys):
    falso = GlueFalso(error=ErrorDeAws("AccessDeniedException"))
    monkeypatch.setattr(athena, "_cliente_de_glue", lambda: falso)

    athena.verificar_esquema_con_athena(TABLA_ATHENA, TABLA_SNOWFLAKE, ConexionFalsa(None))

    assert "Sigo sin verificar" in capsys.readouterr().out


def test_si_la_tabla_de_snowflake_aun_no_existe_avisa_y_sigue(glue, capsys):
    athena.verificar_esquema_con_athena(TABLA_ATHENA, TABLA_SNOWFLAKE, ConexionFalsa(None))

    assert "no existe todavía" in capsys.readouterr().out
