"""bodega: comparación de columnas y carga atómica (nunca crea tablas), con una conexión falsa."""

from __future__ import annotations

import json

import pytest

from pipeline.herramientas import bodega
from pipeline.herramientas.bodega import (
    ColumnasDistintas,
    cargar_gold,
    comparar_columnas,
    esquema_de_tabla,
)

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
        self.valores_infer: tuple = ()

    def execute(self, sql, valores=None):
        self.sentencias.append(sql)
        if self.falla_en and sql.startswith(self.falla_en):
            raise RuntimeError(f"fallo simulado en {self.falla_en}")
        if sql.startswith("LIST"):
            self._respuesta = [
                ("s3://lago/dev/gold/daily_zone_metrics/_SUCCESS", 0, "m", "f"),
                ("s3://lago/dev/gold/daily_zone_metrics/mes=2024-01/part-0.parquet", 99, "m", "f"),
                ("s3://lago/dev/gold/daily_zone_metrics/mes=2024-02/part-0.parquet", 99, "m", "f"),
            ]
        elif "INFER_SCHEMA" in sql:
            self.valores_infer = valores
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
    return cargar_gold(TABLA, "daily_zone_metrics", conexion=ConexionFalsa(cursor), **kwargs)


def test_columnas_iguales_carga_y_reemplaza_el_mes():
    cursor = CursorFalso(TIPOS_BASE, TABLA_BASE, filas_copiadas=42)

    filas = _cargar(cursor, mes="2024-01")

    assert filas == 42
    assert cursor.empiezan_con("COPY INTO BIGDATA.DEV.CARGA_GOLD_TMP")
    assert "mes=2024-01/" in cursor.empiezan_con("COPY INTO")[0]
    assert cursor.sentencias[-4:][0] == "BEGIN"
    assert cursor.sentencias[-1] == "COMMIT"
    assert "DELETE FROM BIGDATA.DEV.GOLD_ALUMNO WHERE FECHA >=" in cursor.sentencias[-3]
    assert cursor.sentencias[-2].startswith("INSERT INTO BIGDATA.DEV.GOLD_ALUMNO SELECT")


def test_la_tabla_temporal_va_calificada_en_todas_las_sentencias():
    cursor = CursorFalso(TIPOS_BASE, TABLA_BASE)

    _cargar(cursor)

    con_temporal = [sql for sql in cursor.sentencias if "CARGA_GOLD_TMP" in sql]
    assert len(con_temporal) == 4  # CREATE, COPY, COUNT, INSERT
    assert all("BIGDATA.DEV.CARGA_GOLD_TMP" in sql for sql in con_temporal)


def test_infer_schema_usa_un_solo_parquet_y_el_copy_filtra_por_patron():
    cursor = CursorFalso(TIPOS_BASE, TABLA_BASE)

    _cargar(cursor)

    assert "PATTERN = '.*[.]parquet'" in cursor.empiezan_con("LIST")[0]
    assert "PATTERN = '.*[.]parquet'" in cursor.empiezan_con("COPY INTO")[0]
    infer = [sql for sql in cursor.sentencias if "INFER_SCHEMA" in sql]
    assert "FILES =>" in infer[0]
    assert cursor.valores_infer == (
        "@BIGDATA.DEV.LAKE_GOLD/daily_zone_metrics/",
        "BIGDATA.DEV.PARQUET_FF",
        "mes=2024-02/part-0.parquet",  # el más reciente; _SUCCESS (0 bytes) no cuenta
    )


def test_nombre_de_tabla_sin_base_y_esquema_se_rechaza():
    with pytest.raises(ValueError, match="BASE.ESQUEMA.TABLA"):
        cargar_gold(
            "GOLD_ALUMNO", "daily_zone_metrics", conexion=ConexionFalsa(CursorFalso({}, {}))
        )


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
    # El ALTER lleva el tipo real que trae S3, no un VARCHAR fijo.
    assert "ALTER TABLE BIGDATA.DEV.GOLD_ALUMNO ADD COLUMN RANGO_DISTANCIA TEXT;" in mensaje
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

    cargar_gold(TABLA, "daily_zone_metrics", conexion=conexion)

    assert conexion.cerrada is False


def test_mes_invalido():
    with pytest.raises(ValueError, match="YYYY-MM"):
        _cargar(CursorFalso(TIPOS_BASE, TABLA_BASE), mes="enero")


def test_comparar_columnas_ignora_mayusculas_y_acepta_entero_en_float():
    diferencias = comparar_columnas({"viajes": "NUMBER(19,0)"}, {"VIAJES": "FLOAT"})

    assert diferencias == {"solo_s3": [], "solo_snowflake": [], "tipos_distintos": []}


def test_el_alter_usa_el_tipo_real_de_cada_columna_nueva():
    en_s3 = {**TIPOS_BASE, "pasajeros": "NUMBER(38, 0)", "propina": "REAL"}
    cursor = CursorFalso(en_s3, TABLA_BASE)

    with pytest.raises(ColumnasDistintas) as error:
        _cargar(cursor)

    mensaje = str(error.value)
    assert "ADD COLUMN PASAJEROS NUMBER(38, 0);" in mensaje
    assert "ADD COLUMN PROPINA REAL;" in mensaje


def test_opciones_desconocidas_de_cargar_gold_fallan_antes_de_conectarse():
    with pytest.raises(TypeError, match="no conoce estas opciones: rapido"):
        cargar_gold(TABLA, "daily_zone_metrics", rapido=True)


