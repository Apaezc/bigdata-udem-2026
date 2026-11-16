"""Pruebas de la ingesta con metadatos de bronze.

Las primeras no usan Spark (rutas, id de lote, lote más reciente, migración del crudo); las
últimas sí (columnas de metadatos, hash, ingesta completa y compatibilidad con silver).
"""

from __future__ import annotations

import hashlib
import re
import shutil
from argparse import Namespace
from datetime import UTC, datetime
from pathlib import Path

import pytest
from pyspark.sql import functions as F

from pipeline import bronze, io, silver
from pipeline.bronze import (
    COLUMNAS_METADATOS,
    MARCADOR_NULO,
    SEPARADOR_HASH,
    agregar_metadatos,
    asegurar_crudo,
    nuevo_id_lote,
)

MES = "2024-01"
LOTE_VIEJO = "20260101T100000Z_aaaaaa"
LOTE_NUEVO = "20260115T143005Z_bbbbbb"
LOTE_NUEVISIMO = "20260301T090000Z_cccccc"
LOTE_FUTURO = "29990101T000000Z_ffffff"  # siempre más nuevo que el lote que arma armar_bronze


# --- rutas (sin Spark) ------------------------------------------------------------------------


def test_rutas_del_crudo():
    base = "s3://lago/bronze"
    assert (
        io.ruta_crudo(base, io.VIAJES, io.nombre_viajes(MES), MES)
        == "s3://lago/bronze/_crudo/fhvhv/mes=2024-01/fhvhv_tripdata_2024-01.parquet"
    )
    assert (
        io.ruta_crudo(base, io.CLIMA, io.nombre_clima(MES), MES)
        == "s3://lago/bronze/_crudo/clima/mes=2024-01/open_meteo_2024-01.json"
    )
    # las zonas no tienen mes
    assert (
        io.ruta_crudo(base, io.ZONAS, io.NOMBRE_ZONAS)
        == "s3://lago/bronze/_crudo/taxi_zones/taxi_zone_lookup.csv"
    )


def test_rutas_de_los_lotes():
    base = "s3://lago/bronze/"
    assert (
        io.dir_lote(base, io.VIAJES, LOTE_NUEVO, MES)
        == "s3://lago/bronze/fhvhv/mes=2024-01/lote=20260115T143005Z_bbbbbb"
    )
    assert io.dir_lote(base, io.ZONAS, LOTE_NUEVO) == (
        "s3://lago/bronze/taxi_zones/lote=20260115T143005Z_bbbbbb"
    )


def test_ruta_anterior_es_la_de_la_version_previa():
    base = "s3://lago/bronze"
    assert (
        io.ruta_anterior(base, io.VIAJES, io.nombre_viajes(MES), MES)
        == "s3://lago/bronze/fhvhv/mes=2024-01/fhvhv_tripdata_2024-01.parquet"
    )
    assert (
        io.ruta_anterior(base, io.ZONAS, io.NOMBRE_ZONAS)
        == "s3://lago/bronze/taxi_zones/taxi_zone_lookup.csv"
    )


# --- id del lote (sin Spark) ------------------------------------------------------------------


def test_id_lote_tiene_el_formato_pedido():
    ahora = datetime(2026, 1, 15, 14, 30, 5, tzinfo=UTC)
    id_lote = nuevo_id_lote(ahora)
    assert re.fullmatch(r"20260115T143005Z_[0-9a-f]{6}", id_lote)


def test_ids_de_lote_se_ordenan_por_fecha():
    antes = nuevo_id_lote(datetime(2026, 1, 15, 14, 30, 5, tzinfo=UTC))
    despues = nuevo_id_lote(datetime(2026, 1, 15, 14, 30, 6, tzinfo=UTC))
    mucho_despues = nuevo_id_lote(datetime(2027, 1, 1, 0, 0, 0, tzinfo=UTC))
    assert sorted([mucho_despues, despues, antes]) == [antes, despues, mucho_despues]


# --- lote más reciente (sin Spark) ------------------------------------------------------------


