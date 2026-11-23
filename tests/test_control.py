"""Tabla de control por entorno: la puerta, el registro y el rol, sin tocar Snowflake."""

from __future__ import annotations

import sys
import types
from dataclasses import dataclass
from datetime import datetime

import pytest

from pipeline.herramientas import bodega, control
from pipeline.herramientas.control import (
    ControlEnMemoria,
    ControlEnSnowflake,
    con_control,
    consultar_control,
    exigir_rol_del_entorno,
    instalar_backend,
    mes_ya_procesado,
    registrar_control,
    tabla_de_control,
    vaciar_control,
)


def _asegurar_modulo_corrida():
    """Si P1 aún no publica herramientas/corrida.py, deja un doble con lo que control.py importa."""
    try:
        import pipeline.herramientas.corrida  # noqa: F401
    except ImportError:
        modulo = types.ModuleType("pipeline.herramientas.corrida")

        class EntornoNoPermitido(RuntimeError):
            pass

        @dataclass(frozen=True)
        class Resultado:
            tabla: str
            capa: str
            mes: str
            leidas: int
            escritas: int
            decision: str

        modulo.EntornoNoPermitido = EntornoNoPermitido
        modulo.Resultado = Resultado
        sys.modules["pipeline.herramientas.corrida"] = modulo


_asegurar_modulo_corrida()
from pipeline.herramientas.corrida import EntornoNoPermitido, Resultado  # noqa: E402
from pipeline.herramientas.rutas import ConfigError  # noqa: E402


@dataclass
class CorridaDePrueba:
    """Lo único que la caja lee de una Corrida."""

    entorno: str = "dev"
    computo: str = "code_editor"
    limite: str = "1000"
    reprocesar: bool = False


INICIO = datetime(2026, 11, 21, 15, 0, 0)


@pytest.fixture
def memoria():
    backend = ControlEnMemoria()
    instalar_backend(backend)
    yield backend
    instalar_backend(None)


def registrar(corrida, tabla="fhvhv", capa="silver", mes="2024-01", filas=10, **extra):
    registrar_control(corrida, tabla, capa, mes, filas, INICIO, "s3://lake/fuente", **extra)


# --- nombre de la tabla --------------------------------------------------------------------------


def test_cada_entorno_tiene_su_tabla_de_control():
    assert tabla_de_control("dev") == "BIGDATA.CONTROL_DEV.WATERMARK"
    assert tabla_de_control("prod") == "BIGDATA.CONTROL_PROD.WATERMARK"


def test_un_entorno_desconocido_se_rechaza():
    with pytest.raises(ConfigError, match="Entorno desconocido"):
        tabla_de_control("qa")


# --- la puerta: los tres casos de la regla del autor --------------------------------------------


def test_sin_registro_y_sin_reprocesar_se_ingesta(memoria):
    assert mes_ya_procesado(CorridaDePrueba(), "fhvhv", "silver", "2024-01") is False


def test_con_registro_y_sin_reprocesar_se_salta(memoria):
    corrida = CorridaDePrueba()
    registrar(corrida)

    assert mes_ya_procesado(corrida, "fhvhv", "silver", "2024-01") is True


def test_con_reprocesar_siempre_se_ingesta_haya_o_no_registro(memoria):
    registrar(CorridaDePrueba())

    assert mes_ya_procesado(CorridaDePrueba(reprocesar=True), "fhvhv", "silver", "2024-01") is False


def test_el_salto_no_mira_filas_computo_ni_limite(memoria):
    registrar(CorridaDePrueba(computo="glue_small", limite="1000"), filas=3)

    otra = CorridaDePrueba(computo="glue_large", limite="todos")
    assert mes_ya_procesado(otra, "fhvhv", "silver", "2024-01") is True


def test_la_clave_es_tabla_capa_mes_y_entorno(memoria):
    corrida = CorridaDePrueba()
    registrar(corrida)

    assert mes_ya_procesado(corrida, "clima", "silver", "2024-01") is False
    assert mes_ya_procesado(corrida, "fhvhv", "gold", "2024-01") is False
    assert mes_ya_procesado(corrida, "fhvhv", "silver", "2024-02") is False
    assert mes_ya_procesado(CorridaDePrueba(entorno="prod"), "fhvhv", "silver", "2024-01") is False


def test_con_reprocesar_la_puerta_ni_consulta(memoria):
    memoria.consultar = lambda *a: pytest.fail("no debía consultar la tabla de control")

    assert mes_ya_procesado(CorridaDePrueba(reprocesar=True), "fhvhv", "silver", "2024-01") is False


# --- registro y consulta -------------------------------------------------------------------------


