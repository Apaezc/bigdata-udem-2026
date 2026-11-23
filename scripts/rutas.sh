#!/usr/bin/env bash
# Imprime en qué bucket y carpetas lee y escribe cada entorno (la misma tabla que
# donde_estoy("dev") en un cuaderno). Sin argumentos muestra dev y prod. Es solo informativo:
# no cambia con qué entorno corres (desde el Code Editor siempre es dev).
# Uso: cd ~/bigdata && bash scripts/rutas.sh [dev|prod]    (con make: make rutas ENTORNO=prod)
# El nombre del bucket sale de tu cuenta de AWS; si no hay credenciales, se usa un marcador.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

entornos="${1:-dev prod}"
for entorno in $entornos; do
  case "$entorno" in
    dev|prod) ;;
    *) error "Entorno inválido: '$entorno' (usa dev o prod; 'local' se retiró en la clase 7)." ;;
  esac
done

[[ -x "$VENV_DIR/bin/python" ]] || error ".venv no existe: corre make setup (o make reparar-entorno)."

# LAKE_BUCKET es opcional: sin él la tabla muestra <tu-bucket> en lugar del nombre real.
export LAKE_BUCKET="${LAKE_BUCKET:-$(lake_bucket 2>/dev/null || true)}"

for entorno in $entornos; do
  PYTHONPATH="$ROOT_DIR/src" "$VENV_DIR/bin/python" -c \
    "from pipeline.herramientas.rutas import donde_estoy; donde_estoy('$entorno')"
  echo
done
