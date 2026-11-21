"""cargar_gold_a_snowflake: comparación de columnas y carga atómica, con una conexión falsa."""

from __future__ import annotations

import pytest

from pipeline.herramientas import ColumnasDistintas, cargar_gold_a_snowflake, comparar_columnas

TABLA = "BIGDATA.DEV.GOLD_ALUMNO"
TIPOS_BASE = {
    "fecha": "DATE",
    "zona": "TEXT",
    "viajes": "NUMBER(19,0)",
    "ingreso_total": "REAL",
}
TABLA_BASE = {
    "FECHA": "DATE",
    "ZONA": "VARCHAR(16777216)",
    "VIAJES": "NUMBER(38,0)",
    "INGRESO_TOTAL": "FLOAT",
}


class CursorFalso:
    """Guarda cada sentencia y responde lo que Snowflake respondería."""

    def __init__(self, en_s3, en_tabla, falla_en=None, filas_copiadas=10):
        self.en_s3 = en_s3
        self.en_tabla = en_tabla
        self.falla_en = falla_en
        self.filas_copiadas = filas_copiadas
        self.sentencias: list[str] = []
        self._respuesta: list = []

    def execute(self, sql, valores=None):
        self.sentencias.append(sql)
        if self.falla_en and sql.startswith(self.falla_en):
            raise RuntimeError(f"fallo simulado en {self.falla_en}")
        if "INFER_SCHEMA" in sql:
            self._respuesta = list(self.en_s3.items())
        elif sql.startswith("DESCRIBE TABLE"):
            self._respuesta = [(nombre, tipo, "COLUMN") for nombre, tipo in self.en_tabla.items()]
        elif sql.startswith("SELECT COUNT"):
            self._respuesta = [(self.filas_copiadas,)]

    def fetchall(self):
        return self._respuesta

    def fetchone(self):
        return self._respuesta[0]

    def empiezan_con(self, prefijo: str) -> list[str]:
        return [sql for sql in self.sentencias if sql.startswith(prefijo)]


class ConexionFalsa:
    def __init__(self, cursor):
        self._cursor = cursor
        self.cerrada = False

    def cursor(self):
        return self._cursor

    def close(self):
        self.cerrada = True


def _cargar(cursor, **kwargs):
    return cargar_gold_a_snowflake(
        TABLA, "daily_zone_metrics", conexion=ConexionFalsa(cursor), **kwargs
    )


def test_columnas_iguales_carga_y_reemplaza_el_mes():
    cursor = CursorFalso(TIPOS_BASE, TABLA_BASE, filas_copiadas=42)

    filas = _cargar(cursor, mes="2024-01")

    assert filas == 42
    assert cursor.empiezan_con("COPY INTO CARGA_GOLD_TMP")
    assert "mes=2024-01/" in cursor.empiezan_con("COPY INTO")[0]
    assert cursor.sentencias[-4:][0] == "BEGIN"
    assert cursor.sentencias[-1] == "COMMIT"
    assert "DELETE FROM BIGDATA.DEV.GOLD_ALUMNO WHERE FECHA >=" in cursor.sentencias[-3]
    assert cursor.sentencias[-2].startswith("INSERT INTO BIGDATA.DEV.GOLD_ALUMNO SELECT")


def test_sin_mes_borra_toda_la_tabla_dentro_de_la_transaccion():
    cursor = CursorFalso(TIPOS_BASE, TABLA_BASE)

    _cargar(cursor)

    assert "DELETE FROM BIGDATA.DEV.GOLD_ALUMNO" in cursor.sentencias
    assert not cursor.empiezan_con("TRUNCATE")
    assert cursor.sentencias.index("BEGIN") < cursor.sentencias.index("COMMIT")


def test_columna_de_mas_en_s3_da_error_claro_y_no_toca_la_tabla():
    en_s3 = {**TIPOS_BASE, "rango_distancia": "TEXT"}
    cursor = CursorFalso(en_s3, TABLA_BASE)

    with pytest.raises(ColumnasDistintas) as error:
        _cargar(cursor)

    mensaje = str(error.value)
    assert "Solo en S3" in mensaje
    assert "RANGO_DISTANCIA" in mensaje
    assert "ALTER TABLE BIGDATA.DEV.GOLD_ALUMNO ADD COLUMN RANGO_DISTANCIA" in mensaje
    assert not cursor.empiezan_con("COPY")
    assert not cursor.empiezan_con("DELETE")


def test_columna_que_falta_en_s3_da_error_claro_y_no_toca_la_tabla():
    en_s3 = {nombre: tipo for nombre, tipo in TIPOS_BASE.items() if nombre != "ingreso_total"}
    cursor = CursorFalso(en_s3, TABLA_BASE)

    with pytest.raises(ColumnasDistintas) as error:
        _cargar(cursor)

    mensaje = str(error.value)
    assert "Solo en Snowflake" in mensaje
    assert "INGRESO_TOTAL" in mensaje
    assert "gold.py" in mensaje
    assert not cursor.empiezan_con("COPY")
    assert not cursor.empiezan_con("DELETE")


def test_tipo_distinto_da_error():
    tabla = {**TABLA_BASE, "VIAJES": "VARCHAR"}
    cursor = CursorFalso(TIPOS_BASE, tabla)

    with pytest.raises(ColumnasDistintas) as error:
        _cargar(cursor)

    assert "Tipo distinto en VIAJES" in str(error.value)


def test_si_falla_el_copy_la_tabla_no_se_toca():
    cursor = CursorFalso(TIPOS_BASE, TABLA_BASE, falla_en="COPY INTO")

    with pytest.raises(RuntimeError):
        _cargar(cursor)

    assert not cursor.empiezan_con("BEGIN")
    assert not cursor.empiezan_con("DELETE")
    assert not cursor.empiezan_con("TRUNCATE")


def test_si_falla_el_insert_se_hace_rollback():
    cursor = CursorFalso(TIPOS_BASE, TABLA_BASE, falla_en="INSERT INTO")

    with pytest.raises(RuntimeError):
        _cargar(cursor)

    assert cursor.sentencias[-1] == "ROLLBACK"
    assert not cursor.empiezan_con("COMMIT")


def test_copy_sin_filas_no_borra_nada():
    cursor = CursorFalso(TIPOS_BASE, TABLA_BASE, filas_copiadas=0)

    with pytest.raises(RuntimeError, match="no cargó ninguna fila"):
        _cargar(cursor)

    assert not cursor.empiezan_con("DELETE")


def test_conexion_propia_se_cierra_y_la_ajena_no():
    cursor = CursorFalso(TIPOS_BASE, TABLA_BASE)
    conexion = ConexionFalsa(cursor)

    cargar_gold_a_snowflake(TABLA, "daily_zone_metrics", conexion=conexion)

    assert conexion.cerrada is False


def test_mes_invalido():
    with pytest.raises(ValueError, match="YYYY-MM"):
        _cargar(CursorFalso(TIPOS_BASE, TABLA_BASE), mes="enero")


def test_comparar_columnas_ignora_mayusculas_y_acepta_entero_en_float():
    diferencias = comparar_columnas({"viajes": "NUMBER(19,0)"}, {"VIAJES": "FLOAT"})

    assert diferencias == {"solo_s3": [], "solo_snowflake": [], "tipos_distintos": []}
