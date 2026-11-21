"""Carga de gold (Parquet en S3) a una tabla de Snowflake, sin perder columnas en silencio.

El problema que resuelve: con COPY ... MATCH_BY_COLUMN_NAME, una columna nueva en gold que la
tabla no tiene se ignora sin error, y el run queda en verde con datos incompletos. Aquí, antes de
cargar, se comparan las columnas del Parquet con las de la tabla; si no coinciden, la carga se
detiene con un mensaje que dice qué sobra, qué falta y qué hacer.

Por qué INFER_SCHEMA y no pyarrow: lo ejecuta Snowflake, que ya tiene permiso sobre S3 por la
storage integration (stage LAKE_GOLD, infra/snowflake). Así no hace falta instalar pyarrow ni
tener credenciales de AWS en Python, y el Code Editor y Airflow usan el mismo código.

Por qué es atómica: el COPY se hace primero a una tabla temporal. Solo si salió bien, en una
transacción se borra lo viejo de la tabla real y se inserta lo nuevo. Si algo falla, ROLLBACK:
la tabla queda como estaba. (TRUNCATE no sirve para esto: en Snowflake es DDL y confirma solo.)
"""

from __future__ import annotations

import os
import re
from typing import Any

# Igual que watermark.py: rol y warehouse con los que trabaja el Code Editor.
ROL = "ACCOUNTADMIN"
WAREHOUSE = "COMPUTE_WH"
CONEXION_POR_DEFECTO = "default"
VARIABLE_CONEXION = "WATERMARK_CONNECTION"

TABLA_TEMPORAL = "CARGA_GOLD_TMP"
PATRON_MES = re.compile(r"^\d{4}-\d{2}$")
PATRON_IDENTIFICADOR = re.compile(r"^[A-Za-z0-9_$]+(\.[A-Za-z0-9_$]+)*$")

# Cada tipo de Snowflake se reduce a una familia para compararlo con el que infiere el Parquet.
FAMILIAS = {
    "TEXT": "TEXTO",
    "VARCHAR": "TEXTO",
    "STRING": "TEXTO",
    "CHAR": "TEXTO",
    "NUMBER": "NUMERO",
    "DECIMAL": "NUMERO",
    "NUMERIC": "NUMERO",
    "INT": "NUMERO",
    "INTEGER": "NUMERO",
    "BIGINT": "NUMERO",
    "SMALLINT": "NUMERO",
    "FLOAT": "DECIMAL",
    "FLOAT4": "DECIMAL",
    "FLOAT8": "DECIMAL",
    "DOUBLE": "DECIMAL",
    "REAL": "DECIMAL",
    "DATE": "FECHA",
    "TIMESTAMP_NTZ": "TIMESTAMP",
    "TIMESTAMP_LTZ": "TIMESTAMP",
    "TIMESTAMP_TZ": "TIMESTAMP",
    "TIMESTAMP": "TIMESTAMP",
    "BOOLEAN": "BOOLEANO",
}
# Un entero del Parquet cabe sin problema en una columna FLOAT.
FAMILIAS_COMPATIBLES = {("NUMERO", "DECIMAL")}


class ColumnasDistintas(Exception):
    """Las columnas de gold en S3 no coinciden con las de la tabla de Snowflake."""


def _familia(tipo: str) -> str:
    """'NUMBER(38,0)' -> 'NUMERO'. Un tipo que no conocemos se compara tal cual."""
    base = tipo.split("(")[0].strip().upper()
    return FAMILIAS.get(base, base)


def comparar_columnas(en_s3: dict[str, str], en_snowflake: dict[str, str]) -> dict[str, list]:
    """Compara {columna: tipo} de S3 contra {columna: tipo} de la tabla.

    Los nombres se comparan sin distinguir mayúsculas (Snowflake guarda FECHA, Spark escribe
    fecha). Devuelve tres listas, todas vacías si coinciden:
        solo_s3          columnas que están en el Parquet y no en la tabla
        solo_snowflake   columnas que están en la tabla y no en el Parquet
        tipos_distintos  (columna, tipo_s3, tipo_snowflake) de las que están en ambos lados
    """
    s3 = {nombre.upper(): tipo for nombre, tipo in en_s3.items()}
    tabla = {nombre.upper(): tipo for nombre, tipo in en_snowflake.items()}

    solo_s3 = [nombre for nombre in s3 if nombre not in tabla]
    solo_snowflake = [nombre for nombre in tabla if nombre not in s3]

    tipos_distintos = []
    for nombre in s3:
        if nombre not in tabla:
            continue
        familia_s3 = _familia(s3[nombre])
        familia_tabla = _familia(tabla[nombre])
        if familia_s3 == familia_tabla:
            continue
        if (familia_s3, familia_tabla) in FAMILIAS_COMPATIBLES:
            continue
        tipos_distintos.append((nombre, s3[nombre], tabla[nombre]))

    return {
        "solo_s3": solo_s3,
        "solo_snowflake": solo_snowflake,
        "tipos_distintos": tipos_distintos,
    }


