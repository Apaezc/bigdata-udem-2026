from __future__ import annotations

import shutil
from argparse import Namespace
from pathlib import Path

import pytest
from botocore.exceptions import ClientError

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


# --- sincronizar: de dónde se toma la muestra local (sin red: buckets simulados con carpetas) ---


class ClienteS3Falso:
    """Imita lo mínimo de boto3 (listar y descargar) leyendo carpetas locales como buckets."""

    def __init__(self, raiz, buckets_con_error=()):
        self.raiz = raiz
        self.buckets_con_error = buckets_con_error

    def get_paginator(self, nombre):
        return self

    def paginate(self, Bucket, Prefix):
        if Bucket in self.buckets_con_error:
            error = {"Error": {"Code": "AccessDenied", "Message": "sin permiso"}}
            raise ClientError(error, "ListObjectsV2")
        contenidos = []
        for archivo in sorted((self.raiz / Bucket).rglob("*")):
            if archivo.is_file():
                clave = archivo.relative_to(self.raiz / Bucket).as_posix()
                if clave.startswith(Prefix):
                    contenidos.append({"Key": clave})
        return [{"Contents": contenidos}]

    def download_file(self, bucket, clave, destino):
        shutil.copy(self.raiz / bucket / clave, destino)


def _armar_muestra_en(carpeta, formato_nuevo, id_lote):
    """Deja en `carpeta` una muestra mínima; con formato nuevo trae el marcador _LOTE_COMPLETO."""
    lote_zonas = carpeta / "taxi_zones" / f"lote={id_lote}"
    lote_viajes = carpeta / "fhvhv" / "mes=2024-01" / f"lote={id_lote}"
    for lote in (lote_zonas, lote_viajes):
        lote.mkdir(parents=True)
        (lote / "part-0.parquet").write_text("datos")
        if formato_nuevo:
            (lote / io.MARCA_LOTE_COMPLETO).write_text("ok")


@pytest.fixture
def entorno_sync(tmp_path, monkeypatch):
    """Dos buckets simulados (propio y público), una config local y un cliente falso."""
    raiz = tmp_path / "s3"
    cfg = {
        "rutas": {"bronze": str(tmp_path / "lake" / "muestra")},
        "muestra": {
            "sincronizar_desde": "muestra",
            "publica": {"bucket": "publico", "prefijo": "paquete/muestra", "region": "us-east-2"},
        },
    }
    monkeypatch.setenv("LAKE_BUCKET", "propio")
    clientes_pedidos = []

    def crear_cliente_falso(anonimo, region=None):
        clientes_pedidos.append("anonimo" if anonimo else "con credenciales")
        return ClienteS3Falso(raiz)

    monkeypatch.setattr(muestra, "crear_cliente_s3", crear_cliente_falso)
    return Namespace(
        raiz=raiz, cfg=cfg, local=Path(cfg["rutas"]["bronze"]), clientes=clientes_pedidos
    )


def test_sincronizar_no_hace_nada_si_la_muestra_local_es_vigente(entorno_sync):
    _armar_muestra_en(entorno_sync.local, formato_nuevo=True, id_lote="local")
    muestra.sincronizar(entorno_sync.cfg)
    assert entorno_sync.clientes == []  # ni siquiera se abrió un cliente de S3


def test_sincronizar_prefiere_el_bucket_propio_si_tiene_el_formato_nuevo(entorno_sync, caplog):
    _armar_muestra_en(entorno_sync.raiz / "propio" / "muestra", True, "propio")
    _armar_muestra_en(entorno_sync.raiz / "publico" / "paquete" / "muestra", True, "publico")
    with caplog.at_level("INFO"):
        muestra.sincronizar(entorno_sync.cfg)
    assert (entorno_sync.local / "taxi_zones" / "lote=propio" / io.MARCA_LOTE_COMPLETO).exists()
    assert not (entorno_sync.local / "taxi_zones" / "lote=publico").exists()
    assert "tu bucket" in caplog.text


def test_sincronizar_va_al_publico_si_el_propio_tiene_el_formato_anterior(entorno_sync, caplog):
    # el bucket propio tiene lotes, pero sin _LOTE_COMPLETO: es la versión anterior
    _armar_muestra_en(entorno_sync.raiz / "propio" / "muestra", False, "viejo")
    _armar_muestra_en(entorno_sync.raiz / "publico" / "paquete" / "muestra", True, "publico")
    # y en el disco hay una muestra de la versión anterior que debe reemplazarse
    zonas_viejas = entorno_sync.local / "taxi_zones"
    zonas_viejas.mkdir(parents=True)
    (zonas_viejas / "taxi_zone_lookup.csv").write_text("LocationID\n1\n")

    with caplog.at_level("INFO"):
        muestra.sincronizar(entorno_sync.cfg)

    assert not (zonas_viejas / "taxi_zone_lookup.csv").exists()
    assert (zonas_viejas / "lote=publico" / io.MARCA_LOTE_COMPLETO).exists()
    assert "el bucket público del curso" in caplog.text
    assert entorno_sync.clientes == ["con credenciales", "anonimo"]
    assert not entorno_sync.local.with_name("muestra.descarga").exists()


def test_sincronizar_va_al_publico_si_no_hay_lake_bucket_o_el_propio_falla(
    entorno_sync, monkeypatch
):
    _armar_muestra_en(entorno_sync.raiz / "publico" / "paquete" / "muestra", True, "publico")

    # sin LAKE_BUCKET: ni se intenta el bucket propio
    monkeypatch.delenv("LAKE_BUCKET")
    muestra.sincronizar(entorno_sync.cfg)
    assert entorno_sync.clientes == ["anonimo"]
    assert muestra.muestra_local_vigente(entorno_sync.local)

    # con LAKE_BUCKET pero sin permiso sobre ese bucket: se sigue con el público
    shutil.rmtree(entorno_sync.local)
    monkeypatch.setenv("LAKE_BUCKET", "propio")
    monkeypatch.setattr(
        muestra,
        "crear_cliente_s3",
        lambda anonimo, region=None: ClienteS3Falso(
            entorno_sync.raiz, buckets_con_error=() if anonimo else ("propio",)
        ),
    )
    muestra.sincronizar(entorno_sync.cfg)
    assert muestra.muestra_local_vigente(entorno_sync.local)


def test_sincronizar_falla_con_un_mensaje_claro_si_ningun_origen_sirve(entorno_sync):
    _armar_muestra_en(entorno_sync.raiz / "propio" / "muestra", False, "viejo")  # formato anterior
    (entorno_sync.raiz / "publico").mkdir()  # el público está vacío
    with pytest.raises(muestra.MuestraError, match="ni en tu bucket ni en el bucket público"):
        muestra.sincronizar(entorno_sync.cfg)
    assert not entorno_sync.local.exists()


def test_la_configuracion_local_define_el_bucket_publico_de_la_muestra():
    from pipeline.settings import cargar

    publica = cargar("local")["muestra"]["publica"]
    assert publica == {
        "bucket": "bigdata-udem-2026-publico",
        "prefijo": "paquete/muestra",
        "region": "us-east-2",
    }
