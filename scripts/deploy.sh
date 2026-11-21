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

msg "Empaquetando src/pipeline"
cd "$ROOT_DIR" || exit 1
mkdir -p build
rm -f build/pipeline.zip
(cd src && zip -r -q ../build/pipeline.zip pipeline -x '*/__pycache__/*' '*.pyc')

msg "Subiendo código, DAGs y framework a s3://$LAKE/"
aws s3 cp build/pipeline.zip "s3://$LAKE/code/pipeline.zip"
aws s3 cp src/pipeline/run_glue.py "s3://$LAKE/code/run_glue.py"
# ingesta_mensual.py y hola_airflow.py son ejercicios de la clase 6 para el Airflow local del Code
# Editor: no se suben a prod. El --exclude evita subirlos, pero 'sync --delete' no borra en destino
# lo que está excluido; por eso el 'rm' los quita si ya estaban de una sincronización anterior (la
# VM los borra en su propio sync con --delete).
aws s3 sync airflow/dags "s3://$LAKE/dags/" --delete --exclude '*__pycache__*' \
  --exclude 'ingesta_mensual.py' --exclude 'hola_airflow.py'
aws s3 rm "s3://$LAKE/dags/ingesta_mensual.py"
aws s3 rm "s3://$LAKE/dags/hola_airflow.py"
aws s3 sync airflow/framework "s3://$LAKE/code/airflow/framework/" --delete --exclude '*__pycache__*'
# La VM necesita el paquete pipeline (cargar_gold_task importa pipeline.herramientas).
aws s3 sync src/pipeline "s3://$LAKE/code/airflow/pipeline/" --delete --exclude '*__pycache__*' --exclude '*.pyc'
aws s3 cp airflow/docker-compose.yaml "s3://$LAKE/code/airflow/docker-compose.yaml"
# Refresco de la VM: la VM baja el cuerpo en cada ejecución, así que esto basta para cambiarlo.
aws s3 cp airflow/vm/airflow-refresh.sh "s3://$LAKE/code/airflow/airflow-refresh.sh"
aws s3 cp infra/aws/modules/airflow_vm/refresh-bootstrap.sh "s3://$LAKE/code/airflow/airflow-bootstrap.sh"
aws s3 cp airflow/vm/instalar-bootstrap.sh "s3://$LAKE/code/airflow/instalar-bootstrap.sh"

msg "Rutas del lake (cada entorno solo toca su carpeta; el detalle: docs/rutas_del_lake.md)"
mostrar_rutas_del_lake
avisar_rutas_antiguas_del_lake || true

msg "Deploy completado"
echo "Si la VM de Airflow ya estaba encendida, se actualiza sola en ~1 min (DAGs, framework y pipeline)."
echo "El docker-compose.yaml se aplica al próximo arranque de la VM (make airflow-off && make airflow-on)."