def _crear_lote(base: Path, fuente: str, id_lote: str, mes: str | None, completo: bool = True):
    carpeta = Path(io.dir_lote(str(base), fuente, id_lote, mes))
    carpeta.mkdir(parents=True)
    (carpeta / "part-0.parquet").write_text("datos")
    if completo:
        (carpeta / io.MARCA_LOTE_COMPLETO).write_text("")


def test_lote_mas_reciente_elige_el_mayor(tmp_path):
    _crear_lote(tmp_path, io.VIAJES, LOTE_NUEVO, MES)
    _crear_lote(tmp_path, io.VIAJES, LOTE_VIEJO, MES)
    _crear_lote(tmp_path, io.VIAJES, LOTE_NUEVISIMO, MES)
    assert io.lote_mas_reciente(str(tmp_path), io.VIAJES, MES) == LOTE_NUEVISIMO


def test_lote_mas_reciente_es_por_mes(tmp_path):
    _crear_lote(tmp_path, io.VIAJES, LOTE_VIEJO, "2024-01")
    _crear_lote(tmp_path, io.VIAJES, LOTE_NUEVO, "2024-02")
    assert io.lote_mas_reciente(str(tmp_path), io.VIAJES, "2024-01") == LOTE_VIEJO
    assert io.lote_mas_reciente(str(tmp_path), io.VIAJES, "2024-02") == LOTE_NUEVO


def test_lote_mas_reciente_de_zonas_no_usa_mes(tmp_path):
    _crear_lote(tmp_path, io.ZONAS, LOTE_VIEJO, None)
    _crear_lote(tmp_path, io.ZONAS, LOTE_NUEVO, None)
    assert io.lote_mas_reciente(str(tmp_path), io.ZONAS) == LOTE_NUEVO


def test_lote_a_medias_se_ignora(tmp_path):
    # la ingesta del lote más nuevo falló al escribir: no tiene el marcador _LOTE_COMPLETO
    _crear_lote(tmp_path, io.VIAJES, LOTE_VIEJO, MES)
    _crear_lote(tmp_path, io.VIAJES, LOTE_NUEVO, MES, completo=False)
    assert io.lote_mas_reciente(str(tmp_path), io.VIAJES, MES) == LOTE_VIEJO


def test_el_marcador_propio_manda_aunque_no_haya_success(tmp_path):
    # Glue no escribe _SUCCESS en S3: lo que cuenta es nuestro marcador
    _crear_lote(tmp_path, io.VIAJES, LOTE_VIEJO, MES)
    carpeta = Path(io.dir_lote(str(tmp_path), io.VIAJES, LOTE_NUEVO, MES))
    carpeta.mkdir(parents=True)
    (carpeta / "_SUCCESS").write_text("")  # tiene _SUCCESS pero no el marcador: a medias
    assert io.lote_mas_reciente(str(tmp_path), io.VIAJES, MES) == LOTE_VIEJO


def test_marcar_lote_completo_publica_el_marcador(tmp_path):
    carpeta = tmp_path / "lote"
    io.marcar_lote_completo(str(carpeta))
    assert (carpeta / io.MARCA_LOTE_COMPLETO).is_file()


def test_sin_lotes_el_error_dice_que_hacer(tmp_path):
    with pytest.raises(io.LoteNoEncontrado, match="--step bronze"):
        io.lote_mas_reciente(str(tmp_path), io.VIAJES, MES)
    # un archivo suelto de la versión anterior no cuenta como lote
    anterior = Path(io.ruta_anterior(str(tmp_path), io.VIAJES, io.nombre_viajes(MES), MES))
    anterior.parent.mkdir(parents=True)
    anterior.write_text("viejo")
    with pytest.raises(io.LoteNoEncontrado):
        io.lote_mas_reciente(str(tmp_path), io.VIAJES, MES)


# --- crudo y migración (sin Spark) ------------------------------------------------------------


@pytest.fixture
def descargas(monkeypatch):
    """Reemplaza la descarga real: escribe un archivo de mentira y anota cada llamada."""
    llamadas = []

    def descarga_falsa(url, destino):
        llamadas.append(url)
        Path(destino).parent.mkdir(parents=True, exist_ok=True)
        Path(destino).write_text("descargado")

    monkeypatch.setattr(bronze, "descargar", descarga_falsa)
    return llamadas


