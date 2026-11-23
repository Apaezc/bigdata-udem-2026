"""Preparación común de las pruebas de los DAGs.

Airflow lee su configuración al importarse: hay que fijarla antes de cualquier import de airflow.
"""

from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path

AIRFLOW_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = AIRFLOW_ROOT.parent

os.environ.setdefault("AIRFLOW_HOME", tempfile.mkdtemp(prefix="airflow_home_"))
os.environ.setdefault("AIRFLOW__CORE__LOAD_EXAMPLES", "False")
os.environ.setdefault("AIRFLOW__CORE__UNIT_TEST_MODE", "True")
# Estas pruebas son del Airflow de dev: ni un entorno ni un pipeline.yaml ajenos las alteran.
for variable in ("PIPELINE_ENTORNO", "PIPELINE_YAML", "PIPELINE_RAIZ_LAKE"):
    os.environ.pop(variable, None)
# Los DAGs y `framework` salen de airflow/; `pipeline` sale de src/.
for ruta in (AIRFLOW_ROOT, REPO_ROOT / "src"):
    if str(ruta) not in sys.path:
        sys.path.insert(0, str(ruta))
