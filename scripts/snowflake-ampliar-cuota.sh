#!/usr/bin/env bash
# Amplía la cuota de créditos del resource monitor ${PREFIX}_RM (requiere ACCOUNTADMIN).
# Uso: scripts/snowflake-ampliar-cuota.sh [CUOTA]   (o variable CUOTA)
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

requerir snow
RM="$(echo "${PREFIX}_RM" | tr "[:lower:]" "[:upper:]")"

CUOTA="${1:-${CUOTA:-}}"
if [[ -z "$CUOTA" ]]; then
  [[ -t 0 ]] || error "Indica la nueva cuota: make snowflake-ampliar-cuota CUOTA=<créditos>."
  read -r -p "Nueva cuota de créditos mensual para $RM: " CUOTA
fi
[[ "$CUOTA" =~ ^[0-9]+$ ]] || error "La cuota debe ser un entero de créditos (recibido: '$CUOTA')."
(( CUOTA > 0 )) || error "La cuota debe ser mayor que 0."

confirmar "Se cambiará la cuota de $RM a $CUOTA créditos usando el rol ACCOUNTADMIN." "SI"

snow sql -q "USE ROLE ACCOUNTADMIN; ALTER RESOURCE MONITOR ${RM} SET CREDIT_QUOTA = ${CUOTA};"
msg "Cuota de $RM actualizada a $CUOTA créditos."
