"""La caja de herramientas: cada archivo se puede importar sin pyspark y sin traer los pasos.

La VM de Airflow no tiene pyspark, y bronze, silver, gold y carga importan la caja (no al revés).
"""

from __future__ import annotations

import pkgutil
import subprocess
import sys
from pathlib import Path

import pytest

import pipeline.herramientas as herramientas

RAIZ_DEL_REPO = Path(__file__).resolve().parents[1]
ARCHIVOS = sorted(m.name for m in pkgutil.iter_modules(herramientas.__path__))


def _correr(codigo: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, "-c", codigo],
        capture_output=True,
        text=True,
        env={"PYTHONPATH": str(RAIZ_DEL_REPO / "src"), "PATH": ""},
        check=False,
    )


def test_el_init_de_la_caja_no_tiene_codigo():
    nombres = [n for n in vars(herramientas) if not n.startswith("__") and n not in ARCHIVOS]
    assert nombres == []


@pytest.mark.parametrize("archivo", ARCHIVOS)
def test_cada_archivo_importa_sin_pyspark_y_sin_los_pasos(archivo):
    """Importar el archivo no pide pyspark ni importa bronze, silver, gold ni carga."""
    codigo = (
        "import sys; sys.modules['pyspark'] = None\n"
        f"import pipeline.herramientas.{archivo}\n"
        "malos = [m for m in ('pipeline.bronze','pipeline.silver','pipeline.gold','pipeline.carga')"
        " if m in sys.modules]\n"
        "print(malos)"
    )
    resultado = _correr(codigo)
    assert resultado.returncode == 0, resultado.stderr
    assert resultado.stdout.strip() == "[]"


def test_el_motor_de_correr_importa_sin_pyspark():
    """pipeline.correr tampoco pide pyspark al cargarse (la VM de Airflow lo usa)."""
    resultado = _correr(
        "import sys; sys.modules['pyspark'] = None\nimport pipeline.correr\nprint('ok')"
    )
    assert resultado.returncode == 0, resultado.stderr
    assert resultado.stdout.strip() == "ok"
