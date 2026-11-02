#!/usr/bin/env bash
# Prepara Snowflake para Terraform sin pasos manuales (lo llama 'make snowflake' antes del apply):
#   1. genera la llave de TERRAFORM_SVC si falta (~/.snowflake/keys/terraform_svc_rsa_key.p8);
#   2. ejecuta bootstrap/snowflake/01_admin.sql con la conexión por defecto de `snow` (ACCOUNTADMIN)
#      y registra la clave pública en TERRAFORM_SVC (también si el usuario ya existía);
#   3. escribe infra/snowflake/terraform.tfvars y backend.hcl si no existen, con los datos de la
#      cuenta de Snowflake, los outputs de infra/aws y tu usuario como dev_users.
# Idempotente: si los archivos ya existen no los toca. Requiere 'make snowflake-conexion' y 'make deploy'.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

requerir snow jq openssl terraform
SF_DIR="$ROOT_DIR/infra/snowflake"
LLAVE="$HOME/.snowflake/keys/terraform_svc_rsa_key.p8"
PUB="$HOME/.snowflake/keys/terraform_svc_rsa_key.pub"
TFVARS="$SF_DIR/terraform.tfvars"
BACKEND="$SF_DIR/backend.hcl"

snow connection test >/dev/null 2>&1 \
  || error "La conexión de snow no funciona. Corre primero: cd $ROOT_DIR && make snowflake-conexion"

if [[ ! -f "$LLAVE" ]]; then
  msg "Generando la llave de TERRAFORM_SVC en $LLAVE"
  bash "$ROOT_DIR/bootstrap/snowflake/gen_key.sh" TERRAFORM_SVC >/dev/null
fi
[[ -f "$PUB" ]] || openssl rsa -in "$LLAVE" -pubout -out "$PUB" 2>/dev/null
PUB_LINEA="$(grep -v -- '-----' "$PUB" | tr -d '\n')"
[[ -n "$PUB_LINEA" ]] || error "No se pudo leer la clave pública de $PUB."

msg "Ejecutando bootstrap/snowflake/01_admin.sql (resource monitor, TERRAFORM_ROLE, TERRAFORM_SVC)"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
sed "s#<PEGAR_CLAVE_PUBLICA>#$PUB_LINEA#" "$ROOT_DIR/bootstrap/snowflake/01_admin.sql" > "$tmp"
# Si TERRAFORM_SVC ya existía, CREATE USER IF NOT EXISTS no cambia su llave: se fija aquí.
printf "\nALTER USER TERRAFORM_SVC SET RSA_PUBLIC_KEY = '%s';\n" "$PUB_LINEA" >> "$tmp"
snow sql -f "$tmp" >/dev/null \
  || error "Falló 01_admin.sql. Revisa que tu usuario tenga el rol ACCOUNTADMIN (snow connection test debe mostrar Role ACCOUNTADMIN)."

if [[ ! -f "$TFVARS" ]]; then
  msg "Escribiendo $TFVARS"
  datos="$(snow sql -q "SELECT CURRENT_ORGANIZATION_NAME() AS org, CURRENT_ACCOUNT_NAME() AS cuenta, CURRENT_USER() AS usuario" --format json)" \
    || error "No se pudieron leer los datos de la cuenta de Snowflake."
  org="$(jq -r '.[0].ORG' <<< "$datos")"
  cuenta="$(jq -r '.[0].CUENTA' <<< "$datos")"
  usuario="$(jq -r '.[0].USUARIO' <<< "$datos")"
  rol_s3="$(terraform -chdir="$ROOT_DIR/infra/aws" output -raw snowflake_s3_role_arn 2>/dev/null)" \
    || error "Falta el output snowflake_s3_role_arn de infra/aws. Corre primero: cd $ROOT_DIR && make deploy"
  lake="$(terraform -chdir="$ROOT_DIR/infra/aws" output -raw lake_bucket 2>/dev/null)" \
    || error "Falta el output lake_bucket de infra/aws. Corre primero: cd $ROOT_DIR && make deploy"
  cat > "$TFVARS" <<EOF
# Generado por scripts/snowflake-preparar.sh. La llave privada NO va aquí.
organization_name = "$org"
account_name      = "$cuenta"
user              = "TERRAFORM_SVC"
s3_role_arn       = "$rol_s3"
lake_bucket       = "$lake"
dev_users         = ["$usuario"]
EOF
fi

if [[ ! -f "$BACKEND" ]]; then
  msg "Escribiendo $BACKEND"
  cat > "$BACKEND" <<EOF
bucket       = "$(tfstate_bucket)"
key          = "snowflake/terraform.tfstate"
region       = "$AWS_REGION"
encrypt      = true
use_lockfile = true
EOF
fi

msg "Snowflake listo para Terraform:"
grep -E '^(organization_name|account_name|lake_bucket|dev_users)' "$TFVARS" | sed 's/^/    /'
