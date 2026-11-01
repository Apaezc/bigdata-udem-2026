#!/usr/bin/env bash
# Enciende la instancia de Airflow (tag Name=${PREFIX}-airflow) e imprime la URL.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

requerir aws
ID="$(find_airflow_instance_id)"
[[ -n "$ID" ]] || error "No existe la instancia ${PREFIX}-airflow (¿enable_airflow = true y terraform apply?)."

ESTADO="$(instance_state "$ID")"
if [[ "$ESTADO" == "running" ]]; then
  msg "La instancia $ID ya está encendida."
else
  msg "Encendiendo instancia $ID (estado actual: $ESTADO)"
  aws ec2 start-instances --instance-ids "$ID" >/dev/null
  aws ec2 wait instance-running --instance-ids "$ID"
fi

msg "Airflow de prod encendido (Airflow tarda ~2 min en responder)."
echo "Acceso: 'make airflow-tunel' desde el Code Editor y la URL /codeeditor/default/ports/8080/."
