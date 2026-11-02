#!/usr/bin/env bash
# Fase 2 de la integración con Snowflake: aplica infra/snowflake, copia sus outputs
# (storage_aws_iam_user_arn, storage_aws_external_id) a la configuración de AWS en S3 y,
# salvo SIN_DEPLOY=true, aplica la fase 2 de AWS con deploy.sh (trust policy del rol).
# Además deja lista la conexión de Airflow a Snowflake: el apply crea el usuario AIRFLOW_SVC con una
# llave que genera el Makefile (~/.snowflake/keys/airflow_svc_rsa_key.p8) y snowflake-secreto.sh
# guarda esa llave y los datos de conexión en el secreto <prefix>/snowflake. Sin pasos manuales.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

requerir aws terraform zip jq make
exigir_cuenta
SF_DIR="$ROOT_DIR/infra/snowflake"

# Init con backend S3 (mismas flags que destroy.sh); -reconfigure evita el prompt si la caché local apunta a otro backend.
# Llave de TERRAFORM_SVC, 01_admin.sql, terraform.tfvars y backend.hcl (idempotente).
bash "$ROOT_DIR/scripts/snowflake-preparar.sh"

msg "Terraform init: infra/snowflake"
terraform -chdir="$SF_DIR" init -reconfigure -input=false -backend-config="bucket=$(tfstate_bucket)" \
  -backend-config="key=snowflake/terraform.tfstate" -backend-config="region=$AWS_REGION" \
  -backend-config="use_lockfile=true"

preparar_airflow_svc() {
  # Terraform crea AIRFLOW_SVC con TERRAFORM_ROLE: necesita CREATE USER (01_admin.sql lo concede
  # en cuentas nuevas; aquí se completa en cuentas ya bootstrapeadas). Usa la conexión de `snow`.
  command -v snow >/dev/null 2>&1 || { aviso "Sin 'snow': no se comprobó el permiso CREATE USER de TERRAFORM_ROLE."; return 0; }
  local out
  if ! out="$(snow sql -q "SHOW GRANTS TO ROLE TERRAFORM_ROLE" --format json 2>/dev/null)"; then
    aviso "No se pudo consultar TERRAFORM_ROLE con 'snow'; si el apply falla por CREATE USER, ejecuta como ACCOUNTADMIN: GRANT CREATE USER ON ACCOUNT TO ROLE TERRAFORM_ROLE;"
    return 0
  fi
  if ! jq -e '.[] | select(.privilege == "CREATE USER")' >/dev/null 2>&1 <<< "$out"; then
    msg "Concediendo CREATE USER a TERRAFORM_ROLE (para crear AIRFLOW_SVC)"
    snow sql -q "USE ROLE ACCOUNTADMIN; GRANT CREATE USER ON ACCOUNT TO ROLE TERRAFORM_ROLE;" >/dev/null \
      || error "No se pudo conceder CREATE USER. Ejecuta en Snowsight como ACCOUNTADMIN: GRANT CREATE USER ON ACCOUNT TO ROLE TERRAFORM_ROLE;"
  fi
  # Un AIRFLOW_SVC creado a mano (no por Terraform) haría fallar el apply con "already exists".
  if out="$(snow sql -q "SHOW USERS LIKE 'AIRFLOW_SVC'" --format json 2>/dev/null)" \
     && [[ "$(jq 'length' <<< "$out" 2>/dev/null || echo 0)" != "0" ]]; then
    local estado
    if estado="$(terraform -chdir="$SF_DIR" state list 2>/dev/null)"; then
      [[ "$estado" != *snowflake_service_user.airflow* ]] || return 0
      error "AIRFLOW_SVC ya existe en Snowflake y no lo gestiona Terraform. Elimínalo (Snowsight, ACCOUNTADMIN: DROP USER AIRFLOW_SVC;) y repite 'make snowflake': se recrea con la llave de ~/.snowflake/keys/airflow_svc_rsa_key.pub."
    fi
  fi
}

preparar_airflow_svc

msg "Terraform apply: infra/snowflake (confirma el plan cuando lo pida)"
make -C "$SF_DIR" apply

IAM_ARN="$(terraform -chdir="$SF_DIR" output -raw storage_aws_iam_user_arn)"
EXT_ID="$(terraform -chdir="$SF_DIR" output -raw storage_aws_external_id)"
[[ -n "$IAM_ARN" && -n "$EXT_ID" ]] || error "Snowflake no devolvió storage_aws_iam_user_arn ni storage_aws_external_id (¿terminó bien el apply?)."

config_set snowflake_iam_user_arn "$IAM_ARN"
config_set snowflake_external_id "$EXT_ID"

if [[ "${SIN_DEPLOY:-}" == "true" ]]; then
  # El secreto <prefix>/snowflake lo crea Terraform en infra/aws: si aún no existe, se escribe tras 'make deploy'.
  bash "$ROOT_DIR/scripts/snowflake-secreto.sh" \
    || aviso "Conexión de Airflow pendiente: corre 'make deploy' y luego 'make snowflake-secreto'."
  msg "SIN_DEPLOY=true: no se aplica AWS. Corre 'make deploy' (o 'make airflow-habilitar') para aplicar la fase 2."
  exit 0
fi

msg "Fase 2 de AWS: deploy.sh con la trust policy de Snowflake"
bash "$ROOT_DIR/scripts/deploy.sh"

msg "Conexión de Airflow a Snowflake: llave de AIRFLOW_SVC -> secreto $PREFIX/snowflake"
bash "$ROOT_DIR/scripts/snowflake-secreto.sh"