def test_las_opciones_stage_y_formato_se_respetan():
    cursor = CursorFalso(TIPOS_BASE, TABLA_BASE)

    _cargar(
        cursor,
        stage="@OTRA.BASE.STAGE",
        formato_archivo="OTRA.BASE.FORMATO",
    )

    assert not any(sentencia.startswith("CREATE TABLE IF") for sentencia in cursor.sentencias)
    assert any("@OTRA.BASE.STAGE/daily_zone_metrics/" in x for x in cursor.sentencias)
    assert cursor.valores_infer[1] == "OTRA.BASE.FORMATO"


# --- la conexión sale del secreto del entorno de la tabla -----------------------------------------


@pytest.mark.parametrize(
    ("tabla", "entorno"),
    [("BIGDATA.DEV.GOLD_ALUMNO", "dev"), ("BIGDATA.PROD.GOLD_ALUMNO", "prod")],
)
def test_sin_conexion_se_abre_la_del_entorno_de_la_tabla_y_se_cierra(monkeypatch, tabla, entorno):
    conexion = ConexionFalsa(CursorFalso(TIPOS_BASE, TABLA_BASE))
    pedidas = []

    def abrir(nombre_entorno):
        pedidas.append(nombre_entorno)
        return conexion

    monkeypatch.setattr(bodega, "abrir_conexion_de_entorno", abrir)

    cargar_gold(tabla, "daily_zone_metrics")

    assert pedidas == [entorno]
    assert conexion.cerrada is True


# --- esquema_de_tabla ---------------------------------------------------------------------------


def test_esquema_de_tabla_devuelve_columna_y_tipo():
    cursor = CursorFalso(TIPOS_BASE, TABLA_BASE)

    assert esquema_de_tabla(TABLA, ConexionFalsa(cursor)) == TABLA_BASE
    assert cursor.sentencias == ["DESCRIBE TABLE BIGDATA.DEV.GOLD_ALUMNO"]


def test_esquema_de_tabla_inexistente_explica_como_crearla():
    cursor = CursorFalso(TIPOS_BASE, TABLA_BASE, falla_en="DESCRIBE TABLE")

    with pytest.raises(RuntimeError, match="no existe o tu rol no la ve"):
        esquema_de_tabla(TABLA, ConexionFalsa(cursor))


def test_cargar_gold_con_tabla_inexistente_muestra_el_sql_y_no_carga():
    cursor = CursorFalso(TIPOS_BASE, TABLA_BASE, falla_en="DESCRIBE TABLE")
    sql = "USE ROLE BIGDATA_DEV;\nCREATE TABLE IF NOT EXISTS BIGDATA.DEV.GOLD_ALUMNO (FECHA DATE);"

    with pytest.raises(RuntimeError) as error:
        cargar_gold(
            TABLA, "daily_zone_metrics", conexion=ConexionFalsa(cursor), sql_para_crearla=sql
        )

    assert sql in str(error.value)
    assert "vuelve a correr cargar_snowflake" in str(error.value)
    assert not any(x.startswith(("COPY", "INSERT", "DELETE")) for x in cursor.sentencias)


def test_esquema_de_tabla_rechaza_nombres_raros():
    with pytest.raises(ValueError, match="Nombre de tabla inválido"):
        esquema_de_tabla("T; DROP TABLE X", ConexionFalsa(CursorFalso({}, {})))


# --- la conexión del entorno: siempre por secreto, nunca connections.toml -------------------------


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
    monkeypatch.setattr(bodega, "_llave_privada_der", lambda pem: b"der:" + pem.encode())
    parametros = bodega._parametros_de_secreto(secreto_de_airflow())
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
    parametros = bodega._parametros_de_secreto(texto)
    assert parametros == {"account": "a", "user": "AIRFLOW_SVC", "password": "clave"}


def test_el_secreto_sin_llave_ni_password_falla_con_mensaje_claro():
    with pytest.raises(ValueError, match="private_key_content ni password"):
        bodega._parametros_de_secreto(secreto_de_airflow(extra={"account": "a"}))


def test_el_secreto_por_defecto_de_cada_entorno(monkeypatch):
    monkeypatch.delenv(bodega.VARIABLE_SECRETO, raising=False)
    monkeypatch.delenv("PREFIX", raising=False)
    assert bodega.nombre_del_secreto("dev") == "bigdata/snowflake"
    assert bodega.nombre_del_secreto("prod") == "bigdata/snowflake_prod"

    monkeypatch.setenv("PREFIX", "curso")
    assert bodega.nombre_del_secreto("dev") == "curso/snowflake"
    assert bodega.nombre_del_secreto("prod") == "curso/snowflake_prod"


def test_la_variable_del_secreto_gana_sobre_el_defecto(monkeypatch):
    monkeypatch.setenv(bodega.VARIABLE_SECRETO, "otro/secreto")
    assert bodega.nombre_del_secreto("prod") == "otro/secreto"


def test_la_conexion_de_entorno_usa_el_secreto_y_nunca_connections_toml(monkeypatch):
    monkeypatch.delenv(bodega.VARIABLE_SECRETO, raising=False)
    monkeypatch.delenv("PREFIX", raising=False)
    abiertos = []
    monkeypatch.setattr(bodega, "_abrir_conexion_con_secreto", lambda n: abiertos.append(n) or n)

    assert bodega.abrir_conexion_de_entorno("dev") == "bigdata/snowflake"
    assert bodega.abrir_conexion_de_entorno("prod") == "bigdata/snowflake_prod"
    assert abiertos == ["bigdata/snowflake", "bigdata/snowflake_prod"]
