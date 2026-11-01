#!/usr/bin/env bash
# Fase 2 de la integración con Snowflake: aplica infra/snowflake, copia sus outputs
# (storage_aws_iam_user_arn, storage_aws_external_id) a la configuración de AWS en S3 y,
# salvo SIN_DEPLOY=true, aplica la fase 2 de AWS con deploy.sh (trust policy del rol).
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

requerir aws terraform zip jq make
SF_DIR="$ROOT_DIR/infra/snowflake"

msg "Terraform apply: infra/snowflake (confirma el plan cuando lo pida)"
make -C "$SF_DIR" apply

IAM_ARN="$(terraform -chdir="$SF_DIR" output -raw storage_aws_iam_user_arn)"
EXT_ID="$(terraform -chdir="$SF_DIR" output -raw storage_aws_external_id)"
[[ -n "$IAM_ARN" && -n "$EXT_ID" ]] || error "Snowflake no devolvió storage_aws_iam_user_arn ni storage_aws_external_id (¿terminó bien el apply?)."

config_set snowflake_iam_user_arn "$IAM_ARN"
config_set snowflake_external_id "$EXT_ID"

if [[ "${SIN_DEPLOY:-}" == "true" ]]; then
  msg "SIN_DEPLOY=true: no se aplica AWS. Corre 'make deploy' (o 'make airflow-habilitar') para aplicar la fase 2."
  exit 0
fi

msg "Fase 2 de AWS: deploy.sh con la trust policy de Snowflake"
bash "$ROOT_DIR/scripts/deploy.sh"
