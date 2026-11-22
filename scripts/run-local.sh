#!/usr/bin/env bash
# Retirado en la clase 7: ya no existe el entorno local. Solo avisa y sale con error.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
echo "ERROR: 'make run-local' se retiró en la clase 7: ya no hay entorno local en disco." >&2
echo "  Spark en el Code Editor ahora lee y escribe en S3 (dev) y se llama cómputo 'code_editor'." >&2
echo "  Usa:  cd ~/bigdata && make correr PASO=silver LIMITE=1000" >&2
echo "  Si es la primera vez, antes:  cd ~/bigdata && make jars-s3a" >&2
exit 1
