#!/usr/bin/env bash
# Deja la VM de Airflow de prod con la configuración de la clase 7: refresh.env apuntando al secreto de
# prod (<PREFIX>/snowflake_prod, rol BIGDATA_PROD), el arranque y el cron de sincronización. Corre
# airflow/vm/instalar-bootstrap.sh dentro de la VM por SSM. Se hace una vez por cuenta.
# Requisito: el CI/CD ya publicó el código (merge a main) y la VM está encendida (make airflow-on).
# Uso: cd ~/bigdata && make actualizar-vm
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

requerir aws
exigir_cuenta
LAKE="$(lake_bucket)"
ID="$(find_airflow_instance_id)"
[[ -n "$ID" ]] || error "No existe la instancia ${PREFIX}-airflow (¿enable_airflow = true?)."
[[ "$(instance_state "$ID")" == "running" ]] \
  || error "La VM $ID no está encendida. Enciéndela con 'cd ~/bigdata && make airflow-on', espera ~2 minutos y repite."
aws s3api head-object --bucket "$LAKE" --key code/airflow/instalar-bootstrap.sh >/dev/null 2>&1 \
  || error "Falta s3://$LAKE/code/airflow/instalar-bootstrap.sh: el CI/CD todavía no ha publicado el código (haz merge a main y espera el workflow Deploy)."

msg "Actualizando la VM $ID (secreto de prod: $SECRETO_SNOWFLAKE_PROD)"
CMD="aws s3 cp s3://$LAKE/code/airflow/instalar-bootstrap.sh /tmp/instalar-bootstrap.sh --only-show-errors && LAKE=$LAKE REGION=$AWS_REGION PREFIX=$PREFIX bash /tmp/instalar-bootstrap.sh"
CMD_ID="$(aws ssm send-command --instance-ids "$ID" --document-name AWS-RunShellScript \
  --parameters "commands=[\"$CMD\"]" --query Command.CommandId --output text)" \
  || error "No pude enviar el comando por SSM a la VM $ID."

for _ in $(seq 1 40); do
  ESTADO="$(aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$ID" \
    --query Status --output text 2>/dev/null || echo Pending)"
  case "$ESTADO" in
    Success) msg "VM actualizada. Airflow de prod se reinició con el secreto $SECRETO_SNOWFLAKE_PROD."; exit 0 ;;
    Failed|Cancelled|TimedOut)
      aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$ID" \
        --query StandardErrorContent --output text >&2 || true
      error "La actualización de la VM terminó en $ESTADO. Revisa el mensaje de arriba y avisa al instructor." ;;
  esac
  sleep 5
done
error "La VM no respondió a tiempo (estado: $ESTADO). Repite 'cd ~/bigdata && make actualizar-vm'."
