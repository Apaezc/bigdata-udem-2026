"""engine.get_spark: cómputos, alias de las clases 1 a 6 y los jars de S3A (solo al tocar s3://)."""

from __future__ import annotations

import pytest

from pipeline import engine
from pipeline.engine import JARS_S3A, _parametros_snowflake, get_spark, jars_de_s3a


def test_parametros_snowflake_vacios_sin_entorno(monkeypatch):
    for k in (
        "SNOWFLAKE_CONNECTION_NAME",
        "SNOWFLAKE_DEFAULT_CONNECTION_NAME",
        "SNOWFLAKE_DATABASE",
        "SNOWFLAKE_SCHEMA",
        "SNOWFLAKE_WAREHOUSE",
        "SNOWFLAKE_ROLE",
    ):
        monkeypatch.delenv(k, raising=False)
    assert _parametros_snowflake() == {}


def test_parametros_snowflake_desde_entorno(monkeypatch):
    monkeypatch.setenv("SNOWFLAKE_CONNECTION_NAME", "mi-conexion")
    monkeypatch.setenv("SNOWFLAKE_DATABASE", "BIGDATA")
    monkeypatch.setenv("SNOWFLAKE_SCHEMA", "GOLD")
    assert _parametros_snowflake() == {
        "connection_name": "mi-conexion",
        "database": "BIGDATA",
        "schema": "GOLD",
    }


def test_un_motor_desconocido_dice_cuales_hay():
    with pytest.raises(ValueError, match="code_editor"):
        get_spark("spark_local")


def test_los_jars_se_buscan_en_la_carpeta_pedida(tmp_path, monkeypatch):
    monkeypatch.setenv("PIPELINE_JARS_DIR", str(tmp_path))
    assert jars_de_s3a() == []
    (tmp_path / JARS_S3A[0]).write_bytes(b"x")
    assert jars_de_s3a() == [str(tmp_path / JARS_S3A[0])]
    (tmp_path / JARS_S3A[1]).write_bytes(b"x")
    assert len(jars_de_s3a()) == 2


def test_las_versiones_de_los_jars_son_las_de_hadoop_3_3_4():
    assert JARS_S3A == ("hadoop-aws-3.3.4.jar", "aws-java-sdk-bundle-1.12.262.jar")


def test_tocar_s3_sin_jars_dice_que_corra_make_jars_s3a(tmp_path, monkeypatch):
    monkeypatch.setenv("PIPELINE_JARS_DIR", str(tmp_path))
    with pytest.raises(RuntimeError, match="make jars-s3a"):
        get_spark("code_editor", toca_s3=True)


def test_sin_s3_no_se_exigen_los_jars(spark):
    """Una sesión que no toca s3:// funciona sin los jars."""
    sesion = get_spark("code_editor")
    assert sesion.range(3).count() == 3
    assert sesion.conf.get("spark.sql.session.timeZone") == "UTC"
    assert spark.conf.get("spark.sql.sources.partitionOverwriteMode") == "dynamic"


def test_los_jars_van_en_la_configuracion_solo_si_existen(tmp_path, monkeypatch):
    """Arma el constructor sin crear la sesión: lo que importa es qué configuración recibe."""
    configuraciones = {}

    class ConstructorFalso:
        def master(self, valor):
            return self

        def appName(self, valor):  # noqa: N802 - así se llama en pyspark
            return self

        def config(self, clave, valor):
            configuraciones[clave] = valor
            return self

        def getOrCreate(self):  # noqa: N802
            return "sesion"

    class SesionFalsa:
        builder = ConstructorFalso()

    monkeypatch.setattr(engine, "SparkSession", SesionFalsa)
    monkeypatch.setenv("PIPELINE_JARS_DIR", str(tmp_path))
    monkeypatch.delenv("PIPELINE_S3A_CREDENCIALES", raising=False)

    assert engine._code_editor(toca_s3=False) == "sesion"
    assert "spark.jars" not in configuraciones
    assert configuraciones["spark.driver.memory"] == "2g"

    for nombre in JARS_S3A:
        (tmp_path / nombre).write_bytes(b"x")
    configuraciones.clear()
    engine._code_editor(toca_s3=True)
    assert configuraciones["spark.jars"].count(".jar") == 2
    assert "jars.packages" not in "".join(configuraciones)
    assert configuraciones["spark.hadoop.fs.s3.impl"].endswith("S3AFileSystem")
    assert configuraciones["spark.hadoop.fs.s3a.aws.credentials.provider"].endswith(
        "DefaultAWSCredentialsProviderChain"
    )
