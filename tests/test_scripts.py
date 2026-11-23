"""Scripts de shell y Makefile (clase 7): sintaxis, make correr, targets retirados, deploy."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest

RAIZ = Path(__file__).resolve().parents[1]
SCRIPTS = sorted((RAIZ / "scripts").glob("*.sh")) + sorted((RAIZ / "airflow" / "vm").glob("*.sh"))

pytestmark = pytest.mark.skipif(shutil.which("bash") is None, reason="requiere bash")


def _correr(args, **entorno):
    env = {**os.environ, "CORRER_SOLO_MOSTRAR": "1", "LAKE_BUCKET": "bigdata-lake-test"}
    for clave in ("ENTORNO", "PIPELINE_ENTORNO", "PASO", "COMPUTO", "LIMITE", "MES", "REPROCESAR"):
        env.pop(clave, None)
    env.update(entorno)
    return subprocess.run(
        ["bash", str(RAIZ / "scripts" / "correr.sh"), *args],
        capture_output=True,
        text=True,
        env=env,
        cwd=RAIZ,
    )


@pytest.mark.parametrize("script", SCRIPTS, ids=lambda p: p.name)
def test_sintaxis_bash(script):
    assert subprocess.run(["bash", "-n", str(script)]).returncode == 0


def test_correr_pasa_las_perillas():
    r = _correr(
        [],
        PASO="silver",
        LIMITE="100000",
        COMPUTO="glue_small",
        REPROCESAR="true",
        MES="2024-01",
    )
    assert r.returncode == 0, r.stderr
    salida = r.stdout
    assert "PIPELINE_ENTORNO=dev" in salida
    assert "--paso silver" in salida
    assert "--computo glue_small" in salida
    assert "--limite 100000" in salida
    assert "--mes 2024-01" in salida
    assert "--reprocesar true" in salida
    assert "WATERMARK_SECRET=bigdata/snowflake" in salida


def test_correr_sin_argumentos_deja_que_mande_pipeline_yaml():
    r = _correr([])
    assert r.returncode == 0, r.stderr
    assert "--paso" not in r.stdout and "--limite" not in r.stdout


def test_correr_ignora_entorno_prod():
    r = _correr([], ENTORNO="prod")
    assert r.returncode == 0
    assert "PIPELINE_ENTORNO=dev" in r.stdout
    assert "siempre es dev" in r.stderr


@pytest.mark.parametrize(
    "perilla",
    [
        {"PASO": "todo"},
        {"COMPUTO": "spark_local"},
        {"LIMITE": "12345"},
        {"MES": "2024-13"},
        {"REPROCESAR": "si"},
        {"LIMITE": "todos", "COMPUTO": "code_editor"},
    ],
)
def test_correr_rechaza_valores_malos(perilla):
    r = _correr([], **perilla)
    assert r.returncode == 1
    assert "ERROR" in r.stderr


def test_deploy_no_sube_codigo_de_prod_sin_confirmar():
    texto = (RAIZ / "scripts" / "deploy.sh").read_text()
    assert 'CONFIRMAR_PROD:-}" != "si"' in texto
    # pipeline.zip, dags/ y code/airflow/ solo aparecen después de la guardia
    guardia = texto.index('CONFIRMAR_PROD:-}" != "si"')
    for subida in (
        "aws s3 cp build/pipeline.zip",
        "aws s3 sync airflow/dags",
        "aws s3 sync airflow/framework",
    ):
        assert texto.index(subida) > guardia


@pytest.mark.skipif(shutil.which("make") is None, reason="requiere make")
def test_make_help_muestra_lo_nuevo_y_oculta_lo_del_instructor():
    r = subprocess.run(["make", "help"], capture_output=True, text=True, cwd=RAIZ)
    for visible in ("correr", "jars-s3a", "migrar-clase07", "actualizar-vm"):
        assert visible in r.stdout
    for oculto in (
        "publicar-bootstrap",
        "retirar-bootstrap",
        "limpieza-total",
    ):
        assert oculto not in r.stdout
