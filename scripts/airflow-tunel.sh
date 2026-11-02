#!/usr/bin/env bash
# Abre un port forwarding SSM: localhost:8080 -> proxy-studio (127.0.0.1:8081 en la VM). Ctrl+C para cerrar.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

requerir aws session-manager-plugin
ID="$(find_airflow_instance_id)"
[[ -n "$ID" ]] || error "No existe la instancia ${PREFIX}-airflow."

ESTADO="$(instance_state "$ID")"
[[ "$ESTADO" == "running" ]] || error "La instancia está '$ESTADO'. Ejecuta 'make airflow-on' primero."

# El Airflow de dev (make airflow-local) también usa el puerto 8080: no pueden convivir.
if (exec 3<>/dev/tcp/127.0.0.1/8080) 2>/dev/null; then
  error "El puerto 8080 está ocupado (¿Airflow de dev encendido?). Apágalo con: cd $ROOT_DIR && make airflow-local-down"
fi

msg "Túnel SSM hacia $ID (deja esta terminal abierta; Ctrl+C para cerrar)."
echo "UI de Airflow (prod): $(url_airflow_studio)"

aws ssm start-session \
  --target "$ID" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8081"],"localPortNumber":["8080"]}'
