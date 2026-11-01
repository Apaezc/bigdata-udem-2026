from __future__ import annotations

import pytest

from pipeline.quality import QualityError, validar


def test_pasa_con_datos_validos(spark):
    df = spark.createDataFrame([(1, "A", 2.0), (2, "B", 50.0)], "id int, zona string, d double")
    total = validar(
        df,
        nombre="prueba",
        llaves=("zona",),
        rangos={"d": (0, 100)},
        clave_unica=("id",),
    )
    assert total == {"total": 2}


def test_falla_si_esta_vacio(spark):
    df = spark.createDataFrame([], "id int")
    with pytest.raises(QualityError, match=r"\[prueba\] el conjunto está vacío"):
        validar(df, nombre="prueba")


def test_falla_con_llave_nula(spark):
    df = spark.createDataFrame([(1, "A"), (2, None)], "id int, zona string")
    with pytest.raises(QualityError, match="la llave 'zona' tiene 1 nulos de 2 filas"):
        validar(df, nombre="prueba", llaves=("zona",))


def test_falla_con_valor_fuera_de_rango(spark):
    df = spark.createDataFrame([(1, -1.0), (2, 3.0)], "id int, distancia double")
    with pytest.raises(QualityError, match="'distancia' tiene 1 valores fuera de rango"):
        validar(df, nombre="prueba", rangos={"distancia": (0, None)})


def test_nulos_no_cuentan_como_fuera_de_rango(spark):
    df = spark.createDataFrame([(1, None), (2, 3.0)], "id int, distancia double")
    validar(df, nombre="prueba", rangos={"distancia": (0, 100)})


def test_falla_con_clave_duplicada(spark):
    df = spark.createDataFrame([(1, "A"), (1, "A"), (2, "B")], "fecha int, zona string")
    with pytest.raises(QualityError, match="no es única: 1 filas duplicadas"):
        validar(df, nombre="prueba", clave_unica=("fecha", "zona"))