def _mensaje_de_diferencias(tabla: str, ubicacion: str, diferencias: dict[str, list]) -> str:
    """Arma el error en español: qué sobra, qué falta y qué hacer."""
    lineas = [
        f"No se cargó nada: las columnas de gold ({ubicacion}) no coinciden con la tabla {tabla}.",
        "",
    ]
    solo_s3 = diferencias["solo_s3"]
    solo_snowflake = diferencias["solo_snowflake"]
    tipos = diferencias["tipos_distintos"]

    if solo_s3:
        lineas.append(f"  Solo en S3 (gold las trae, la tabla no): {', '.join(solo_s3)}")
    if solo_snowflake:
        lineas.append(
            f"  Solo en Snowflake (la tabla las tiene, gold no): {', '.join(solo_snowflake)}"
        )
    for nombre, tipo_s3, tipo_tabla in tipos:
        lineas.append(
            f"  Tipo distinto en {nombre}: S3 trae {tipo_s3}, la tabla tiene {tipo_tabla}"
        )

    lineas.append("")
    lineas.append("Qué hacer:")
    if solo_s3:
        lineas.append("  - Si la columna es nueva a propósito, agrégala a la tabla, por ejemplo:")
        lineas.append(f"      ALTER TABLE {tabla} ADD COLUMN {solo_s3[0]} VARCHAR;")
        lineas.append("    (o vuelve a crear la tabla con tu CREATE TABLE completo).")
    if solo_snowflake:
        lineas.append("  - Si gold debía traer la columna, corrige gold.py (COLUMNAS y el select)")
        lineas.append("    y vuelve a correr gold. Si ya no la quieres en la tabla:")
        lineas.append(f"      ALTER TABLE {tabla} DROP COLUMN {solo_snowflake[0]};")
    if tipos:
        lineas.append(
            "  - Si el tipo es distinto, cambia el tipo en tu CREATE TABLE o el cast en gold.py."
        )
    return "\n".join(lineas)


def abrir_conexion(connection_name: str | None = None) -> Any:
    """Abre la conexión a Snowflake con el mismo archivo connections.toml que usa watermark.py."""
    import snowflake.connector  # import tardío: solo se necesita al hablar con Snowflake

    nombre = connection_name or os.environ.get(VARIABLE_CONEXION, CONEXION_POR_DEFECTO)
    conexion = snowflake.connector.connect(connection_name=nombre)
    try:
        cursor = conexion.cursor()
        cursor.execute(f"USE ROLE {ROL}")
        cursor.execute(f"USE WAREHOUSE {WAREHOUSE}")
    except Exception:
        conexion.close()
        raise
    return conexion


def _columnas_de_gold(cursor: Any, ubicacion: str, formato: str) -> dict[str, str]:
    """Columnas y tipos que Snowflake infiere de los Parquet que hay en esa ubicación del stage."""
    try:
        cursor.execute(
            "SELECT COLUMN_NAME, TYPE FROM TABLE(INFER_SCHEMA(LOCATION => %s, FILE_FORMAT => %s))",
            (ubicacion, formato),
        )
        filas = cursor.fetchall()
    except Exception as error:
        raise RuntimeError(
            f"No se pudo leer el esquema de los Parquet en {ubicacion}. Revisa que gold haya "
            f"escrito archivos ahí y que exista el formato {formato}. Detalle: {error}"
        ) from error
    if not filas:
        raise RuntimeError(f"No hay archivos Parquet en {ubicacion}: corre gold antes de cargar.")
    return {fila[0]: fila[1] for fila in filas}


def _columnas_de_tabla(cursor: Any, tabla: str) -> dict[str, str]:
    """Columnas y tipos de la tabla de Snowflake (DESCRIBE TABLE: nombre en [0], tipo en [1])."""
    try:
        cursor.execute(f"DESCRIBE TABLE {tabla}")
        filas = cursor.fetchall()
    except Exception as error:
        raise RuntimeError(
            f"No se pudo leer la tabla {tabla}: no existe o tu rol no la ve. Créala primero con "
            f"tu CREATE TABLE (mira docs/herramientas.md). Detalle: {error}"
        ) from error
    return {fila[0]: fila[1] for fila in filas}


