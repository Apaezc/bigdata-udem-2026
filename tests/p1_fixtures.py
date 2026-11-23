"""Fixtures de las pruebas del núcleo (P1): entorno limpio y un pipeline.yaml a la medida."""

from __future__ import annotations

import pytest

import pipeline.herramientas.rutas as rutas

BUCKET_DE_PRUEBA = "bigdata-lake-123456789012-us-east-2"

# Todo lo que cambia el comportamiento de entorno_actual, cargar_configuracion y ruta_lake.
VARIABLES = (
    "PIPELINE_ENTORNO",
    "PIPELINE_YAML",
    "PIPELINE_RAIZ_LAKE",
    "LAKE_BUCKET",
    "WATERMARK_SECRET",
    "PREFIX",
    "AWS_REGION",
    "AWS_DEFAULT_REGION",
)


@pytest.fixture
def entorno_limpio(monkeypatch):
    """Quita las variables del pipeline y devuelve la lista de llamadas a sts.

    cargar_configuracion deja puestas WATERMARK_SECRET y LAKE_BUCKET. Para que eso no se filtre a
    otras pruebas, cada variable se pone y se quita con monkeypatch: al terminar la prueba vuelve
    a lo que había antes.
    """
    for variable in VARIABLES:
        monkeypatch.setenv(variable, "x")
        monkeypatch.delenv(variable)

    llamadas_a_sts: list[str] = []

    def sts_falso() -> str:
        llamadas_a_sts.append("sts")
        return BUCKET_DE_PRUEBA

    monkeypatch.setattr(rutas, "_bucket_por_sts", sts_falso)
    return llamadas_a_sts


@pytest.fixture
def poner_yaml(tmp_path, monkeypatch):
    """Función que escribe un pipeline.yaml con el texto dado y lo deja en PIPELINE_YAML."""

    def _poner(texto: str):
        archivo = tmp_path / "pipeline.yaml"
        archivo.write_text(texto, encoding="utf-8")
        monkeypatch.setenv("PIPELINE_YAML", str(archivo))
        return archivo

    return _poner
