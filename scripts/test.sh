#!/usr/bin/env bash
# Lint (ruff) y pruebas (pytest).
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

requerir python3 ruff pytest
cd "$ROOT_DIR" || exit 1
export PYTHONPATH="$ROOT_DIR/src${PYTHONPATH:+:$PYTHONPATH}"

msg "Ruff (lint y formato)"
ruff check .
ruff format --check .

msg "Pytest (src)"
pytest

# Los tests de los DAGs necesitan Airflow (pip install -r airflow/requirements.txt); en CI corren siempre.
# (no basta 'import airflow': la carpeta airflow/ del repo se importaría como paquete vacío)
if python3 -c 'from airflow.sdk import DAG' >/dev/null 2>&1; then
  msg "Pytest (airflow/tests)"
  pytest airflow/tests
else
  aviso "Airflow no está instalado: se omiten airflow/tests (corren en CI)."
fi
