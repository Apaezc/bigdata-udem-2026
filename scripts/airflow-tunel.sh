#!/usr/bin/env bash
# Abre un port forwarding SSM: localhost:8080 -> proxy-studio (127.0.0.1:8081 en la VM). Ctrl+C para cerrar.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

requerir aws session-manager-plugin
ID="$(find_airflow_instance_id)"
[[ -n "$ID" ]] || error "No existe la instancia ${PREFIX}-airflow."

ESTADO="$(instance_state "$ID")"
[[ "$ESTADO" == "running" ]] || error "La instancia está '$ESTADO'. Ejecuta 'make airflow-on' primero."

msg "Túnel SSM hacia $ID (deja esta terminal abierta; Ctrl+C para cerrar)."
echo "Abre en el navegador la URL de tu Code Editor cambiando lo que va después del dominio por:"
echo "  /codeeditor/default/ports/8080/"
echo "  ej.: https://<id-del-space>.studio.${AWS_REGION}.sagemaker.aws/codeeditor/default/ports/8080/"

aws ssm start-session \
  --target "$ID" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8081"],"localPortNumber":["8080"]}'