def test_consultar_devuelve_claves_en_minuscula_del_mas_antiguo_al_mas_reciente(memoria):
    corrida = CorridaDePrueba(computo="glue_small", limite="100000")
    registrar_control(corrida, "fhvhv", "silver", "2024-01", 7, datetime(2026, 11, 22), "f2", 9)
    registrar_control(corrida, "fhvhv", "silver", "2024-01", 5, datetime(2026, 11, 21), "f1", 6)

    registros = consultar_control("dev", "fhvhv", "silver", "2024-01")

    assert [r["filas"] for r in registros] == [5, 7]
    assert registros[0] == {
        "fuente": "f1",
        "capa": "silver",
        "tabla": "fhvhv",
        "mes": "2024-01",
        "filas": 5,
        "inicio": "2026-11-21T00:00:00",
        "reprocesar": False,
        "computo": "glue_small",
        "limite": "100000",
        "leidas": 6,
    }


# --- con_control: puerta y registro juntos -------------------------------------------------------


def test_con_control_registra_cuando_el_trabajo_termina_bien(memoria):
    corrida = CorridaDePrueba(computo="glue_medium", limite="todos")

    resultado = con_control(corrida, "fhvhv", "silver", "2024-01", "s3://bronze", lambda: (100, 99))

    assert resultado == Resultado("fhvhv", "silver", "2024-01", 100, 99, "REGISTRÓ")
    (registro,) = consultar_control("dev", "fhvhv", "silver", "2024-01")
    assert (registro["filas"], registro["leidas"]) == (99, 100)
    assert (registro["computo"], registro["limite"]) == ("glue_medium", "todos")
    assert registro["fuente"] == "s3://bronze"


def test_con_control_salta_la_segunda_vez_y_no_corre_el_trabajo(memoria):
    corrida = CorridaDePrueba()
    con_control(corrida, "taxi_zones", "silver", "sin_mes", "s3://b", lambda: (265, 265))

    resultado = con_control(
        corrida, "taxi_zones", "silver", "sin_mes", "s3://b", lambda: pytest.fail("no debía correr")
    )

    assert resultado == Resultado("taxi_zones", "silver", "sin_mes", 265, 265, "SE SALTÓ")
    assert len(consultar_control("dev", "taxi_zones", "silver", "sin_mes")) == 1


def test_con_control_reprocesar_corre_otra_vez_y_conserva_la_historia(memoria):
    con_control(CorridaDePrueba(), "fhvhv", "gold", "2024-01", "f", lambda: (10, 4))

    resultado = con_control(
        CorridaDePrueba(reprocesar=True), "fhvhv", "gold", "2024-01", "f", lambda: (10, 4)
    )

    assert resultado.decision == "REGISTRÓ"
    registros = consultar_control("dev", "fhvhv", "gold", "2024-01")
    assert [r["reprocesar"] for r in registros] == [False, True]


def test_si_el_trabajo_falla_no_se_registra_nada(memoria):
    def trabajo():
        raise RuntimeError("se cayó a mitad")

    with pytest.raises(RuntimeError, match="a mitad"):
        con_control(CorridaDePrueba(), "fhvhv", "silver", "2024-01", "f", trabajo)

    assert consultar_control("dev", "fhvhv", "silver", "2024-01") == []
    assert memoria.registros == []


def test_con_control_no_imprime(memoria, capsys):
    con_control(CorridaDePrueba(), "fhvhv", "silver", "2024-01", "f", lambda: (1, 1))

    assert capsys.readouterr().out == ""


def test_vaciar_borra_solo_el_entorno_pedido(memoria):
    registrar(CorridaDePrueba(entorno="dev"))
    registrar(CorridaDePrueba(entorno="dev"), mes="2024-02")
    registrar(CorridaDePrueba(entorno="prod"))

    assert vaciar_control("dev") == 2
    assert consultar_control("dev", "fhvhv", "silver", "2024-01") == []
    assert len(consultar_control("prod", "fhvhv", "silver", "2024-01")) == 1


# --- la tabla de verdad: Snowflake con una conexión falsa ----------------------------------------


class CursorFalso:
    def __init__(self, conexion):
        self.conexion = conexion
        self.rowcount = 0

    def execute(self, sql, valores=None):
        texto = " ".join(sql.split())
        self.conexion.sentencias.append((texto, valores))
        if self.conexion.error:
            raise self.conexion.error
        if texto.startswith("DELETE"):
            self.rowcount = 4
        if texto.startswith("SELECT CURRENT_ROLE"):
            self.conexion.fila_del_rol = [(self.conexion.rol,)]

    def fetchall(self):
        return self.conexion.filas

    def fetchone(self):
        return self.conexion.fila_del_rol[0]


class ConexionFalsa:
    def __init__(self, rol="BIGDATA_DEV", filas=None, error=None):
        self.rol = rol
        self.filas = filas or []
        self.fila_del_rol = [(rol,)]
        self.error = error
        self.sentencias = []
        self.cerrada = False

    def cursor(self):
        return CursorFalso(self)

    def close(self):
        self.cerrada = True


