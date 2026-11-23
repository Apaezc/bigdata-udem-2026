"""Pruebas de herramientas/capas.py: crudo, bronze, silver y gold, todo sobre file:// (sin AWS).

Cada prueba arma sus propios DataFrames dentro de la prueba y usa la fixture `raiz_lake`, que
apunta el lake a una carpeta temporal con PIPELINE_RAIZ_LAKE=file://...
"""

from __future__ import annotations

import shutil
from pathlib import Path

import pytest

from pipeline.herramientas import archivos, capas
from pipeline.herramientas.rutas import ruta_del_crudo, ruta_lake

DATA = Path(__file__).resolve().parent / "data"
MES = "2024-01"
ENTORNO = "dev"


def df_de_prueba(spark, filas):
    return spark.createDataFrame(filas, "id int, valor string")


def poner_viajes_crudos(spark, tmp_path, filas):
    """Deja un Parquet en la ruta del crudo de viajes, como si ya se hubiera descargado."""
    carpeta = tmp_path / "parquet_tmp"
    df_de_prueba(spark, filas).coalesce(1).write.mode("overwrite").parquet(str(carpeta))
    archivo = next(carpeta.glob("part-*.parquet"))
    destino = archivos.a_ruta_local(ruta_del_crudo(ENTORNO, "fhvhv", MES))
    destino.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(archivo, destino)


# --- hash y metadatos -------------------------------------------------------------------------


def test_columnas_de_metadatos_son_las_de_hoy():
    assert capas.COLUMNAS_METADATOS == [
        "_fecha_ingesta",
        "_id_lote",
        "_hash_fila",
        "_fuente",
        "_archivo_origen",
    ]


def test_hash_fila_igual_para_filas_iguales_y_distinto_si_cambia_un_valor(spark):
    df = spark.createDataFrame(
        [(1, "a"), (1, "a"), (1, "b"), (2, None), (2, "")], "id int, valor string"
    )
    hashes = [f[0] for f in df.select(capas.hash_fila(["id", "valor"])).collect()]
    assert hashes[0] == hashes[1]
    assert hashes[0] != hashes[2]
    # un nulo no se confunde con un texto vacío
    assert hashes[3] != hashes[4]


# --- leer_crudo -------------------------------------------------------------------------------


def test_leer_crudo_con_limite_devuelve_las_mismas_filas_en_dos_llamadas(
    spark, raiz_lake, tmp_path
):
    filas = [(i, f"v{i}") for i in range(200)]
    poner_viajes_crudos(spark, tmp_path, filas)

    primera = capas.leer_crudo(spark, ENTORNO, "fhvhv", MES, limite=10).collect()
    segunda = capas.leer_crudo(spark, ENTORNO, "fhvhv", MES, limite=10).collect()

    assert len(primera) == 10
    assert primera == segunda


def test_leer_crudo_sin_limite_trae_todo(spark, raiz_lake, tmp_path):
    poner_viajes_crudos(spark, tmp_path, [(i, "x") for i in range(50)])
    assert capas.leer_crudo(spark, ENTORNO, "fhvhv", MES).count() == 50


def test_leer_crudo_zonas_deja_todo_como_texto(spark, raiz_lake):
    destino = archivos.a_ruta_local(ruta_del_crudo(ENTORNO, "taxi_zones"))
    destino.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(DATA / "taxi_zone_lookup_sample.csv", destino)

    df = capas.leer_crudo(spark, ENTORNO, "taxi_zones")

    assert df.count() > 0
    assert {tipo for _, tipo in df.dtypes} == {"string"}


def test_leer_crudo_clima_sale_en_una_fila_por_dia(spark, raiz_lake):
    destino = archivos.a_ruta_local(ruta_del_crudo(ENTORNO, "clima", MES))
    destino.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(DATA / "open_meteo_sample.json", destino)

    df = capas.leer_crudo(spark, ENTORNO, "clima", MES)

    assert df.columns == ["fecha", "lluvia_mm", "temperatura"]
    assert df.count() > 1


def test_leer_crudo_tabla_desconocida_falla(spark, raiz_lake):
    with pytest.raises(ValueError):
        capas.leer_crudo(spark, ENTORNO, "otra", MES)


# --- bronze -----------------------------------------------------------------------------------


def test_escribir_bronze_devuelve_filas_y_deja_el_marcador(spark, raiz_lake):
    df = df_de_prueba(spark, [(1, "a"), (2, "b"), (3, "c")])

    escritas = capas.escribir_bronze(df, ENTORNO, "fhvhv", MES, "20240101T000000Z_aaaaaa")

    assert escritas == 3
    carpeta = ruta_lake(ENTORNO, "bronze", "fhvhv", MES)
    marcador = archivos.unir(carpeta, "lote=20240101T000000Z_aaaaaa", archivos.MARCA_LOTE_COMPLETO)
    assert archivos.existe(marcador)