def test_descarga_si_no_hay_nada(tmp_path, descargas):
    destino = str(tmp_path / "_crudo" / "zonas.csv")
    anterior = str(tmp_path / "zonas.csv")
    asegurar_crudo("http://fuente/zonas.csv", destino, anterior)
    assert descargas == ["http://fuente/zonas.csv"]
    assert Path(destino).read_text() == "descargado"


def test_ingestar_dos_veces_el_mismo_crudo_no_descarga_de_nuevo(tmp_path, descargas):
    destino = str(tmp_path / "_crudo" / "zonas.csv")
    anterior = str(tmp_path / "zonas.csv")
    asegurar_crudo("http://fuente/zonas.csv", destino, anterior)
    asegurar_crudo("http://fuente/zonas.csv", destino, anterior)
    assert len(descargas) == 1


def test_migra_el_archivo_de_la_ruta_anterior_sin_descargar(tmp_path, descargas):
    anterior = tmp_path / "fhvhv" / "mes=2024-01" / "fhvhv_tripdata_2024-01.parquet"
    anterior.parent.mkdir(parents=True)
    anterior.write_text("contenido original")
    destino = tmp_path / "_crudo" / "fhvhv" / "mes=2024-01" / "fhvhv_tripdata_2024-01.parquet"

    asegurar_crudo("http://fuente/viajes", str(destino), str(anterior))

    assert descargas == []
    assert destino.read_text() == "contenido original"  # mismo contenido, sin tocar
    assert not anterior.exists()  # se movió: no queda duplicado


def test_si_ya_hay_crudo_no_se_toca_el_archivo_anterior(tmp_path, descargas):
    anterior = tmp_path / "zonas.csv"
    anterior.write_text("viejo")
    destino = tmp_path / "_crudo" / "zonas.csv"
    destino.parent.mkdir(parents=True)
    destino.write_text("crudo")

    asegurar_crudo("http://fuente/zonas.csv", str(destino), str(anterior))

    assert descargas == []
    assert destino.read_text() == "crudo"
    assert anterior.exists()


# --- hash y metadatos (con Spark) -------------------------------------------------------------

ESQUEMA = "texto string, numero int, nulo string"
AHORA = datetime(2026, 1, 15, 14, 30, 5, tzinfo=UTC)


def _con_metadatos(spark, filas, esquema=ESQUEMA):
    df = spark.createDataFrame(filas, esquema)
    return agregar_metadatos(df, "http://fuente/x", "x.parquet", LOTE_NUEVO, AHORA)


def _hashes(spark, filas, esquema=ESQUEMA):
    return [r["_hash_fila"] for r in _con_metadatos(spark, filas, esquema).collect()]


def _hash_de_referencia(valores: list) -> str:
    """El mismo cálculo escrito en Python plano, para comparar con el de Spark."""
    textos = []
    for valor in valores:
        if valor is None:
            textos.append(MARCADOR_NULO)
        else:
            textos.append(str(valor))
    fila = SEPARADOR_HASH.join(textos)
    return hashlib.sha256(fila.encode("utf-8")).hexdigest()


def test_el_hash_es_sha256_de_la_fila_unida_con_marcador_de_nulo(spark):
    hashes = _hashes(spark, [("a", 1, None)])
    assert hashes == [_hash_de_referencia(["a", 1, None])]
    assert len(hashes[0]) == 64


def test_misma_fila_da_el_mismo_hash(spark):
    primero = _hashes(spark, [("a", 1, "x"), ("a", 1, "x")])
    segundo = _hashes(spark, [("a", 1, "x")])
    assert primero[0] == primero[1] == segundo[0]


def test_fila_distinta_da_hash_distinto(spark):
    h_base, h_texto, h_numero, h_nulo = _hashes(
        spark, [("a", 1, "x"), ("b", 1, "x"), ("a", 2, "x"), ("a", 1, None)]
    )
    assert len({h_base, h_texto, h_numero, h_nulo}) == 4


