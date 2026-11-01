#!/usr/bin/env bash
# Ejecuta el pipeline en local (Spark en el Code Editor) sobre la muestra.
# Variables: STEP (silver|gold|all), MES (YYYY-MM), LIMITE (máximo de viajes; vacío = toda la muestra).
# La primera vez descarga la muestra de s3://<lake>/muestra a ./lake/muestra (generarla con
# 'make muestra' si todavía no existe).
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

STEP="${STEP:-all}"
requerir python3

case "$STEP" in
  silver|gold|all) ;;
  *) error "STEP inválido: '$STEP' (en local usa silver, gold o all; bronze y muestra corren en Glue)." ;;
esac

ARGS="--step $STEP --env local --engine local"
if [[ -n "${MES:-}" ]]; then
  [[ "$MES" =~ ^[0-9]{4}-[0-9]{2}$ ]] || error "MES debe tener formato YYYY-MM (recibido: $MES)."
  ARGS="$ARGS --mes $MES"
fi
if [[ -n "${LIMITE:-}" ]]; then
  [[ "$LIMITE" =~ ^[0-9]+$ ]] || error "LIMITE debe ser un entero (recibido: $LIMITE)."
  ARGS="$ARGS --limite $LIMITE"
fi

# LAKE_BUCKET solo hace falta para descargar la muestra la primera vez.
export LAKE_BUCKET="${LAKE_BUCKET:-$(lake_bucket 2>/dev/null || true)}"

msg "Pipeline local: $ARGS"
cd "$ROOT_DIR" || exit 1
# shellcheck disable=SC2086
PYTHONPATH="$ROOT_DIR/src" exec "$ROOT_DIR/.venv/bin/python" -m pipeline.run $ARGS
