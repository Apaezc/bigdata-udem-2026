from __future__ import annotations

import shutil
from argparse import Namespace
from pathlib import Path

import pytest

from pipeline import gold, io, muestra, silver
from pipeline.muestra import aplicar_muestra, limite_efectivo
from pipeline.run import pasos_de

DATA = Path(__file__).resolve().parent / "data"
MES = "2024-01"


def _armar_bronze(spark, base: Path) -> None:
    """Bronze local con el mismo layout que S3 (a partir de las muestras de tests/data)."""
    viajes = (
        spark.read.option("header", True)
        .option("inferSchema", True)
        .csv(str(DATA / "fhvhv_tripdata_sample.csv"))
    )
    viajes.write.mode("overwrite").parquet(io.dir_viajes(str(base), MES))
    zonas = Path(io.ruta_zonas(str(base)))
    zonas.parent.mkdir(parents=True)
    shutil.copyfile(DATA / "taxi_zone_lookup_sample.csv", zonas)
    clima = Path(io.ruta_clima(str(base), MES))
    clima.parent.mkdir(parents=True)
    shutil.copyfile(DATA / "open_meteo_sample.json", clima)


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


def test_muestra_y_pipeline_local_de_punta_a_punta(spark, tmp_path):
    bronze = tmp_path / "bronze"
    _armar_bronze(spark, bronze)
    destino = tmp_path / "muestra"
    cfg_nube = {
        "entorno": "dev",
        "rutas": {"bronze": str(bronze)},
        "muestra": {"objetivo_filas": 50, "destino": str(destino)},
    }
    muestra.main(spark, cfg_nube, Namespace(meses=[MES]))

    n = spark.read.parquet(io.dir_viajes(str(destino), MES)).count()
    assert 0 < n < 100  # ~50 de 100, aleatoria y reproducible
    assert Path(io.ruta_zonas(str(destino))).exists()
    assert Path(io.ruta_clima(str(destino), MES)).exists()

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
