#!/usr/bin/env bash
# Cambia enable_airflow en la configuración de S3 y aplica con deploy.sh.
# Uso: airflow-config.sh true|false   (apagar la VM exige CONFIRMAR_DESTRUCCION=true)
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

VALOR="${1:-}"
[[ "$VALOR" == true || "$VALOR" == false ]] || error "Uso: airflow-config.sh true|false"

requerir aws terraform zip jq
config_set enable_airflow "$VALOR"

msg "Aplicando la configuración (deploy.sh)"
bash "$ROOT_DIR/scripts/deploy.sh" || {
  aviso "El deploy no terminó. La configuración ya tiene enable_airflow = $VALOR; corrige el problema y vuelve a correr 'make deploy'."
  exit 1
}
