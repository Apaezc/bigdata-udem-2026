#!/usr/bin/env bash
# Destruye los recursos del curso. Requiere confirmación escrita.
#
# Orden: 1) vaciar el bucket del lake  2) terraform destroy de infra/snowflake
#        3) terraform destroy de infra/aws  4) (opcional) borrar el stack de bootstrap
#        y el bucket de state versionado.
#
# El paso 4 solo corre si respondes la segunda confirmación (o con INCLUIR_BOOTSTRAP=si).
# Borrar el bootstrap elimina el dominio de SageMaker: si ejecutas el script desde el Code
# Editor, la sesión desaparece al final. Para el paso 4 conviene usar una terminal local o
# CloudShell con credenciales de administrador.
#
# Snowflake necesita infra/snowflake/terraform.tfvars (organization_name, account_name) y la
# llave privada (KEY, por defecto ~/.snowflake/keys/terraform_svc_rsa_key.p8).
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

requerir aws terraform jq
BUCKET_ESTADO="$(tfstate_bucket)"
LAKE="$(lake_bucket)"
STACK="${BOOTSTRAP_STACK:-${PREFIX}-bootstrap}"
KEY="${KEY:-$HOME/.snowflake/keys/terraform_svc_rsa_key.p8}"

vaciar_bucket_versionado() {
  # Borra todas las versiones y marcadores de borrado (bucket de state versionado).
  local bucket="$1" lote cuantos
  while :; do
    lote="$(aws s3api list-object-versions --bucket "$bucket" --max-items 500 --output json 2>/dev/null \
      | jq -c '{Objects: ([(.Versions // [])[], (.DeleteMarkers // [])[]] | map({Key: .Key, VersionId: .VersionId})), Quiet: true}' \
      2>/dev/null || true)"
    [[ -n "$lote" ]] || break
    cuantos="$(jq '.Objects | length' <<< "$lote")"
    [[ "$cuantos" != "0" ]] || break
    aws s3api delete-objects --bucket "$bucket" --delete "$lote" >/dev/null
  done
}

echo "ATENCIÓN: esto destruirá los recursos del prefijo '${PREFIX}' en AWS y Snowflake:"
echo "  - bucket del lake s3://${LAKE} (se vacía: bronze, silver, gold, code, dags, logs, tmp)"
echo "  - infra/snowflake (warehouse, base de datos, rol, integración de almacenamiento)"
echo "  - infra/aws (Glue, Athena, VM de Airflow, roles, secretos, presupuesto)"
echo "El stack de bootstrap y el bucket de state se tocan solo si lo confirmas después."
confirmar "Se destruirán los recursos del prefijo ${PREFIX} (estado en $BUCKET_ESTADO)." "destruir ${PREFIX}"

# --- 1) Vaciar el lake (sin versionado; force_destroy de Terraform queda como respaldo) ---
if aws s3api head-bucket --bucket "$LAKE" >/dev/null 2>&1; then
  msg "Vaciando s3://$LAKE"
  aws s3 rm "s3://$LAKE" --recursive --only-show-errors
else
  msg "El bucket $LAKE no existe; se omite."
fi

# --- 2) Snowflake primero: depende del rol/bucket de AWS (integración y stage) ---
SF_DIR="$ROOT_DIR/infra/snowflake"
if [[ ! -f "$SF_DIR/terraform.tfvars" ]]; then
  aviso "No existe infra/snowflake/terraform.tfvars: se omite el destroy de Snowflake (créalo desde terraform.tfvars.example y repite si quieres borrarlo)."
elif [[ ! -f "$KEY" ]]; then
  aviso "No existe la llave privada $KEY: se omite el destroy de Snowflake (define KEY=/ruta/llave.p8)."
else
  msg "Terraform destroy: infra/snowflake"
  cd "$SF_DIR" || exit 1
  terraform init -input=false -backend-config="bucket=$BUCKET_ESTADO" \
    -backend-config="key=snowflake/terraform.tfstate" -backend-config="region=$AWS_REGION" \
    -backend-config="use_lockfile=true"
  TF_VAR_private_key="$(cat "$KEY")" terraform destroy -input=false -auto-approve \
    -var "lake_bucket=$LAKE" -var "s3_role_arn=arn:aws:iam::$(account_id):role/${PREFIX}-snowflake-s3"
fi

# --- 3) AWS ---
# destroy no usa estos valores, pero Terraform exige alert_email.
export TF_VAR_alert_email="${ALERT_EMAIL:-destroy@example.com}"
msg "Terraform destroy: infra/aws"
cd "$ROOT_DIR/infra/aws" || exit 1
terraform init -input=false -backend-config="bucket=$BUCKET_ESTADO" \
  -backend-config="key=aws/terraform.tfstate" -backend-config="region=$AWS_REGION" \
  -backend-config="use_lockfile=true"
terraform destroy -input=false -auto-approve

msg "Recursos de Terraform destruidos."

# --- 4) Bootstrap (opcional) ---
BORRAR_BOOTSTRAP="no"
if [[ "${INCLUIR_BOOTSTRAP:-}" == "si" ]]; then
  BORRAR_BOOTSTRAP="si"
elif [[ -t 0 ]]; then
  read -r -p "¿Borrar también el stack '$STACK' y el bucket de state $BUCKET_ESTADO? (si/no): " resp
  [[ "$resp" == "si" ]] && BORRAR_BOOTSTRAP="si"
fi

if [[ "$BORRAR_BOOTSTRAP" != "si" ]]; then
  msg "Destrucción terminada. El stack de bootstrap sigue desplegado (bórralo desde CloudFormation o repite con INCLUIR_BOOTSTRAP=si)."
  exit 0
fi

confirmar "Se borrará el stack $STACK (SageMaker, OIDC, roles, presupuesto) y el bucket $BUCKET_ESTADO con TODO el historial de state." "borrar bootstrap ${PREFIX}"

msg "Borrando el stack $STACK (puede tardar varios minutos)"
aws cloudformation delete-stack --stack-name "$STACK"
aws cloudformation wait stack-delete-complete --stack-name "$STACK" \
  || error "El borrado del stack falló. Revisa CloudFormation (DomainCleanup) y repite."

if aws s3api head-bucket --bucket "$BUCKET_ESTADO" >/dev/null 2>&1; then
  msg "Vaciando y borrando el bucket de state $BUCKET_ESTADO"
  vaciar_bucket_versionado "$BUCKET_ESTADO"
  aws s3api delete-bucket --bucket "$BUCKET_ESTADO"
fi

msg "Destrucción completa. Quedan fuera de AWS: usuario y rol TERRAFORM_* y BIGDATA_RM en Snowflake (bootstrap/snowflake/01_admin.sql)."
