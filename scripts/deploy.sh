#!/usr/bin/env bash
# Despliegue local: configuración desde s3://<state>/config/aws.tfvars, plan con -out, guardia de
# destrucción y apply de infra/aws.
#
# El código de prod (pipeline.zip, dags/, framework/, code/airflow/*) lo publica SOLO el CI/CD
# (.github/workflows/deploy.yml, al hacer merge a main). Desde el Code Editor este script no lo sube:
# dev nunca publica código de prod. Solo sube code/run_glue.py (entrada estable, sin lógica).
# Excepción del instructor: CONFIRMAR_PROD=si sube también todo lo demás.
#
# La configuración de Terraform (enable_airflow, enable_glue, alert_email, fase 2 de Snowflake...)
# vive solo en S3: se cambia con 'make config' / 'make airflow-habilitar' / 'make snowflake'.
# Si el plan elimina o reemplaza recursos, el script aborta salvo CONFIRMAR_DESTRUCCION=true.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

requerir aws terraform jq
[[ "${CONFIRMAR_PROD:-}" != "si" ]] || requerir zip
exigir_cuenta

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
terraform init -reconfigure -input=false \
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

cd "$ROOT_DIR" || exit 1
msg "Subiendo code/run_glue.py (entrada estable de los jobs de Glue, sin lógica)"
aws s3 cp src/pipeline/run_glue.py "s3://$LAKE/code/run_glue.py"

if [[ "${CONFIRMAR_PROD:-}" != "si" ]]; then
  aviso "No subo el código de prod (pipeline.zip, dags/, framework/, code/airflow/*) desde el Code Editor."
  aviso "Eso lo hace el CI/CD cuando haces merge a main: PR -> CI -> merge -> workflow Deploy."
  aviso "Para correr tu código en Glue sin tocar prod usa: make correr COMPUTO=glue_small (sube el código a s3://$LAKE/code/dev/)."
else
  aviso "CONFIRMAR_PROD=si: voy a publicar código de PROD desde esta terminal (solo instructor)."
  msg "Empaquetando src/pipeline"
  mkdir -p build
  rm -f build/pipeline.zip
  (cd src && zip -r -q ../build/pipeline.zip pipeline -x '*/__pycache__/*' '*.pyc')

  msg "Subiendo código, DAGs y framework a s3://$LAKE/"
  aws s3 cp build/pipeline.zip "s3://$LAKE/code/pipeline.zip"
  aws s3 sync airflow/dags "s3://$LAKE/dags/" --delete --exclude '*__pycache__*'
  aws s3 sync airflow/framework "s3://$LAKE/code/airflow/framework/" --delete --exclude '*__pycache__*'
  # La VM necesita el paquete pipeline (las tareas importan pipeline.herramientas).
  aws s3 sync src/pipeline "s3://$LAKE/code/airflow/pipeline/" --delete --exclude '*__pycache__*' --exclude '*.pyc'
  aws s3 cp airflow/docker-compose.yaml "s3://$LAKE/code/airflow/docker-compose.yaml"
  # Refresco de la VM: la VM baja el cuerpo en cada ejecución, así que esto basta para cambiarlo.
  aws s3 cp airflow/vm/airflow-refresh.sh "s3://$LAKE/code/airflow/airflow-refresh.sh"
  aws s3 cp infra/aws/modules/airflow_vm/refresh-bootstrap.sh "s3://$LAKE/code/airflow/airflow-bootstrap.sh"
  aws s3 cp airflow/vm/instalar-bootstrap.sh "s3://$LAKE/code/airflow/instalar-bootstrap.sh"
fi

msg "Rutas del lake (cada entorno solo toca su carpeta; el detalle: docs/rutas_del_lake.md)"
mostrar_rutas_del_lake
avisar_rutas_antiguas_del_lake || true

msg "Deploy completado"
echo "El código de prod llega a la VM por el CI/CD (merge a main); la VM lo toma sola en ~1 min."
echo "Si cambió el docker-compose.yaml, se aplica al próximo arranque de la VM (make airflow-off && make airflow-on)."