def cargar_gold_a_snowflake(
    tabla_snowflake: str,
    carpeta_gold: str,
    mes: str | None = None,
    conexion: Any = None,
    columna_fecha: str = "FECHA",
    stage: str | None = None,
    formato_archivo: str | None = None,
    crear_si_no_existe: str | None = None,
) -> int:
    """Carga gold desde S3 a una tabla de Snowflake. Devuelve cuántas filas cargó.

    tabla_snowflake  nombre completo, por ejemplo 'BIGDATA.DEV.DAILY_ZONE_METRICS'.
    carpeta_gold     carpeta de la tabla dentro de gold, por ejemplo 'daily_zone_metrics'
                     (el stage LAKE_GOLD ya apunta a s3://<lake>/<entorno>/gold/).
    mes              'YYYY-MM': reemplaza solo ese mes (carpeta mes=YYYY-MM/). None: reemplaza
                     toda la tabla.
    conexion         conexión abierta de Snowflake; si es None se abre con connections.toml y
                     se cierra al terminar.
    columna_fecha    columna DATE de la tabla; se usa para borrar el mes antes de insertar.
    stage            por defecto @<base>.<esquema>.LAKE_GOLD, tomado del nombre de la tabla.
    formato_archivo  por defecto <base>.<esquema>.PARQUET_FF.
    crear_si_no_existe  CREATE TABLE IF NOT EXISTS ... para la tabla de la casa (el DAG); el
                     estudiante no lo necesita: crea su tabla él mismo.

    Falla con ColumnasDistintas, sin tocar la tabla, si las columnas de S3 y de la tabla no
    coinciden. Falla con cualquier error de COPY o de la transacción, también sin tocarla.
    """
    if not PATRON_IDENTIFICADOR.match(tabla_snowflake):
        raise ValueError(f"Nombre de tabla inválido: {tabla_snowflake!r}")
    if mes is not None and not PATRON_MES.match(mes):
        raise ValueError(f"mes debe tener la forma YYYY-MM, por ejemplo 2024-01 (llegó {mes!r})")

    partes = tabla_snowflake.split(".")
    if len(partes) == 3:
        stage = stage or f"@{partes[0]}.{partes[1]}.LAKE_GOLD"
        formato_archivo = formato_archivo or f"{partes[0]}.{partes[1]}.PARQUET_FF"
    if not stage or not formato_archivo:
        raise ValueError(
            "Usa el nombre completo BASE.ESQUEMA.TABLA, o indica stage y formato_archivo."
        )

    ubicacion = f"{stage}/{carpeta_gold.strip('/')}/"
    if mes:
        ubicacion += f"mes={mes}/"

    cerrar_al_final = conexion is None
    if conexion is None:
        conexion = abrir_conexion()
    try:
        cursor = conexion.cursor()

        # 1. La tabla de la casa se crea sola; la del estudiante ya debe existir.
        if crear_si_no_existe:
            cursor.execute(crear_si_no_existe)

        # 2. Comparar columnas ANTES de tocar nada.
        en_s3 = _columnas_de_gold(cursor, ubicacion, formato_archivo)
        en_tabla = _columnas_de_tabla(cursor, tabla_snowflake)
        diferencias = comparar_columnas(en_s3, en_tabla)
        hay_diferencias = (
            diferencias["solo_s3"]
            or diferencias["solo_snowflake"]
            or diferencias["tipos_distintos"]
        )
        if hay_diferencias:
            raise ColumnasDistintas(
                _mensaje_de_diferencias(tabla_snowflake, ubicacion, diferencias)
            )
        if columna_fecha.upper() not in {nombre.upper() for nombre in en_tabla}:
            raise ColumnasDistintas(
                f"La tabla {tabla_snowflake} no tiene la columna de fecha {columna_fecha}, que se "
                f"usa para reemplazar el mes. Indica otra con columna_fecha=..."
            )

        # 3. COPY a una tabla temporal: si falla aquí, la tabla real no se ha tocado.
        #    FORCE = TRUE porque Snowflake recuerda 64 días los archivos ya cargados.
        cursor.execute(f"CREATE OR REPLACE TEMPORARY TABLE {TABLA_TEMPORAL} LIKE {tabla_snowflake}")
        cursor.execute(
            f"COPY INTO {TABLA_TEMPORAL} FROM '{ubicacion}' "
            "FILE_FORMAT = (TYPE = PARQUET) MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE "
            "PATTERN = '.*[.]parquet' FORCE = TRUE ON_ERROR = ABORT_STATEMENT"
        )
        cursor.execute(f"SELECT COUNT(*) FROM {TABLA_TEMPORAL}")
        filas = int(cursor.fetchone()[0])
        if filas == 0:
            # Borrar lo viejo y no insertar nada dejaría la tabla vacía.
            raise RuntimeError(
                f"El COPY desde {ubicacion} no cargó ninguna fila; no se tocó la tabla."
            )

        # 4. Reemplazo atómico: o queda todo lo nuevo, o todo lo viejo.
        cursor.execute("BEGIN")
        try:
            if mes:
                cursor.execute(
                    f"DELETE FROM {tabla_snowflake} WHERE {columna_fecha} >= TO_DATE('{mes}-01') "
                    f"AND {columna_fecha} < DATEADD(MONTH, 1, TO_DATE('{mes}-01'))"
                )
            else:
                cursor.execute(f"DELETE FROM {tabla_snowflake}")
            cursor.execute(f"INSERT INTO {tabla_snowflake} SELECT * FROM {TABLA_TEMPORAL}")
            cursor.execute("COMMIT")
        except Exception:
            cursor.execute("ROLLBACK")
            raise
        return filas
    finally:
        if cerrar_al_final:
            conexion.close()