def test_el_orden_de_las_columnas_cuenta(spark):
    h_ab, h_ba = _hashes(spark, [("a", "b", "c"), ("b", "a", "c")], "x string, y string, z string")
    assert h_ab != h_ba


def test_nulo_no_se_confunde_con_texto_vacio_ni_con_la_palabra_null(spark):
    h_nulo, h_vacio, h_palabra = _hashes(spark, [("a", 1, None), ("a", 1, ""), ("a", 1, "null")])
    assert len({h_nulo, h_vacio, h_palabra}) == 3


def test_el_hash_no_cambia_entre_ejecuciones(spark):
    # mismo contenido, otro lote y otra fecha de ingesta: el hash solo depende de la fila
    df = spark.createDataFrame([("a", 1, None)], ESQUEMA)
    otro_momento = datetime(2027, 6, 1, 8, 0, 0, tzinfo=UTC)
    uno = agregar_metadatos(df, "u", "f", LOTE_VIEJO, AHORA).first()
    dos = agregar_metadatos(df, "u", "f", LOTE_NUEVO, otro_momento).first()
    assert uno["_hash_fila"] == dos["_hash_fila"]


def test_agrega_las_cinco_columnas_y_no_toca_las_originales(spark):
    df = _con_metadatos(spark, [("a", 1, None), ("b", 2, "x")])
    assert df.columns == ["texto", "numero", "nulo", *COLUMNAS_METADATOS]
    assert dict(df.dtypes) == {
        "texto": "string",
        "numero": "int",
        "nulo": "string",
        "_fecha_ingesta": "timestamp",
        "_id_lote": "string",
        "_hash_fila": "string",
        "_fuente": "string",
        "_archivo_origen": "string",
    }
    originales = df.select("texto", "numero", "nulo").orderBy("texto").collect()
    assert [tuple(r) for r in originales] == [("a", 1, None), ("b", 2, "x")]


def test_valores_de_los_metadatos(spark):
    df = _con_metadatos(spark, [("a", 1, None), ("b", 2, "x")])
    meta = df.select(
        F.date_format("_fecha_ingesta", "yyyy-MM-dd HH:mm:ss").alias("fecha"),
        "_id_lote",
        "_fuente",
        "_archivo_origen",
    ).distinct()
    filas = meta.collect()
    assert len(filas) == 1  # el mismo valor en todas las filas del lote
    assert tuple(filas[0]) == ("2026-01-15 14:30:05", LOTE_NUEVO, "http://fuente/x", "x.parquet")


def test_clima_a_filas_una_fila_por_dia(muestra_clima_raw, muestra_clima):
    assert muestra_clima.columns == ["fecha", "lluvia_mm", "temperatura"]
    assert muestra_clima.count() == 31
    primera = muestra_clima.orderBy("fecha").first()
    crudo = muestra_clima_raw.first()
    assert primera["fecha"] == crudo["daily"]["time"][0]
    assert primera["lluvia_mm"] == crudo["daily"]["precipitation_sum"][0]
    assert primera["temperatura"] == crudo["daily"]["temperature_2m_mean"][0]


# --- ingesta completa (con Spark) -------------------------------------------------------------


def test_main_escribe_un_lote_por_fuente_con_el_mismo_id(spark, tmp_path, armar_bronze):
    base = tmp_path / "bronze"
    armar_bronze(base)

    id_viajes = io.lote_mas_reciente(str(base), io.VIAJES, MES)
    id_clima = io.lote_mas_reciente(str(base), io.CLIMA, MES)
    id_zonas = io.lote_mas_reciente(str(base), io.ZONAS)
    assert id_viajes == id_clima == id_zonas
    for fuente, mes in ((io.VIAJES, MES), (io.CLIMA, MES), (io.ZONAS, None)):
        lote = Path(io.dir_lote(str(base), fuente, id_viajes, mes))
        assert (lote / io.MARCA_LOTE_COMPLETO).is_file()
    assert re.fullmatch(r"\d{8}T\d{6}Z_[0-9a-f]{6}", id_viajes)

    viajes = io.leer_viajes(spark, str(base), [MES])
    assert viajes.count() == 100
    assert viajes.columns[-5:] == COLUMNAS_METADATOS
    assert viajes.select("_id_lote").distinct().first()[0] == id_viajes
    esperado = "fhvhv_tripdata_2024-01.parquet"
    assert viajes.select("_archivo_origen").distinct().first()[0] == esperado
    assert viajes.select("_fuente").distinct().first()[0].endswith(esperado)
    assert viajes.where(F.col("_hash_fila").isNull()).count() == 0

    clima = io.leer_clima(spark, str(base), [MES])
    assert clima.count() == 31
    zonas = io.leer_zonas(spark, str(base))
    assert zonas.count() == 12
    assert zonas.columns[:4] == ["LocationID", "Borough", "Zone", "service_zone"]


