"""Creación de la SparkSession según el motor elegido (--engine).

- local: SparkSession local[*] con 2 GB de driver.
- glue: GlueContext sobre el SparkContext del job (si awsglue no está, SparkSession genérica).
- snowpark_connect: Snowpark Connect for Spark; warehouse y database vienen de la conexión
  de Snowflake (connections.toml) o de SNOWFLAKE_DATABASE / SNOWFLAKE_SCHEMA / SNOWFLAKE_WAREHOUSE /
  SNOWFLAKE_ROLE / SNOWFLAKE_CONNECTION_NAME si están definidas. Se requiere database y schema.
"""

from __future__ import annotations

import logging
import os
import sys

from pyspark.sql import SparkSession

MOTORES = ("local", "glue", "snowpark_connect")
log = logging.getLogger(__name__)


def get_spark(engine: str) -> SparkSession:
    if engine not in MOTORES:
        raise ValueError(f"Motor desconocido '{engine}'. Válidos: {', '.join(MOTORES)}")
    if engine == "local":
        spark = _local()
    elif engine == "glue":
        spark = _glue()
    else:
        spark = _snowpark_connect()
    _configurar(spark)
    return spark


def _local() -> SparkSession:
    # Mismo Python en driver y workers (evita PYTHON_VERSION_MISMATCH con varios Python).
    os.environ.setdefault("PYSPARK_PYTHON", sys.executable)
    return (
        SparkSession.builder.master("local[*]")
        .appName("pipeline-taxi")
        .config("spark.driver.memory", "2g")
        .getOrCreate()
    )


def _glue() -> SparkSession:
    try:
        from awsglue.context import GlueContext
        from pyspark.context import SparkContext
    except ImportError:
        log.warning("awsglue no disponible: se usa una SparkSession genérica")
        return SparkSession.builder.getOrCreate()
    return GlueContext(SparkContext.getOrCreate()).spark_session


def _parametros_snowflake() -> dict[str, str]:
    """Parámetros de conexión opcionales desde el entorno (si no, connections.toml manda).

    SNOWFLAKE_CONNECTION_NAME (o SNOWFLAKE_DEFAULT_CONNECTION_NAME), SNOWFLAKE_DATABASE,
    SNOWFLAKE_SCHEMA, SNOWFLAKE_WAREHOUSE y SNOWFLAKE_ROLE. Útil porque Snowpark Connect
    necesita una base de datos y un schema en la sesión (para el stage de la sesión) y muchas
    conexiones de `snow` no los traen.
    """
    nombre = os.environ.get("SNOWFLAKE_CONNECTION_NAME") or os.environ.get(
        "SNOWFLAKE_DEFAULT_CONNECTION_NAME"
    )
    params = {"connection_name": nombre} if nombre else {}
    for clave in ("database", "schema", "warehouse", "role"):
        valor = os.environ.get(f"SNOWFLAKE_{clave.upper()}")
        if valor:
            params[clave] = valor
    return params


def _snowpark_connect() -> SparkSession:
    # Import perezoso: solo existe dentro del entorno de Snowflake.
    from snowflake import snowpark_connect

    params = _parametros_snowflake()
    spark = snowpark_connect.init_spark_session(connection_parameters=params or None)
    if spark is None:
        spark = SparkSession.builder.getOrCreate()
    return spark


def _configurar(spark: SparkSession) -> None:
    """Zona horaria UTC (las fechas TLC son hora local sin offset) y overwrite dinámico."""
    try:
        spark.conf.set("spark.sql.session.timeZone", "UTC")
        spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")
    except Exception as exc:  # algunos motores no permiten cambiar la configuración
        log.warning("No se pudo ajustar la configuración de Spark: %s", exc)
