"""Creación de la SparkSession según el cómputo de la corrida.

- code_editor: Spark en esta máquina (local[2], 2 GB de driver) que lee y escribe en S3 (dev).
  El código usa rutas s3://; por debajo Spark las trata con S3A, que necesita dos jars. Los jars
  se bajan una vez con `make jars-s3a` a ~/.spark-jars y NO se piden con spark.jars.packages
  (en clase 30 equipos bajarían 280 MB a la misma hora).
- glue_small | glue_medium | glue_large: el GlueContext del job (si awsglue no está, una
  SparkSession genérica). El tamaño lo decide el job, no este archivo.
- snowpark_connect: Snowpark Connect for Spark; warehouse y database vienen de la conexión de
  Snowflake (connections.toml) o de SNOWFLAKE_DATABASE / SNOWFLAKE_SCHEMA / SNOWFLAKE_WAREHOUSE /
  SNOWFLAKE_ROLE / SNOWFLAKE_CONNECTION_NAME si están definidas. Se requiere database y schema.

Los jars de S3A se exigen SOLO cuando se va a tocar s3:// (toca_s3=True): una sesión sin S3 (las
pruebas, un cuaderno que solo lee archivos del disco) funciona sin ellos.

Variables: PIPELINE_JARS_DIR (por defecto ~/.spark-jars) y PIPELINE_S3A_CREDENCIALES=boto3
(respaldo: usa las credenciales de boto3 en lugar de la cadena por defecto de AWS).
"""

from __future__ import annotations

import logging
import os
import sys
from pathlib import Path

from pyspark.sql import SparkSession

COMPUTOS_DE_GLUE = ("glue_small", "glue_medium", "glue_large")
MOTORES = ("code_editor", *COMPUTOS_DE_GLUE, "snowpark_connect")

# Versiones exactas: pyspark 3.5.6 trae Hadoop 3.3.4, y hadoop-aws tiene que ser la misma.
JARS_S3A = ("hadoop-aws-3.3.4.jar", "aws-java-sdk-bundle-1.12.262.jar")
REGION_POR_DEFECTO = "us-east-2"

log = logging.getLogger(__name__)


def carpeta_de_jars() -> Path:
    """Dónde están los jars de S3A: PIPELINE_JARS_DIR o ~/.spark-jars."""
    return Path(os.environ.get("PIPELINE_JARS_DIR") or Path.home() / ".spark-jars")


def jars_de_s3a() -> list[str]:
    """Rutas de los jars de S3A que existen (si falta alguno, no está en la lista)."""
    carpeta = carpeta_de_jars()
    encontrados = []
    for nombre in JARS_S3A:
        jar = carpeta / nombre
        if jar.is_file():
            encontrados.append(str(jar))
    return encontrados


def get_spark(engine: str, toca_s3: bool = False) -> SparkSession:
    """SparkSession del cómputo pedido. toca_s3=True exige los jars de S3A (code_editor)."""
    if engine not in MOTORES:
        raise ValueError(f"Motor desconocido '{engine}'. Válidos: {', '.join(MOTORES)}")
    if engine == "code_editor":
        spark = _code_editor(toca_s3)
    elif engine == "snowpark_connect":
        spark = _snowpark_connect()
    else:
        spark = _glue()
    _configurar(spark)
    return spark


def _code_editor(toca_s3: bool) -> SparkSession:
    # Mismo Python en driver y workers (evita PYTHON_VERSION_MISMATCH con varios Python).
    os.environ.setdefault("PYSPARK_PYTHON", sys.executable)
    jars = jars_de_s3a()
    faltan = len(jars) < len(JARS_S3A)
    if faltan and toca_s3:
        raise RuntimeError(
            f"Faltan los jars de S3A en {carpeta_de_jars()}: sin ellos Spark no puede leer ni "
            "escribir en s3://. Corre `make jars-s3a` (se hace una sola vez) y vuelve a intentar."
        )
    if faltan:
        log.info("Sin jars de S3A: esta sesión no puede tocar s3:// (corre `make jars-s3a`).")

    constructor = (
        SparkSession.builder.master("local[2]")
        .appName("pipeline-taxi")
        .config("spark.driver.memory", "2g")
        .config("spark.driver.maxResultSize", "512m")
        .config("spark.sql.shuffle.partitions", "8")
        .config("spark.ui.enabled", "false")
    )
    if not faltan:
        region = os.environ.get("AWS_REGION") or REGION_POR_DEFECTO
        credenciales = "com.amazonaws.auth.DefaultAWSCredentialsProviderChain"
        if os.environ.get("PIPELINE_S3A_CREDENCIALES") == "boto3":
            credenciales = _credenciales_de_boto3(constructor)
        constructor = (
            constructor.config("spark.jars", ",".join(jars))
            # El código usa s3://; Hadoop lo atiende con la clase de S3A.
            .config("spark.hadoop.fs.s3.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
            .config("spark.hadoop.fs.s3a.aws.credentials.provider", credenciales)
            .config("spark.hadoop.fs.s3a.endpoint", f"s3.{region}.amazonaws.com")
            .config("spark.hadoop.fs.s3a.fast.upload", "true")
            .config("spark.hadoop.mapreduce.fileoutputcommitter.algorithm.version", "2")
        )
    return constructor.getOrCreate()


def _credenciales_de_boto3(constructor) -> str:
    """Respaldo: toma las credenciales que ve boto3 y se las entrega a S3A como claves fijas."""
    import boto3

    credenciales = boto3.Session().get_credentials()
    if credenciales is None:
        raise RuntimeError("PIPELINE_S3A_CREDENCIALES=boto3, pero boto3 no encuentra credenciales.")
    congeladas = credenciales.get_frozen_credentials()
    constructor.config("spark.hadoop.fs.s3a.access.key", congeladas.access_key)
    constructor.config("spark.hadoop.fs.s3a.secret.key", congeladas.secret_key)
    if congeladas.token:
        constructor.config("spark.hadoop.fs.s3a.session.token", congeladas.token)
        return "org.apache.hadoop.fs.s3a.TemporaryAWSCredentialsProvider"
    return "org.apache.hadoop.fs.s3a.SimpleAWSCredentialsProvider"


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
