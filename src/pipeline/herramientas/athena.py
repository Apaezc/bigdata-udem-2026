"""Athena como catálogo: ¿las columnas de gold en S3 coinciden con la tabla de Snowflake?

Antes de cargar a Snowflake se comparan las columnas que Athena declara para la tabla de gold
(`dev_gold_tarifa_por_milla_barrio`) con las de la tabla de Snowflake. Así una columna nueva en
gold que a la tabla le falta se detecta antes del COPY, con un mensaje que dice qué hacer.

Solo se lee el catálogo de Glue (el mismo que usa Athena): no se escanea S3 ni se paga una consulta.
Las columnas de partición (`mes`) no cuentan: viven en el nombre de la carpeta, no dentro del
Parquet, y la tabla de Snowflake no las tiene.

Si Athena no responde (la tabla no existe en el catálogo o el rol no tiene permiso, como la VM de
prod), se avisa y se sigue: la carga a Snowflake vuelve a comparar contra los Parquet.
"""

from __future__ import annotations

import re
from typing import Any

from pipeline.herramientas import archivos, bodega
from pipeline.herramientas.rutas import validar_capa, validar_entorno

BASE_ATHENA = "bigdata_lake"

# Tipo de Glue -> tipo de Snowflake, para el ALTER TABLE que se sugiere.
TIPOS_DE_SNOWFLAKE = {
    "string": "VARCHAR",
    "varchar": "VARCHAR",
    "char": "VARCHAR",
    "tinyint": "NUMBER(38,0)",
    "smallint": "NUMBER(38,0)",
    "int": "NUMBER(38,0)",
    "integer": "NUMBER(38,0)",
    "bigint": "NUMBER(38,0)",
    "float": "FLOAT",
    "double": "FLOAT",
    "date": "DATE",
    "timestamp": "TIMESTAMP_NTZ",
    "boolean": "BOOLEAN",
}


def nombre_tabla_athena(entorno: str, capa: str, tabla: str) -> str:
    """'dev', 'silver', 'fhvhv' -> 'dev_silver_fhvhv' (así se llaman las tablas en Athena)."""
    return f"{validar_entorno(entorno)}_{validar_capa(capa)}_{tabla}"


def _cliente_de_glue() -> Any:
    import boto3  # import tardío: fuera de AWS no hace falta

    return boto3.client("glue")


def esquema_de_athena(tabla: str, base: str = BASE_ATHENA) -> dict[str, str] | None:
    """{columna: tipo} de la tabla en el catálogo (sin columnas de partición), o None.

    None si la tabla no existe o no hay permiso para verla; en ese caso avisa por qué.
    """
    archivos.anunciar("CONSULTA", f"athena://{base}.{tabla}", "catálogo de Glue, sin escanear S3")
    try:
        respuesta = _cliente_de_glue().get_table(DatabaseName=base, Name=tabla)
    except Exception as error:
        print(f"AVISO    No pude leer {base}.{tabla} en el catálogo de Athena: {_resumen(error)}")
        return None
    columnas = respuesta["Table"]["StorageDescriptor"]["Columns"]
    return {columna["Name"]: columna["Type"] for columna in columnas}


def _resumen(error: Exception) -> str:
    """Una frase corta del error de AWS (el código, p. ej. EntityNotFoundException)."""
    detalle = getattr(error, "response", {}).get("Error", {})
    codigo = detalle.get("Code") or type(error).__name__
    if codigo == "EntityNotFoundException":
        return "la tabla no existe (¿declaraste las tablas con athena/01_tablas.sql?)"
    if codigo in ("AccessDeniedException", "AccessDenied"):
        return "tu rol no tiene permiso sobre el catálogo de Glue"
    return str(codigo)


def _tipo_para_snowflake(tipo_de_glue: str) -> str:
    """'bigint' -> 'NUMBER(38,0)'; 'decimal(10,2)' -> 'NUMBER(10,2)'. Lo desconocido pasa igual."""
    coincide = re.fullmatch(r"decimal\((\d+),\s*(\d+)\)", tipo_de_glue.strip().lower())
    if coincide:
        return f"NUMBER({coincide.group(1)},{coincide.group(2)})"
    return TIPOS_DE_SNOWFLAKE.get(tipo_de_glue.strip().lower(), tipo_de_glue.upper())


def verificar_esquema_con_athena(
    tabla_athena: str, tabla_snowflake: str, conexion: Any = None
) -> None:
    """Compara las columnas de la tabla de Athena con las de la tabla de Snowflake.

    Lanza ColumnasDistintas, sin tocar nada, si no coinciden. Si Athena no responde, o si la tabla
    de Snowflake todavía no existe (la creas tú en Snowsight), avisa y sigue
    (cargar_gold se detiene).
    """
    en_athena = esquema_de_athena(tabla_athena)
    if en_athena is None:
        print(f"AVISO    Sigo sin verificar con Athena: {tabla_athena} no se pudo consultar.")
        return
    try:
        en_snowflake = bodega.esquema_de_tabla(tabla_snowflake, conexion)
    except RuntimeError:
        print(
            f"AVISO    {tabla_snowflake} no existe todavía: nada que comparar con "
            f"{tabla_athena}. Créala tú en Snowsight; la carga se detiene si falta."
        )
        return

    diferencias = bodega.comparar_columnas(en_athena, en_snowflake)
    if not any(diferencias.values()):
        print(f"OK       Columnas de {tabla_athena} (Athena) = columnas de {tabla_snowflake}.")
        return
    tipos_para_alter = {n: _tipo_para_snowflake(t) for n, t in en_athena.items()}
    raise bodega.ColumnasDistintas(
        bodega.mensaje_de_diferencias(
            tabla_snowflake, f"tabla {tabla_athena} de Athena", diferencias, tipos_para_alter
        )
    )
