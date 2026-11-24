"""Paso snowflake: lleva gold a una tabla de Snowflake. No usa Spark.

Por cada mes y por cada tabla de TABLAS_A_CARGAR, la tabla de control decide si se salta; si no,
dos pasos en este orden:

    1. verificar_esquema_con_athena: ¿las columnas de gold (según Athena) son las de la tabla?
    2. cargar_gold: reemplaza ese mes en la tabla con los Parquet de gold.

La tabla de Snowflake se llama BIGDATA.<ENTORNO>.<TABLA EN MAYÚSCULAS>, por ejemplo
BIGDATA.DEV.TARIFA_POR_MILLA_BARRIO (dev escribe en BIGDATA.DEV, prod en BIGDATA.PROD).

El código NUNCA crea la tabla: la creas tú, a mano, en Snowsight (una sola vez por tabla). Si falta,
cargar_snowflake se detiene con un error que imprime el SQL exacto para correr allá (USE ROLE...,
CREATE TABLE IF NOT EXISTS ...); luego vuelves a correr cargar_snowflake.

Para agregar la tuya: escribe el CREATE TABLE (con las columnas de tu tabla de gold: mismo nombre
y tipos compatibles), créalo en Snowsight y súmalo a TABLAS_A_CARGAR.

Este módulo no importa pyspark: corre igual en la VM de Airflow, que no lo tiene.
"""

from __future__ import annotations

from typing import Any

from pipeline.herramientas.athena import (
    nombre_tabla_athena,
    verificar_esquema_con_athena,
)
from pipeline.herramientas.bodega import cargar_gold
from pipeline.herramientas.control import con_control
from pipeline.herramientas.corrida import Resultado
from pipeline.herramientas.rutas import nombre_tabla_snowflake, ruta_lake

CAPA = "snowflake"

# El CREATE que tú ejecutas en Snowsight (el código solo lo muestra, nunca lo corre). Las columnas
# salen de tarifa_por_milla_por_barrio (gold.py): mismo nombre y tipos compatibles (el nombre de
# las columnas se compara sin importar mayúsculas).
DDL_TARIFA_POR_MILLA = (
    "CREATE TABLE IF NOT EXISTS {tabla} ("
    "FECHA DATE, "
    "BOROUGH VARCHAR, "
    "FRANJA VARCHAR, "
    "VIAJES NUMBER(38,0), "
    "DISTANCIA_TOTAL_MI FLOAT, "
    "INGRESO_TOTAL FLOAT, "
    "TARIFA_POR_MILLA FLOAT)"
)

# Cada entrada: la tabla de gold y el CREATE TABLE que se muestra para su tabla en Snowflake.
TABLAS_A_CARGAR = [
    {"gold": "tarifa_por_milla_barrio", "ddl": DDL_TARIFA_POR_MILLA},
]


def sql_para_snowsight(entorno: str, tabla_snowflake: str, ddl: str) -> str:
    """El SQL exacto que se corre a mano en Snowsight para crear la tabla (USE ... + CREATE)."""
    permiso = ""
    if entorno == "prod":
        # BIGDATA_PROD es el rol de Airflow en la VM: ningún usuario de Snowsight lo tiene asignado
        # y ACCOUNTADMIN no puede crear tablas en BIGDATA.PROD. Hay que asignárselo una vez.
        permiso = (
            "-- Solo la primera vez, con ACCOUNTADMIN (tu usuario: SELECT CURRENT_USER();):\n"
            'USE ROLE ACCOUNTADMIN;\nGRANT ROLE BIGDATA_PROD TO USER "<tu usuario>";\n'
        )
    return (
        permiso + f"USE ROLE BIGDATA_{entorno.upper()};\n"
        "USE WAREHOUSE BIGDATA_WH;\n"
        "USE DATABASE BIGDATA;\n"
        f"{ddl.format(tabla=tabla_snowflake)};"
    )


def _cargar_una_tabla(corrida: Any, mes: str, entrada: dict, conexion: Any) -> Resultado:
    """La puerta decide; si pasa: verificar con Athena -> cargar gold."""
    entorno = corrida.entorno
    tabla_gold = entrada["gold"]
    tabla_snowflake = nombre_tabla_snowflake(entorno, tabla_gold)
    tabla_athena = nombre_tabla_athena(entorno, "gold", tabla_gold)
    fuente = ruta_lake(entorno, "gold", tabla_gold, mes)

    def trabajo() -> tuple[int, int]:
        verificar_esquema_con_athena(tabla_athena, tabla_snowflake, conexion)
        filas = cargar_gold(
            tabla_snowflake,
            tabla_gold,
            mes=mes,
            conexion=conexion,
            sql_para_crearla=sql_para_snowsight(entorno, tabla_snowflake, entrada["ddl"]),
        )
        return filas, filas

    return con_control(corrida, tabla_gold, CAPA, mes, fuente, trabajo, conexion)


def main(corrida: Any, conexion: Any = None) -> list[Resultado]:
    """Carga a Snowflake los meses de la corrida. No imprime banner ni cierre."""
    resultados: list[Resultado] = []
    for mes in corrida.meses:
        for entrada in TABLAS_A_CARGAR:
            resultados.append(_cargar_una_tabla(corrida, mes, entrada, conexion))
    return resultados