def test_el_crudo_queda_intacto_en_la_ruta_pedida(spark, tmp_path, armar_bronze):
    base = tmp_path / "bronze"
    armar_bronze(base)
    esperada = base / "_crudo" / "fhvhv" / "mes=2024-01" / "fhvhv_tripdata_2024-01.parquet"
    assert esperada.is_file()
    assert (base / "_crudo" / "taxi_zones" / "taxi_zone_lookup.csv").is_file()
    assert (base / "_crudo" / "clima" / "mes=2024-01" / "open_meteo_2024-01.json").is_file()


def _segundo_lote(monkeypatch, id_lote: str) -> None:
    """Hace que la próxima ingesta use este id (dos ingestas del mismo segundo no se ordenarían)."""

    def id_fijo(ahora):
        return id_lote

    monkeypatch.setattr(bronze, "nuevo_id_lote", id_fijo)


def test_reingestar_crea_un_lote_nuevo_y_no_descarga(spark, tmp_path, armar_bronze, monkeypatch):
    base = tmp_path / "bronze"
    armar_bronze(base)
    primero = io.lote_mas_reciente(str(base), io.VIAJES, MES)

    # segunda ingesta: el crudo ya está, así que descargar (que falla si se llama) no se usa
    _segundo_lote(monkeypatch, LOTE_FUTURO)
    bronze.main(spark, {"rutas": {"bronze": str(base)}}, Namespace(meses=[MES]))

    assert io.lote_mas_reciente(str(base), io.VIAJES, MES) == LOTE_FUTURO
    lotes = io.listar_subcarpetas(io.dir_fuente(str(base), io.VIAJES, MES))
    assert sorted(lotes) == sorted([f"lote={primero}", f"lote={LOTE_FUTURO}"])


def _dejar_como_la_version_anterior(base: Path) -> None:
    """Deja bronze como lo dejaba la versión anterior: archivos sueltos, sin _crudo ni lotes."""
    archivos = [
        (io.VIAJES, MES, io.nombre_viajes(MES)),
        (io.CLIMA, MES, io.nombre_clima(MES)),
        (io.ZONAS, None, io.NOMBRE_ZONAS),
    ]
    for fuente, mes, nombre in archivos:
        crudo = Path(io.ruta_crudo(str(base), fuente, nombre, mes))
        anterior = Path(io.ruta_anterior(str(base), fuente, nombre, mes))
        anterior.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(crudo, anterior)
        for nombre_lote in io.listar_subcarpetas(io.dir_fuente(str(base), fuente, mes)):
            shutil.rmtree(Path(io.dir_fuente(str(base), fuente, mes)) / nombre_lote)
    shutil.rmtree(base / "_crudo")


def test_ingesta_migra_los_archivos_de_la_ruta_anterior(spark, tmp_path, armar_bronze):
    base = tmp_path / "bronze"
    armar_bronze(base)
    _dejar_como_la_version_anterior(base)
    assert not (base / "_crudo").exists()

    # descargar falla si se llama (lo deja armar_bronze): la migración no usa la red
    bronze.main(spark, {"rutas": {"bronze": str(base)}}, Namespace(meses=[MES]))

    assert (base / "_crudo/fhvhv/mes=2024-01/fhvhv_tripdata_2024-01.parquet").is_file()
    assert (base / "_crudo/clima/mes=2024-01/open_meteo_2024-01.json").is_file()
    assert (base / "_crudo/taxi_zones/taxi_zone_lookup.csv").is_file()
    assert not (base / "fhvhv/mes=2024-01/fhvhv_tripdata_2024-01.parquet").exists()
    assert not (base / "taxi_zones/taxi_zone_lookup.csv").exists()
    assert io.leer_viajes(spark, str(base), [MES]).count() == 100


