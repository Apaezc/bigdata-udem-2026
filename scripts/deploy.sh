#!/usr/bin/env bash
# Despliegue local equivalente a .github/workflows/deploy.yml:
# configuración desde s3://<state>/config/aws.tfvars, plan con -out, guardia de destrucción,
# apply de infra/aws y sincronización de código y DAGs a S3.
#
# La configuración de Terraform (enable_airflow, enable_glue, alert_email, fase 2 de Snowflake...)
# vive solo en S3: se cambia con 'make config' / 'make airflow-habilitar' / 'make snowflake'.
# Si el plan elimina o reemplaza recursos, el script aborta salvo CONFIRMAR_DESTRUCCION=true.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

requerir aws terraform zip jq

BUCKET_ESTADO="$(tfstate_bucket)"
LAKE="$(lake_bucket)"
msg "Bucket de estado: $BUCKET_ESTADO"
msg "Bucket del lake: $LAKE"

msg "Descargando configuración de $(config_uri)"
config_pull

PLAN_FILE="$(mktemp -t tfplan.XXXXXX)"
trap 'rm -f "$PLAN_FILE"' EXIT

msg "Terraform init (infra/aws)"
cd "$ROOT_DIR/infra/aws" || exit 1
terraform init -input=false \
  -backend-config="bucket=$BUCKET_ESTADO" \
  -backend-config="key=aws/terraform.tfstate" \
  -backend-config="region=$AWS_REGION" \
  -backend-config="use_lockfile=true"

msg "Terraform plan (infra/aws)"
terraform plan -input=false -lock-timeout=5m -out="$PLAN_FILE" -var-file="$CONFIG_LOCAL"

msg "Guardia de destrucción"
guardia_destruccion "$PLAN_FILE"

msg "Terraform apply (aplica el plan revisado)"
terraform apply -input=false -lock-timeout=5m "$PLAN_FILE"

msg "Empaquetando src/pipeline"
cd "$ROOT_DIR" || exit 1
mkdir -p build
rm -f build/pipeline.zip
(cd src && zip -r -q ../build/pipeline.zip pipeline -x '*/__pycache__/*' '*.pyc')

msg "Subiendo código, DAGs y framework a s3://$LAKE/"
aws s3 cp build/pipeline.zip "s3://$LAKE/code/pipeline.zip"
aws s3 cp src/pipeline/run_glue.py "s3://$LAKE/code/run_glue.py"
aws s3 sync airflow/dags "s3://$LAKE/dags/" --delete --exclude '*__pycache__*'
aws s3 sync airflow/framework "s3://$LAKE/code/airflow/framework/" --delete --exclude '*__pycache__*'
aws s3 cp airflow/docker-compose.yaml "s3://$LAKE/code/airflow/docker-compose.yaml"

msg "Deploy completado"
echo "Si la VM de Airflow ya estaba encendida, se actualiza sola en ~1 min (DAGs y framework)."
echo "El docker-compose.yaml se aplica al próximo arranque de la VM (make airflow-off && make airflow-on)."