def test_consultar_en_snowflake_parametriza_y_usa_la_tabla_del_entorno():
    fila = ("f", "silver", "fhvhv", "2024-01", 99, INICIO, False, "glue_small", "1000", 100)
    conexion = ConexionFalsa(filas=[fila])

    registros = consultar_control("dev", "fhvhv", "silver", "2024-01", conexion)

    sql, valores = conexion.sentencias[-1]
    assert "FROM BIGDATA.CONTROL_DEV.WATERMARK" in sql
    assert "WHERE TABLA = %s AND CAPA = %s AND MES = %s" in sql
    assert sql.endswith("ORDER BY INICIO")
    assert valores == ("fhvhv", "silver", "2024-01")
    assert registros[0]["leidas"] == 100 and registros[0]["inicio"] == "2026-11-21T15:00:00"
    assert conexion.cerrada is False  # la conexión ajena la cierra quien la abrió


def test_registrar_en_snowflake_inserta_las_diez_columnas_en_orden():
    conexion = ConexionFalsa()
    corrida = CorridaDePrueba(entorno="prod", computo="glue_medium", limite="todos")

    registrar_control(corrida, "fhvhv", "gold", "2024-01", 50, INICIO, "s3://silver", 60, conexion)

    sql, valores = conexion.sentencias[-1]
    assert sql.startswith("INSERT INTO BIGDATA.CONTROL_PROD.WATERMARK (FUENTE, CAPA, TABLA, MES,")
    assert "FILAS, INICIO, REPROCESAR, COMPUTO, LIMITE, LEIDAS)" in sql
    assert sql.endswith("VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)")
    assert valores == (
        "s3://silver",
        "gold",
        "fhvhv",
        "2024-01",
        50,
        INICIO,
        False,
        "glue_medium",
        "todos",
        60,
    )


def test_vaciar_en_snowflake_borra_solo_la_tabla_del_entorno():
    conexion = ConexionFalsa()

    borradas = vaciar_control("dev", conexion)

    assert borradas == 4
    assert conexion.sentencias[-1][0] == "DELETE FROM BIGDATA.CONTROL_DEV.WATERMARK"


def test_tabla_inexistente_o_sin_permiso_explica_que_hay_que_correr_make_snowflake():
    class ObjetoNoExiste(Exception):
        errno = control.ERRNO_TABLA_NO_VISIBLE

    conexion = ConexionFalsa(error=ObjetoNoExiste("does not exist or not authorized"))

    with pytest.raises(RuntimeError, match="make snowflake"):
        consultar_control("dev", "fhvhv", "silver", "2024-01", conexion)


def test_sin_conexion_se_abre_la_del_entorno_con_su_rol_y_se_cierra(monkeypatch):
    abiertas = []
    conexion = ConexionFalsa(rol="BIGDATA_PROD")

    def abrir(entorno):
        abiertas.append(entorno)
        return conexion

    monkeypatch.setattr(bodega, "abrir_conexion_de_entorno", abrir)

    consultar_control("prod", "fhvhv", "silver", "2024-01")

    assert abiertas == ["prod"]
    assert conexion.sentencias[0][0] == "SELECT CURRENT_ROLE()"
    assert conexion.cerrada is True


def test_sin_conexion_con_accountadmin_se_niega_y_cierra(monkeypatch):
    conexion = ConexionFalsa(rol="ACCOUNTADMIN")
    monkeypatch.setattr(bodega, "abrir_conexion_de_entorno", lambda entorno: conexion)

    with pytest.raises(EntornoNoPermitido, match="ACCOUNTADMIN"):
        consultar_control("dev", "fhvhv", "silver", "2024-01")

    assert conexion.cerrada is True
    assert not any(sql.startswith("SELECT FUENTE") for sql, _ in conexion.sentencias)


def test_un_backend_instalado_gana_sobre_snowflake(monkeypatch, memoria):
    monkeypatch.setattr(bodega, "abrir_conexion_de_entorno", lambda e: pytest.fail("red"))

    assert consultar_control("dev", "fhvhv", "silver", "2024-01") == []


def test_backend_por_defecto_es_snowflake():
    instalar_backend(None)

    assert isinstance(control._backend(), ControlEnSnowflake)


# --- el rol -------------------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("entorno", "rol"), [("dev", "BIGDATA_DEV"), ("prod", "BIGDATA_PROD"), ("dev", "bigdata_dev")]
)
def test_el_rol_del_entorno_pasa(entorno, rol):
    exigir_rol_del_entorno(entorno, ConexionFalsa(rol=rol))


def test_accountadmin_se_rechaza_en_los_dos_entornos():
    for entorno in ("dev", "prod"):
        with pytest.raises(EntornoNoPermitido, match="ACCOUNTADMIN"):
            exigir_rol_del_entorno(entorno, ConexionFalsa(rol="ACCOUNTADMIN"))


def test_el_rol_de_dev_se_rechaza_en_prod_y_el_de_prod_en_dev():
    with pytest.raises(EntornoNoPermitido, match="BIGDATA_PROD"):
        exigir_rol_del_entorno("prod", ConexionFalsa(rol="BIGDATA_DEV"))
    with pytest.raises(EntornoNoPermitido, match="BIGDATA_DEV"):
        exigir_rol_del_entorno("dev", ConexionFalsa(rol="BIGDATA_PROD"))
