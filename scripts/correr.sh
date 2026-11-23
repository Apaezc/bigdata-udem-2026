#!/usr/bin/env bash
# Corre el pipeline en dev desde el Code Editor. El entorno NO se elige: aquí siempre es dev.
# Variables (todas opcionales; lo que no pongas sale de pipeline.yaml):
#   PASO        bronze | silver | gold | snowflake   (vacío = los cuatro, en orden)
#   COMPUTO     code_editor | glue_small | glue_medium | glue_large
#   LIMITE      1000 | 100000 | todos                (todos solo con Glue)
#   MES         AAAA-MM                              (vacío = lo de pipeline.yaml)
#   REPROCESAR  true | false
# Ejemplo: make correr PASO=silver LIMITE=100000 COMPUTO=glue_small REPROCESAR=true
# CORRER_SOLO_MOSTRAR=1 imprime el comando y no lo corre (para revisar).
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Quien llama con ENTORNO=prod no cambia nada: se dice claro y se sigue en dev.
if [[ -n "${ENTORNO:-}" ]]; then
  aviso "El entorno no se elige: desde el Code Editor siempre es dev (ignoro ENTORNO='$ENTORNO')."
  aviso "Prod lo corre solo la VM de Airflow, después de PR -> merge a main -> CI/CD."
fi
export PIPELINE_ENTORNO=dev

ARGS=()
if [[ -n "${PASO:-}" ]]; then
  case "$PASO" in
    bronze|silver|gold|snowflake) ARGS+=(--paso "$PASO") ;;
    *) error "PASO='$PASO' no existe. Usa bronze, silver, gold o snowflake (sin PASO corre los cuatro)." ;;
  esac
fi
if [[ -n "${COMPUTO:-}" ]]; then
  case "$COMPUTO" in
    code_editor|glue_small|glue_medium|glue_large) ARGS+=(--computo "$COMPUTO") ;;
    *) error "COMPUTO='$COMPUTO' no existe. Usa code_editor, glue_small, glue_medium o glue_large." ;;
  esac
fi
if [[ -n "${LIMITE:-}" ]]; then
  case "$LIMITE" in
    1000|100000|todos) ARGS+=(--limite "$LIMITE") ;;
    *) error "LIMITE='$LIMITE' no vale. Usa 1000, 100000 o todos." ;;
  esac
  if [[ "$LIMITE" == "todos" && "${COMPUTO:-}" == "code_editor" ]]; then
    error "LIMITE=todos no cabe en el Code Editor: usa un cómputo de Glue (COMPUTO=glue_small, por ejemplo)."
  fi
fi
if [[ -n "${MES:-}" ]]; then
  [[ "$MES" =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]] || error "MES debe tener formato AAAA-MM, por ejemplo 2024-01 (recibí: $MES)."
  ARGS+=(--mes "$MES")
fi
if [[ -n "${REPROCESAR:-}" ]]; then
  case "$REPROCESAR" in
    true|false) ARGS+=(--reprocesar "$REPROCESAR") ;;
    *) error "REPROCESAR debe ser true o false (recibí: $REPROCESAR)." ;;
  esac
fi

# Conexiones de dev: el bucket del lake y el secreto de Snowflake con el rol BIGDATA_DEV.
export WATERMARK_SECRET="$SECRETO_SNOWFLAKE"
if [[ -z "${LAKE_BUCKET:-}" && "${CORRER_SOLO_MOSTRAR:-}" != "1" ]]; then
  LAKE_BUCKET="$(lake_bucket 2>/dev/null || true)"
fi
export LAKE_BUCKET="${LAKE_BUCKET:-}"

cd "$ROOT_DIR" || exit 1
PY="$ROOT_DIR/.venv/bin/python"
if [[ "${CORRER_SOLO_MOSTRAR:-}" == "1" ]]; then
  echo "cd $ROOT_DIR"
  echo "PIPELINE_ENTORNO=dev WATERMARK_SECRET=$WATERMARK_SECRET LAKE_BUCKET=$LAKE_BUCKET PYTHONPATH=$ROOT_DIR/src $PY -m pipeline.run ${ARGS[*]:-}"
  exit 0
fi
[[ -x "$PY" ]] || error "No existe .venv: corre 'cd ~/bigdata && make reparar-entorno' y repite."
# ${ARGS[@]+...}: bash 3.2 (macOS) falla con arrays vacíos bajo set -u.
PYTHONPATH="$ROOT_DIR/src" exec "$PY" -m pipeline.run ${ARGS[@]+"${ARGS[@]}"}
