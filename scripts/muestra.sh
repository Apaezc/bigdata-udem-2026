#!/usr/bin/env bash
# Retirado en la clase 7: ya no hay muestra. Solo avisa y sale con error.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
echo "ERROR: 'make muestra' se retiró en la clase 7: ya no hay muestra ni bucket público de muestra." >&2
echo "  El crudo se descarga solo la primera vez que corres bronze, directo a s3://<tu-bucket>/dev/bronze/_crudo/." >&2
echo "  Usa:  cd ~/bigdata && make correr PASO=bronze" >&2
exit 1
