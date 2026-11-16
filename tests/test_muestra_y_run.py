from __future__ import annotations

from argparse import Namespace

import pytest

from pipeline import gold, io, muestra, silver
from pipeline.bronze import COLUMNAS_METADATOS
from pipeline.muestra import aplicar_muestra, limite_efectivo
from pipeline.run import pasos_de

MES = "2024-01"


def test_limite_efectivo_prioriza_cli():
    cfg = {"muestra": {"max_rows": 1000}}
    assert limite_efectivo(cfg) == 1000
    assert limite_efectivo(cfg, 50) == 50
    assert limite_efectivo({"muestra": {"max_rows": None}}) is None
    assert limite_efectivo({}) is None


def test_aplicar_muestra_recorta(muestra_viajes):
    assert aplicar_muestra(muestra_viajes, {}, 10).count() == 10
    assert aplicar_muestra(muestra_viajes, {}).count() == 100


def test_pasos_por_entorno():
    assert pasos_de("all", "local") == ["silver", "gold"]
    assert pasos_de("all", "prod") == ["bronze", "silver", "gold"]
    assert pasos_de("muestra", "prod") == ["muestra"]
    with pytest.raises(SystemExit):
        pasos_de("bronze", "local")


def test_muestra_y_pipeline_local_de_punta_a_punta(spark, tmp_path, armar_bronze):
    bronze = tmp_path / "bronze"
    armar_bronze(bronze)
    destino = tmp_path / "muestra"
    cfg_nube = {
        "entorno": "dev",
        "rutas": {"bronze": str(bronze)},
        "muestra": {"objetivo_filas": 50, "destino": str(destino)},
    }
    muestra.main(spark, cfg_nube, Namespace(meses=[MES]))

    viajes_muestra = io.leer_viajes(spark, str(destino), [MES])
    n = viajes_muestra.count()
    assert 0 < n < 100  # ~50 de 100, aleatoria y reproducible
    assert io.lote_mas_reciente(str(destino), io.ZONAS)
    assert io.lote_mas_reciente(str(destino), io.CLIMA, MES)

    # la muestra conserva el lote de bronze y sus columnas de metadatos
    id_bronze = io.lote_mas_reciente(str(bronze), io.VIAJES, MES)
    assert io.lote_mas_reciente(str(destino), io.VIAJES, MES) == id_bronze
    assert set(COLUMNAS_METADATOS) <= set(viajes_muestra.columns)
    assert viajes_muestra.select("_id_lote").distinct().first()[0] == id_bronze

    # local: silver y gold leen la muestra con el mismo código que dev/prod
    cfg_local = {
        "entorno": "local",
        "rutas": {
            "bronze": str(destino),
            "silver": str(tmp_path / "silver"),
            "gold": str(tmp_path / "gold"),
        },
        "muestra": {"max_rows": None},
    }
    args = Namespace(meses=[MES], limite=None)
    silver.main(spark, cfg_local, args)
    gold.main(spark, cfg_local, args)
    gold_df = spark.read.parquet(str(tmp_path / "gold" / "daily_zone_metrics"))
    assert gold_df.agg({"viajes": "sum"}).first()[0] <= n
    assert set(gold_df.columns) >= {"fecha", "zona", "empresa", "viajes"}


def _cfg_local(tmp_path, bronze):
    return {
        "entorno": "local",
        "rutas": {
            "bronze": str(bronze),
            "silver": str(tmp_path / "silver"),
            "gold": str(tmp_path / "gold"),
        },
        "muestra": {"max_rows": None},
        "limites": {"max_mb_entrada": 500},
    }


def test_reproceso_con_limite_no_deja_dias_viejos(spark, tmp_path, armar_bronze):
    """Regresión: con overwrite dinámico, correr con --limite dejaba los días de la corrida
    anterior y gold contaba más viajes que los procesados."""
    bronze = tmp_path / "bronze"
    armar_bronze(bronze)
    cfg = _cfg_local(tmp_path, bronze)

    silver.main(spark, cfg, Namespace(meses=[MES], limite=None))
    gold.main(spark, cfg, Namespace(meses=[MES], limite=None))
    silver.main(spark, cfg, Namespace(meses=[MES], limite=5))
    gold.main(spark, cfg, Namespace(meses=[MES], limite=None))

    assert spark.read.parquet(str(tmp_path / "silver" / "fhvhv_trips")).count() <= 5
    viajes_gold = spark.read.parquet(str(tmp_path / "gold" / "daily_zone_metrics"))
    assert viajes_gold.agg({"viajes": "sum"}).first()[0] <= 5


def test_guardia_de_tamano_en_local(spark, tmp_path, armar_bronze):
    bronze = tmp_path / "bronze"
    armar_bronze(bronze)
    cfg = _cfg_local(tmp_path, bronze)
    cfg["limites"]["max_mb_entrada"] = 0.000001  # cualquier archivo lo supera
    with pytest.raises(silver.EntradaDemasiadoGrande, match="usa Glue"):
        silver.main(spark, cfg, Namespace(meses=[MES], limite=None))


def test_leer_fuente_aplica_el_limite_y_rechaza_fuentes_no_declaradas(
    spark, tmp_path, armar_bronze
):
    bronze = tmp_path / "bronze"
    armar_bronze(bronze)
    cfg = {"rutas": {"bronze": str(bronze)}, "muestra": {"max_rows": None}}
    assert io.leer_fuente(spark, cfg, "viajes", [MES], 7).count() == 7
    assert io.leer_fuente(spark, cfg, "zonas", [MES]).count() == 12
    with pytest.raises(ValueError, match="Declárala en io.LECTORES"):
        io.leer_fuente(spark, cfg, "citibike", [MES])


def test_muestra_local_de_la_version_anterior_no_es_vigente(tmp_path):
    # versión anterior: la muestra traía el CSV de zonas suelto, sin carpeta lote=
    zonas = tmp_path / "taxi_zones"
    zonas.mkdir()
    (zonas / "taxi_zone_lookup.csv").write_text("LocationID\n1\n")
    assert muestra.muestra_local_vigente(tmp_path) is False

    (zonas / "lote=20260115T143005Z_a3f9c1").mkdir()
    assert muestra.muestra_local_vigente(tmp_path) is True
    assert muestra.muestra_local_vigente(tmp_path / "no_existe") is False
