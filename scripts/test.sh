#!/usr/bin/env bash
# Lint (ruff) y pruebas (pytest).
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

cd "$ROOT_DIR" || exit 1
# Prefiere el entorno del repo (.venv, Python 3.12) al python3 del PATH: en el Code Editor el PATH
# trae conda con 3.13, con el que pyspark y las dependencias fijadas no coinciden.
if [[ -x .venv/bin/python ]]; then
  PY=".venv/bin/python"
  RUFF=".venv/bin/ruff"
else
  requerir python3 ruff
  PY="python3"
  RUFF="ruff"
fi
export PYTHONPATH="$ROOT_DIR/src${PYTHONPATH:+:$PYTHONPATH}"

msg "Ruff (lint y formato)"
"$RUFF" check .
"$RUFF" format --check .

# Se usa 'python -m pytest' y no el ejecutable 'pytest': en el Code Editor el shebang de
# .venv/bin/pytest apunta a una ruta que ya no existe y el comando falla.
msg "Pytest (src)"
# -rs muestra el motivo de cada prueba omitida (por ejemplo «PENDIENTE: falta deduplicar»).
"$PY" -m pytest -rs

# Los tests de los DAGs necesitan Airflow (pip install -r airflow/requirements.txt); en CI corren siempre.
# (no basta 'import airflow': la carpeta airflow/ del repo se importaría como paquete vacío)
# El Airflow local del Code Editor vive en su propio venv (~/.airflow-local/venv): si existe, se usa.
PY_AIRFLOW="$PY"
[[ -x "$HOME/.airflow-local/venv/bin/python" ]] && PY_AIRFLOW="$HOME/.airflow-local/venv/bin/python"
# El venv de Airflow local no trae pytest: se instala ahí la primera vez (unos segundos).
if "$PY_AIRFLOW" -c 'from airflow.sdk import DAG' >/dev/null 2>&1 \
  && ! "$PY_AIRFLOW" -c 'import pytest' >/dev/null 2>&1; then
  msg "Instalando pytest en el venv de Airflow local"
  "$PY_AIRFLOW" -m pip install --quiet pytest || aviso "No se pudo instalar pytest en $PY_AIRFLOW"
fi
if "$PY_AIRFLOW" -c 'from airflow.sdk import DAG; import pytest' >/dev/null 2>&1; then
  msg "Pytest (airflow/tests)"
  "$PY_AIRFLOW" -m pytest airflow/tests
else
  aviso "Airflow no está instalado: se omiten airflow/tests (corren en CI)."
fi
