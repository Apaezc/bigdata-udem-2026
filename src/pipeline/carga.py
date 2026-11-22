"""Paso snowflake: lleva gold a una tabla de Snowflake. No usa Spark.

Por cada mes y por cada tabla de TABLAS_A_CARGAR, la tabla de control decide si se salta; si no,
tres pasos en este orden:

    1. verificar_esquema_con_athena: ¿las columnas de gold (según Athena) son las de la tabla?
    2. crear_tabla(ddl): crea la tabla en Snowflake si todavía no existe.
    3. cargar_gold: reemplaza ese mes en la tabla con los Parquet de gold.

La tabla de Snowflake se llama BIGDATA.<ENTORNO>.<TABLA EN MAYÚSCULAS>, por ejemplo
BIGDATA.DEV.TARIFA_POR_MILLA_BARRIO (dev escribe en BIGDATA.DEV, prod en BIGDATA.PROD).

El CREATE TABLE de la casa lleva IF NOT EXISTS: se puede correr cuantas veces haga falta. En
clase se ejecuta también a mano, en una celda, justo antes de `cargar_snowflake()`, para que se
vea el momento en que nace la tabla.

Para agregar la tuya: escribe su CREATE TABLE (con las columnas de tu tabla de gold: mismo
nombre y tipos compatibles) y súmala a TABLAS_A_CARGAR.

Este módulo no importa pyspark: corre igual en la VM de Airflow, que no lo tiene.
"""

from __future__ import annotations

from typing import Any

from pipeline.herramientas import (
    Resultado,
    cargar_gold,
    con_control,
    crear_tabla,
    nombre_tabla_athena,
    nombre_tabla_snowflake,
    ruta_lake,
    verificar_esquema_con_athena,
)

CAPA = "snowflake"

# Las columnas salen de tarifa_por_milla_por_barrio (gold.py): mismo nombre y tipos compatibles
# (el nombre de las columnas se compara sin importar mayúsculas).
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

# Cada entrada: la tabla de gold y el CREATE TABLE de su tabla en Snowflake ({tabla} se llena sola).
TABLAS_A_CARGAR = [
    {"gold": "tarifa_por_milla_barrio", "ddl": DDL_TARIFA_POR_MILLA},
]


def _cargar_una_tabla(corrida: Any, mes: str, entrada: dict, conexion: Any) -> Resultado:
    """La puerta decide; si pasa: verificar con Athena -> crear la tabla -> cargar gold."""
    entorno = corrida.entorno
    tabla_gold = entrada["gold"]
    tabla_snowflake = nombre_tabla_snowflake(entorno, tabla_gold)
    tabla_athena = nombre_tabla_athena(entorno, "gold", tabla_gold)
    fuente = ruta_lake(entorno, "gold", tabla_gold, mes)

    def trabajo() -> tuple[int, int]:
        verificar_esquema_con_athena(tabla_athena, tabla_snowflake, conexion)
        crear_tabla(entrada["ddl"].format(tabla=tabla_snowflake), conexion)
        filas = cargar_gold(tabla_snowflake, tabla_gold, mes=mes, conexion=conexion)
        return filas, filas

    return con_control(corrida, tabla_gold, CAPA, mes, fuente, trabajo, conexion)


def main(corrida: Any, conexion: Any = None) -> list[Resultado]:
    """Carga a Snowflake los meses de la corrida. No imprime banner ni cierre."""
    resultados: list[Resultado] = []
    for mes in corrida.meses:
        for entrada in TABLAS_A_CARGAR:
            resultados.append(_cargar_una_tabla(corrida, mes, entrada, conexion))
    return resultados