def test_leer_capa_bronze_todos_suma_los_lotes_completos_e_ignora_los_incompletos(spark, raiz_lake):
    capas.escribir_bronze(df_de_prueba(spark, [(1, "a"), (2, "b")]), ENTORNO, "fhvhv", MES, "L1_x")
    capas.escribir_bronze(df_de_prueba(spark, [(3, "c")]), ENTORNO, "fhvhv", MES, "L2_x")
    # un lote a medias: tiene Parquet pero NO tiene _LOTE_COMPLETO
    carpeta = ruta_lake(ENTORNO, "bronze", "fhvhv", MES)
    df_de_prueba(spark, [(9, "z"), (9, "z"), (9, "z")]).write.parquet(
        archivos.unir(carpeta, "lote=L3_x")
    )

    todos = capas.leer_capa(spark, ENTORNO, "bronze", "fhvhv", MES, lotes="todos")
    ultimo = capas.leer_capa(spark, ENTORNO, "bronze", "fhvhv", MES, lotes="ultimo")

    assert todos.count() == 3
    assert ultimo.count() == 1
    assert ultimo.collect()[0]["id"] == 3


def test_leer_capa_bronze_sin_lotes_completos_falla_con_mensaje_claro(spark, raiz_lake):
    with pytest.raises(archivos.LoteNoEncontrado):
        capas.leer_capa(spark, ENTORNO, "bronze", "fhvhv", MES)


def test_bronze_de_zonas_no_lleva_mes(spark, raiz_lake):
    df = spark.createDataFrame([("1", "EWR")], "LocationID string, Zone string")
    capas.escribir_bronze(df, ENTORNO, "taxi_zones", None, "L1_x")

    leido = capas.leer_capa(spark, ENTORNO, "bronze", "taxi_zones")

    assert leido.count() == 1
    assert "mes=" not in ruta_lake(ENTORNO, "bronze", "taxi_zones")


# --- silver y gold ----------------------------------------------------------------------------


def test_escribir_capa_reemplaza_el_mes_en_vez_de_sumar(spark, raiz_lake):
    capas.escribir_capa(
        df_de_prueba(spark, [(1, "a"), (2, "b"), (3, "c")]), ENTORNO, "silver", "fhvhv", MES
    )
    escritas = capas.escribir_capa(df_de_prueba(spark, [(7, "z")]), ENTORNO, "silver", "fhvhv", MES)

    assert escritas == 1
    assert capas.leer_capa(spark, ENTORNO, "silver", "fhvhv", MES).count() == 1


def test_escribir_capa_no_toca_otros_meses(spark, raiz_lake):
    capas.escribir_capa(df_de_prueba(spark, [(1, "a")]), ENTORNO, "gold", "t", "2024-01")
    capas.escribir_capa(df_de_prueba(spark, [(2, "b"), (3, "c")]), ENTORNO, "gold", "t", "2024-02")
    capas.escribir_capa(df_de_prueba(spark, [(9, "z")]), ENTORNO, "gold", "t", "2024-02")

    assert capas.leer_capa(spark, ENTORNO, "gold", "t", "2024-01").count() == 1
    assert capas.leer_capa(spark, ENTORNO, "gold", "t", "2024-02").count() == 1


def test_escribir_capa_rechaza_bronze(spark, raiz_lake):
    with pytest.raises(ValueError):
        capas.escribir_capa(df_de_prueba(spark, [(1, "a")]), ENTORNO, "bronze", "fhvhv", MES)


def test_mover_entre_capas_devuelve_leidas_y_escritas(spark, raiz_lake):
    capas.escribir_bronze(df_de_prueba(spark, [(1, "a"), (2, "b")]), ENTORNO, "fhvhv", MES, "L1_x")
    capas.escribir_bronze(df_de_prueba(spark, [(2, "b"), (3, "c")]), ENTORNO, "fhvhv", MES, "L2_x")

    def sin_repetidos(df):
        return df.dropDuplicates(["id", "valor"])

    leidas, escritas = capas.mover_entre_capas(
        spark, ENTORNO, MES, "fhvhv", "bronze", "silver", transformar=sin_repetidos
    )

    assert leidas == 4
    assert escritas == 3
    assert capas.leer_capa(spark, ENTORNO, "silver", "fhvhv", MES).count() == 3


def test_mover_entre_capas_sin_transformar_espeja(spark, raiz_lake):
    capas.escribir_bronze(df_de_prueba(spark, [(1, "a"), (2, "b")]), ENTORNO, "fhvhv", MES, "L1_x")

    assert capas.mover_entre_capas(spark, ENTORNO, MES, "fhvhv", "bronze", "silver") == (2, 2)


def test_mover_zonas_ignora_el_mes(spark, raiz_lake):
    df = spark.createDataFrame([("1", "EWR")], "LocationID string, Zone string")
    capas.escribir_bronze(df, ENTORNO, "taxi_zones", None, "L1_x")

    resultado = capas.mover_entre_capas(spark, ENTORNO, MES, "taxi_zones", "bronze", "silver")

    assert resultado == (1, 1)
    assert capas.leer_capa(spark, ENTORNO, "silver", "taxi_zones").count() == 1
