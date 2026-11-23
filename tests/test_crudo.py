"""Pruebas de herramientas/crudo.py: no baja lo que ya está, mueve lo del diseño anterior.

Todo sobre file:// con la fixture `raiz_lake`; la descarga se reemplaza por una función falsa,
así que no hay red.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from pipeline.herramientas import archivos, crudo
from pipeline.herramientas.rutas import ruta_del_crudo, ruta_lake

MES = "2024-01"
ENTORNO = "dev"


@pytest.fixture
def descargas(monkeypatch):
    """Cambia `descargar` por una función falsa que anota las URL y escribe un archivo."""
    pedidas = []

    def falsa(url, destino):
        pedidas.append(url)
        carpeta = archivos.a_ruta_local(destino)
        carpeta.parent.mkdir(parents=True, exist_ok=True)
        carpeta.write_text("contenido descargado", encoding="utf-8")

    monkeypatch.setattr(crudo, "descargar", falsa)
    return pedidas


def test_las_urls_llevan_el_mes():
    assert crudo.url_viajes(MES).endswith("fhvhv_tripdata_2024-01.parquet")
    assert crudo.url_zonas() == crudo.URL_ZONAS
    assert "start_date=2024-01-01" in crudo.url_clima(MES)
    assert "end_date=2024-01-31" in crudo.url_clima(MES)


def test_si_no_esta_en_ninguna_parte_se_descarga(raiz_lake, descargas):
    ruta = crudo.traer_crudo_viajes(ENTORNO, MES)

    assert ruta == ruta_del_crudo(ENTORNO, "fhvhv", MES)
    assert descargas == [crudo.url_viajes(MES)]
    assert archivos.existe(ruta)


def test_si_ya_esta_en_crudo_no_se_descarga(raiz_lake, descargas):
    destino = archivos.a_ruta_local(ruta_del_crudo(ENTORNO, "clima", MES))
    destino.parent.mkdir(parents=True, exist_ok=True)
    destino.write_text("ya estaba", encoding="utf-8")

    ruta = crudo.traer_crudo_clima(ENTORNO, MES)

    assert descargas == []
    assert archivos.a_ruta_local(ruta).read_text(encoding="utf-8") == "ya estaba"


def test_si_esta_en_la_ruta_anterior_se_mueve_sin_descargar(raiz_lake, descargas):
    destino = ruta_del_crudo(ENTORNO, "fhvhv", MES)
    nombre = destino.rstrip("/").rsplit("/", 1)[-1]
    anterior = archivos.a_ruta_local(
        archivos.unir(ruta_lake(ENTORNO, "bronze", "fhvhv", MES), nombre)
    )
    anterior.parent.mkdir(parents=True, exist_ok=True)
    anterior.write_text("del diseño anterior", encoding="utf-8")

    ruta = crudo.traer_crudo_viajes(ENTORNO, MES)

    assert descargas == []
    assert not Path(anterior).exists()
    assert archivos.a_ruta_local(ruta).read_text(encoding="utf-8") == "del diseño anterior"


def test_zonas_no_lleva_mes(raiz_lake, descargas):
    ruta = crudo.traer_crudo_taxi_zones(ENTORNO)

    assert ruta.endswith("_crudo/taxi_zones/taxi_zone_lookup.csv")
    assert descargas == [crudo.URL_ZONAS]


def test_mes_invalido_falla_antes_de_descargar(raiz_lake, descargas):
    with pytest.raises(ValueError):
        crudo.traer_crudo_viajes(ENTORNO, "2024-13")
    assert descargas == []


def test_el_modulo_no_importa_pyspark_al_cargarse():
    import subprocess
    import sys

    codigo = (
        "import sys; import pipeline.herramientas.crudo, pipeline.herramientas.capas; "
        "sys.exit(1 if 'pyspark' in sys.modules else 0)"
    )
    resultado = subprocess.run([sys.executable, "-c", codigo], check=False, env=_entorno_con_src())
    assert resultado.returncode == 0


def _entorno_con_src() -> dict:
    """El proceso hijo no hereda el sys.path de pytest: se le pasa src/ por PYTHONPATH."""
    import os
    from pathlib import Path

    src = str(Path(__file__).resolve().parents[1] / "src")
    entorno = dict(os.environ)
    entorno["PYTHONPATH"] = src + os.pathsep + entorno.get("PYTHONPATH", "")
    return entorno
