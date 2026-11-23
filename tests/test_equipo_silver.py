"""Pruebas de la función del equipo en silver: deduplicar.

Son las mismas en `make test` y en `probar_mis_funciones(...)` del cuaderno. No dependen de que
hayas escrito agregar_metadatos: el `_hash_fila` de estas pruebas lo calcula `hash_fila`, la
función de la casa. Mientras deduplicar traiga la marca `# PENDIENTE(equipo)`, sus pruebas salen
omitidas con «PENDIENTE: ...» (usa `pytest -rs`).
"""

from __future__ import annotations

from pyspark.sql import functions as F

from hueco import saltar_si_pendiente
from pipeline import silver
from pipeline.herramientas.capas import hash_fila

pytest_plugins = ["p1_fixtures", "p4_fixtures"]

ESQUEMA = "letra string, numero int"


def _lote(spark_equipo, filas, id_lote):
    """Filas con su _hash_fila (calculado sobre las originales) y el lote del que vienen."""
    df = spark_equipo.createDataFrame(filas, ESQUEMA)
    return df.withColumn("_hash_fila", hash_fila(["letra", "numero"])).withColumn(
        "_id_lote", F.lit(id_lote)
    )


def _deduplicar(df):
    saltar_si_pendiente(silver.deduplicar, "deduplicar todavía devuelve la tabla tal cual")
    return silver.deduplicar(df)


def test_deduplicar_deja_una_fila_por_hash(spark_equipo):
    filas = [("a", 1), ("a", 1), ("a", 1), ("b", 2), ("b", 2)]
    resultado = _deduplicar(_lote(spark_equipo, filas, "lote1"))

    hashes = [f["_hash_fila"] for f in resultado.select("_hash_fila").collect()]
    assert len(hashes) == 2
    assert len(set(hashes)) == 2


def test_deduplicar_no_cambia_lo_que_no_tiene_repetidos(spark_equipo):
    entrada = _lote(spark_equipo, [("a", 1), ("b", 2), ("c", 3)], "lote1")
    resultado = _deduplicar(entrada)

    assert resultado.columns == entrada.columns
    assert {tuple(f) for f in resultado.collect()} == {tuple(f) for f in entrada.collect()}


def test_dos_lotes_del_mismo_mes_dan_las_filas_de_uno(spark_equipo):
    filas = [("a", 1), ("b", 2), ("c", 3), ("d", None)]
    dos_lotes = _lote(spark_equipo, filas, "lote1").unionByName(_lote(spark_equipo, filas, "lote2"))
    assert dos_lotes.count() == 8

    resultado = _deduplicar(dos_lotes)

    assert resultado.count() == 4
    assert {(f["letra"], f["numero"]) for f in resultado.collect()} == set(filas)


def test_deduplicar_conserva_todas_las_columnas(spark_equipo):
    resultado = _deduplicar(_lote(spark_equipo, [("a", 1), ("a", 1)], "lote1"))
    assert resultado.columns == ["letra", "numero", "_hash_fila", "_id_lote"]
