"""Tabla de control de la ingesta: qué se ingestó, de qué mes, cuándo y cuántas filas.

La tabla vive en Snowflake, en BIGDATA.CONTROL.WATERMARK. Cada vez que una ingesta termina
bien, registra una fila; antes de ingestar, la ingesta consulta la tabla para saber si ese mes
ya se trajo. Una ingesta que ya tiene registro no vuelve a descargar, salvo que se pida
reprocesar. Reprocesar no borra nada: crea un lote nuevo y un registro nuevo, y la historia de
la tabla queda completa.

Columnas de la tabla:

    FUENTE      de dónde vienen los datos (la URL que se descargó).
    CAPA        capa del lake que se escribió: 'bronze', 'silver' o 'gold'.
    TABLA       carpeta de la capa: 'fhvhv', 'clima', 'taxi_zones'...
    MES         mes en texto 'AAAA-MM'. Las fuentes sin mes (las zonas) usan MES_SIN_MES.
    FILAS       filas que quedaron escritas en el lote.
    INICIO      momento (UTC) en que arrancó la ingesta.
    REPROCESAR  verdadero si la ingesta se pidió con reprocesar (ignorar el registro anterior).

Hay dos métodos que usan las ingestas:

    consultar_watermark(tabla, capa, mes)   -> texto JSON con la lista de registros
    registrar_watermark(fuente, capa, tabla, mes, filas, inicio, reprocesar)

La conexión usa snowflake.connector con una conexión guardada en ~/.snowflake/connections.toml.
Su nombre es "default" salvo que se indique otro, con el parámetro connection_name o con la
variable de entorno WATERMARK_CONNECTION. Se usa desde el Code Editor de SageMaker. Pendiente
para la clase 6: dentro de Glue no existe ese archivo, así que hay que resolver de dónde sale la
conexión (por ejemplo, un secreto de AWS Secrets Manager con la llave de Snowflake).

El esquema CONTROL y la tabla los crea Terraform (infra/snowflake/main.tf), no este módulo: la
base BIGDATA es de TERRAFORM_ROLE y ACCOUNTADMIN no puede crear esquemas dentro de ella. Terraform
también da a ACCOUNTADMIN y a BIGDATA_DEV (el rol de AIRFLOW_SVC) permiso para consultar, insertar
y borrar filas. Si la tabla no existe o el rol no la ve, falta correr `make snowflake`.
"""

from __future__ import annotations

import json
import os
from datetime import UTC, datetime
from typing import Any

BASE_DATOS = "BIGDATA"
ESQUEMA = "CONTROL"
TABLA_CONTROL = f"{BASE_DATOS}.{ESQUEMA}.WATERMARK"

ROL = "ACCOUNTADMIN"
WAREHOUSE = "COMPUTE_WH"

CONEXION_POR_DEFECTO = "default"
VARIABLE_CONEXION = "WATERMARK_CONNECTION"

# Valor de la columna MES para las fuentes que no se parten por mes (las zonas de taxi).
MES_SIN_MES = "sin_mes"

# Las tablas de demostración y de prueba empiezan con uno de estos prefijos; solo ellas se
# pueden borrar con borrar_registros_de_prueba.
PREFIJOS_DE_PRUEBA = ("demo", "prueba")

COLUMNAS = ["FUENTE", "CAPA", "TABLA", "MES", "FILAS", "INICIO", "REPROCESAR"]

# Código de error de Snowflake cuando el objeto no existe o el rol no tiene permiso para verlo.
ERRNO_TABLA_NO_VISIBLE = 2003
MENSAJE_TABLA_NO_VISIBLE = (
    f"No se encontró la tabla {TABLA_CONTROL}, o el rol {ROL} no tiene permiso sobre ella. La crea "
    f"Terraform: corre `cd ~/bigdata && git pull && make snowflake` y vuelve a intentar."
)
SQL_CONSULTAR = f"""
    SELECT {", ".join(COLUMNAS)}
    FROM {TABLA_CONTROL}
    WHERE TABLA = %s AND CAPA = %s AND MES = %s
    ORDER BY INICIO
"""
SQL_REGISTRAR = f"""
    INSERT INTO {TABLA_CONTROL} ({", ".join(COLUMNAS)})
    VALUES (%s, %s, %s, %s, %s, %s, %s)
"""
SQL_BORRAR = f"DELETE FROM {TABLA_CONTROL} WHERE TABLA = %s"


# --- conexión ---------------------------------------------------------------------------------


def _abrir_conexion(connection_name: str) -> Any:
    """Abre la conexión con snowflake.connector. Es lo único que toca la red."""
    import snowflake.connector  # import tardío: solo se necesita al hablar con Snowflake

    return snowflake.connector.connect(connection_name=connection_name)


