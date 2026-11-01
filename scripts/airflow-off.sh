#!/usr/bin/env bash
# Apaga la instancia de Airflow (tag Name=${PREFIX}-airflow).
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

requerir aws
ID="$(find_airflow_instance_id)"
[[ -n "$ID" ]] || error "No existe la instancia ${PREFIX}-airflow."

ESTADO="$(instance_state "$ID")"
if [[ "$ESTADO" == "stopped" ]]; then
  msg "La instancia $ID ya está apagada."
else
  msg "Apagando instancia $ID (estado actual: $ESTADO)"
  aws ec2 stop-instances --instance-ids "$ID" >/dev/null
  aws ec2 wait instance-stopped --instance-ids "$ID"
  msg "Instancia apagada."
fi