def test_mismo_crudo_da_los_mismos_hashes_en_dos_lotes(spark, tmp_path, armar_bronze, monkeypatch):
    base = tmp_path / "bronze"
    armar_bronze(base)
    primero = io.lote_mas_reciente(str(base), io.VIAJES, MES)
    _segundo_lote(monkeypatch, LOTE_FUTURO)
    bronze.main(spark, {"rutas": {"bronze": str(base)}}, Namespace(meses=[MES]))

    carpeta = io.dir_fuente(str(base), io.VIAJES, MES)
    hashes_primero = spark.read.parquet(f"{carpeta}/lote={primero}").select("_hash_fila")
    hashes_segundo = spark.read.parquet(f"{carpeta}/lote={LOTE_FUTURO}").select("_hash_fila")
    assert hashes_primero.exceptAll(hashes_segundo).count() == 0
    assert hashes_segundo.exceptAll(hashes_primero).count() == 0


# --- silver sobre bronze (con Spark) ----------------------------------------------------------


def test_leer_viajes_usa_el_lote_mas_reciente(spark, tmp_path):
    base = tmp_path / "bronze"
    for id_lote, filas in ((LOTE_VIEJO, 3), (LOTE_NUEVO, 7), (LOTE_NUEVISIMO, 5)):
        df = spark.range(filas).withColumn("lote", F.lit(id_lote))
        io.escribir_lote(df, io.dir_lote(str(base), io.VIAJES, id_lote, MES))
    # un lote todavía más nuevo pero a medias no debe usarse
    _crear_lote(base, io.VIAJES, "20260401T000000Z_dddddd", MES, completo=False)

    leidos = io.leer_viajes(spark, str(base), [MES])
    assert leidos.count() == 5
    assert leidos.select("lote").distinct().first()[0] == LOTE_NUEVISIMO


def test_silver_da_el_mismo_resultado_que_leyendo_los_datos_originales(
    spark, tmp_path, armar_bronze, muestra_viajes, muestra_zonas, muestra_clima
):
    base = tmp_path / "bronze"
    armar_bronze(base)
    cfg = {
        "entorno": "local",
        "rutas": {
            "bronze": str(base),
            "silver": str(tmp_path / "silver"),
            "gold": str(tmp_path / "gold"),
        },
        "muestra": {"max_rows": None},
    }
    silver.main(spark, cfg, Namespace(meses=[MES], limite=None))
    desde_bronze = spark.read.parquet(str(tmp_path / "silver" / "fhvhv_trips"))

    # el mismo cálculo, directo sobre los archivos de tests/data (como antes de los metadatos)
    directo = silver.enriquecer(
        silver.limpiar_viajes(muestra_viajes, [MES]),
        muestra_zonas,
        silver.clima_diario(muestra_clima),
    )

    assert desde_bronze.count() == directo.count() == 90
    columnas = directo.columns
    assert desde_bronze.select(*columnas).exceptAll(directo).count() == 0
    assert directo.exceptAll(desde_bronze.select(*columnas)).count() == 0
    assert "_hash_fila" not in desde_bronze.columns  # los metadatos no pasan a silver


def test_silver_sin_bronze_explica_que_falta(spark, tmp_path):
    cfg = {
        "entorno": "local",
        "rutas": {"bronze": str(tmp_path / "vacio"), "silver": str(tmp_path / "s")},
        "muestra": {"max_rows": None},
    }
    with pytest.raises(io.LoteNoEncontrado, match="--step bronze"):
        silver.main(spark, cfg, Namespace(meses=[MES], limite=None))