def _nombre_de_conexion(connection_name: str | None) -> str:
    """El nombre pedido; si no se pidió ninguno, el de la variable de entorno; si no, 'default'."""
    if connection_name:
        return connection_name
    return os.environ.get(VARIABLE_CONEXION, CONEXION_POR_DEFECTO)


def _conectar(connection_name: str | None) -> Any:
    """Abre la conexión y fija rol y warehouse.

    La conexión por llave no trae warehouse, por eso se indican siempre. La tabla ya debe existir:
    la crea Terraform, esta función no crea ni otorga nada.
    """
    conexion = _abrir_conexion(_nombre_de_conexion(connection_name))
    try:
        cursor = conexion.cursor()
        cursor.execute(f"USE ROLE {ROL}")
        cursor.execute(f"USE WAREHOUSE {WAREHOUSE}")
    except Exception:
        # Si algo falla al preparar la sesión, no se deja la conexión abierta.
        conexion.close()
        raise
    return conexion


def _ejecutar(cursor: Any, sql: str, valores: tuple) -> None:
    """Ejecuta una sentencia sobre la tabla de control y explica el error más común."""
    try:
        cursor.execute(sql, valores)
    except Exception as error:
        if getattr(error, "errno", None) == ERRNO_TABLA_NO_VISIBLE:
            raise RuntimeError(MENSAJE_TABLA_NO_VISIBLE) from error
        raise


# --- conversión de valores ---------------------------------------------------------------------


def _inicio_en_utc(inicio: datetime) -> datetime:
    """Deja la hora de inicio en UTC y sin zona horaria, que es como la guarda la tabla."""
    if inicio.tzinfo is None:
        return inicio
    return inicio.astimezone(UTC).replace(tzinfo=None)


def _registro_a_diccionario(fila: tuple) -> dict:
    """Convierte una fila de la tabla en un diccionario con nombres en minúscula."""
    fuente, capa, tabla, mes, filas, inicio, reprocesar = fila
    return {
        "fuente": fuente,
        "capa": capa,
        "tabla": tabla,
        "mes": mes,
        "filas": int(filas),
        "inicio": inicio.isoformat(),
        "reprocesar": bool(reprocesar),
    }


# --- los dos métodos que usan las ingestas ------------------------------------------------------


def consultar_watermark(tabla: str, capa: str, mes: str, connection_name: str | None = None) -> str:
    """Devuelve, como texto JSON, la lista de registros de esa tabla, capa y mes.

    Los registros salen ordenados por INICIO, del más antiguo al más reciente. Si no hay
    ninguno, devuelve '[]'. Ejemplo de un registro:

        {"fuente": "https://...", "capa": "bronze", "tabla": "clima", "mes": "2024-01",
         "filas": 31, "inicio": "2026-11-17T14:03:22", "reprocesar": false}
    """
    conexion = _conectar(connection_name)
    try:
        cursor = conexion.cursor()
        _ejecutar(cursor, SQL_CONSULTAR, (tabla, capa, mes))
        registros = []
        for fila in cursor.fetchall():
            registros.append(_registro_a_diccionario(fila))
    finally:
        conexion.close()
    return json.dumps(registros, ensure_ascii=False)


def registrar_watermark(
    fuente: str,
    capa: str,
    tabla: str,
    mes: str,
    filas: int,
    inicio: datetime,
    reprocesar: bool,
    connection_name: str | None = None,
) -> None:
    """Inserta una fila en la tabla de control. Se llama solo cuando la ingesta terminó bien."""
    valores = (fuente, capa, tabla, mes, int(filas), _inicio_en_utc(inicio), bool(reprocesar))
    conexion = _conectar(connection_name)
    try:
        _ejecutar(conexion.cursor(), SQL_REGISTRAR, valores)
    finally:
        conexion.close()


def borrar_registros_de_prueba(tabla: str, connection_name: str | None = None) -> int:
    """Borra los registros de una tabla de demostración o de prueba. Devuelve cuántos borró.

    Solo acepta nombres que empiezan con 'demo' o 'prueba': así no se puede borrar por error el
    historial de una ingesta real.
    """
    if not tabla.startswith(PREFIJOS_DE_PRUEBA):
        raise ValueError(
            f"Solo se pueden borrar registros de tablas de prueba (nombres que empiezan con "
            f"{' o '.join(PREFIJOS_DE_PRUEBA)}), y se pidió {tabla!r}."
        )
    conexion = _conectar(connection_name)
    try:
        cursor = conexion.cursor()
        _ejecutar(cursor, SQL_BORRAR, (tabla,))
        borradas = cursor.rowcount
    finally:
        conexion.close()
    return int(borradas or 0)
