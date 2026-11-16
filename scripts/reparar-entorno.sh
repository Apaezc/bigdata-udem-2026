#!/usr/bin/env bash
# Repara el entorno de Python tras una actualización de la imagen del Code Editor: recrea .venv con
# Python 3.12, reinstala las dependencias, registra el kernel «Python (bigdata)» y comprueba que
# 'snow' funcione (si no, lo reinstala con el Python de conda).
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CONDA_PYTHON="${CONDA_PYTHON:-/opt/conda/bin/python3}"

reparar_snow() {
  # 'snow' vive en ~/.local/bin y depende del Python de conda con el que se instaló.
  export PATH="$HOME/.local/bin:$PATH"
  if snow --version >/dev/null 2>&1; then
    msg "snow funciona; no hace falta reinstalarlo"
    return 0
  fi
  aviso "snow no funciona; se reinstala snowflake-cli con el Python de conda."
  if [[ ! -x "$CONDA_PYTHON" ]]; then
    error "No existe $CONDA_PYTHON. Instala snowflake-cli a mano: python3 -m pip install --user snowflake-cli"
  fi
  "$CONDA_PYTHON" -m pip install --quiet --user snowflake-cli
  hash -r
  snow --version >/dev/null 2>&1 \
    || error "snow sigue sin funcionar tras reinstalarlo. Prueba: $CONDA_PYTHON -m pip install --user --force-reinstall snowflake-cli"
}

crear_venv
instalar_dependencias_venv
registrar_kernel

venv_sano || error ".venv quedó incompleto: no usa Python $VENV_PYTHON_VERSION o no importa pip y pyspark."

msg "Comprobando snow"
reparar_snow

VERSION_PYTHON="$("$VENV_DIR/bin/python" -c 'import platform; print(platform.python_version())')"
msg "Entorno reparado: Python $VERSION_PYTHON, snow OK"
echo "Si tienes un notebook abierto, elige de nuevo el kernel Python (bigdata) (Select Kernel) y reinicia el kernel."
