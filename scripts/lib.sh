#!/usr/bin/env bash
# Funciones y variables comunes para los scripts de scripts/ (Makefile y workflows).
# Compatible con bash 3.2 (macOS): sin mapfile, sin ${var,,}, sin arrays vacíos con set -u.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Configuración local (.env, no versionado). Lo que ya esté en el entorno tiene prioridad.
if [[ -f "$ROOT_DIR/.env" ]]; then
  while IFS='=' read -r _k _v; do
    if [[ "$_k" =~ ^[A-Z][A-Z0-9_]*$ && -z "${!_k:-}" ]]; then
      export "$_k=$_v"
    fi
  done < "$ROOT_DIR/.env"
  unset _k _v
fi

PREFIX="${PREFIX:-bigdata}"
AWS_REGION="${AWS_REGION:-us-east-2}"
export PREFIX AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"
export TF_VAR_prefix="$PREFIX"
export TF_VAR_aws_region="$AWS_REGION"

# Entorno virtual local (creado por 'make setup') tiene prioridad en el PATH.
if [[ -d "$ROOT_DIR/.venv/bin" ]]; then
  export PATH="$ROOT_DIR/.venv/bin:$PATH"
fi

msg() { echo "==> $*"; }
aviso() { echo "AVISO: $*" >&2; }
error() { echo "ERROR: $*" >&2; exit 1; }

requerir() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || error "Falta la herramienta '$cmd'. Instálala y vuelve a intentar (make setup)."
  done
}

confirmar() {
  # Uso: confirmar "<texto>" "<palabra exacta>"
  local texto="$1" palabra="$2" respuesta
  if [[ ! -t 0 ]]; then
    error "Se requiere confirmación interactiva. Ejecuta el comando desde una terminal."
  fi
  echo "$texto"
  read -r -p "Escribe '$palabra' para continuar: " respuesta
  [[ "$respuesta" == "$palabra" ]] || error "Cancelado: no se escribió '$palabra'."
}

set_env_var() {
  # Actualiza o agrega CLAVE=valor en .env (no versionado) sin tocar el resto.
  local clave="$1" valor="$2" archivo="$ROOT_DIR/.env" tmp
  touch "$archivo"
  tmp="$(mktemp)"
  grep -v "^${clave}=" "$archivo" > "$tmp" || true
  echo "${clave}=${valor}" >> "$tmp"
  mv "$tmp" "$archivo"
}

account_id() {
  aws sts get-caller-identity --query Account --output text
}

lake_bucket() {
  echo "${PREFIX}-lake-$(account_id)-${AWS_REGION}"
}

tfstate_bucket() {
  echo "${TF_STATE_BUCKET:-${PREFIX}-tfstate-$(account_id)-${AWS_REGION}}"
}

find_airflow_instance_id() {
  # Devuelve el ID de la instancia Airflow (no terminada) o cadena vacía.
  local ids
  ids="$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${PREFIX}-airflow" \
              "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null || true)"
  ids="$(echo "$ids" | tr '\t' '\n' | grep -v '^None$' | grep -v '^$' | head -1 || true)"
  echo "$ids"
}

instance_state() {
  aws ec2 describe-instances --instance-ids "$1" \
    --query 'Reservations[0].Instances[0].State.Name' --output text
}

# Configuración de infra/aws: fuente única de verdad en s3://<TF_STATE_BUCKET>/config/aws.tfvars
# (HCL, bucket de state con versionado). 'make setup' la crea; deploy.sh y deploy.yml la descargan
# con config_pull y la pasan con -var-file. Claves típicas: prefix, aws_region, alert_email,
# enable_glue, enable_airflow, snowflake_iam_user_arn, snowflake_external_id (ver CONTRATO.md).
CONFIG_S3_KEY="config/aws.tfvars"
CONFIG_LOCAL="$ROOT_DIR/infra/aws/config.auto.tfvars"

config_uri() {
  echo "s3://$(tfstate_bucket)/${CONFIG_S3_KEY}"
}

_config_copiar() {
  # Copia $1 a $2. Devuelve 0 si fue bien, 1 si el origen no existe, 2 en otro caso.
  local origen="$1" destino="$2" salida
  if salida="$(aws s3 cp "$origen" "$destino" --only-show-errors 2>&1)"; then
    return 0
  fi
  rm -f "$destino"
  if [[ "$salida" == *"Not Found"* || "$salida" == *"NoSuchKey"* || "$salida" == *"404"* ]]; then
    return 1
  fi
  echo "$salida" >&2
  return 2
}

_config_fallo() {
  # Termina con error según el código de _config_copiar ($1) para el origen $2.
  case "$1" in
    1) error "Falta la configuración en S3. Corre 'make setup' en Code Editor." ;;
    *) error "No se pudo leer la configuración en $2 (revisa credenciales y permisos)." ;;
  esac
}

config_existe() {
  # 0 si la configuración existe, 1 si no. Sale con error si no se puede comprobar
  # (así 'make setup' nunca sobrescribe una configuración que no pudo ver).
  local salida
  if salida="$(aws s3api head-object --bucket "$(tfstate_bucket)" --key "$CONFIG_S3_KEY" 2>&1)"; then
    return 0
  fi
  if [[ "$salida" == *"Not Found"* || "$salida" == *"404"* ]]; then
    return 1
  fi
  error "No se pudo comprobar la configuración en S3: $salida"
}

config_leer() {
  # Imprime el valor de la clave $1 en el archivo $2 (sin comillas ni comentario); vacío si no está.
  local clave="$1" archivo="$2" linea
  linea="$(grep -E "^[[:space:]]*${clave}[[:space:]]*=" "$archivo" | head -1 || true)"
  linea="${linea#*=}"
  linea="${linea%%#*}"
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' <<< "$linea"
}

config_pull() {
  # Descarga la configuración a $1 (por defecto infra/aws/config.auto.tfvars) y comprueba que
  # prefix, aws_region y alert_email existan y coincidan con el entorno.
  local destino="${1:-$CONFIG_LOCAL}" origen rc=0 valor
  origen="$(config_uri)"
  _config_copiar "$origen" "$destino" || rc=$?
  (( rc == 0 )) || _config_fallo "$rc" "$origen"

  valor="$(config_leer prefix "$destino")"
  [[ -z "$valor" || "$valor" == "$PREFIX" ]] \
    || error "La configuración en S3 tiene prefix = '$valor' y PREFIX = '$PREFIX'. Deben coincidir (revisa .env o vars.PREFIX)."
  valor="$(config_leer aws_region "$destino")"
  [[ -z "$valor" || "$valor" == "$AWS_REGION" ]] \
    || error "La configuración en S3 tiene aws_region = '$valor' y AWS_REGION = '$AWS_REGION'. Deben coincidir."
  [[ -n "$(config_leer alert_email "$destino")" ]] \
    || error "La configuración en S3 no tiene alert_email. Vuelve a crearla con 'make setup' o agrégala en $origen."
}

config_push() {
  # Sube el archivo $1 como configuración de AWS en S3 (reemplaza la versión actual).
  local archivo="$1" destino
  destino="$(config_uri)"
  aws s3 cp "$archivo" "$destino" --only-show-errors || error "No se pudo subir la configuración a $destino."
}

config_literal() {
  # Convierte un valor a literal HCL: true/false y enteros sin comillas; el resto entre comillas.
  local v="$1"
  if [[ "$v" == true || "$v" == false || "$v" =~ ^-?[0-9]+$ ]]; then
    echo "$v"
  else
    v="${v//\\/\\\\}"
    v="${v//\"/\\\"}"
    echo "\"$v\""
  fi
}

config_set() {
  # Uso: config_set clave valor. Actualiza (o agrega) la clave en la configuración de S3,
  # conserva las demás y sube el resultado.
  local clave="$1" valor="$2" origen tmp rc=0
  [[ "$clave" =~ ^[a-z][a-z0-9_]*$ ]] || error "Clave de configuración no válida: '$clave'."
  origen="$(config_uri)"
  tmp="$(mktemp)"
  _config_copiar "$origen" "$tmp" || rc=$?
  (( rc == 0 )) || _config_fallo "$rc" "$origen"

  LINEA="$clave = $(config_literal "$valor")" CLAVE="$clave" awk '
    BEGIN { re = "^[[:space:]]*" ENVIRON["CLAVE"] "[[:space:]]*=" }
    $0 ~ re { print ENVIRON["LINEA"]; hecho = 1; next }
    { print }
    END { if (!hecho) print ENVIRON["LINEA"] }
  ' "$tmp" > "$tmp.nuevo"
  mv "$tmp.nuevo" "$tmp"
  config_push "$tmp"
  rm -f "$tmp"
  msg "$clave actualizado en $origen"
}

guardia_destruccion() {
  # Uso: guardia_destruccion <archivo-plan>. Si el plan elimina o reemplaza recursos, aborta
  # salvo que CONFIRMAR_DESTRUCCION=true. Requiere estar en el directorio de infra/aws y jq.
  local plan="$1" lista cuantos
  lista="$(terraform show -json "$plan" | jq -r \
    '.resource_changes[]? | select((.change.actions // []) | index("delete")) | "  - \(.change.actions | join("+")): \(.address)"')" \
    || error "No se pudo leer el plan con 'terraform show -json'."
  if [[ -z "$lista" ]]; then
    msg "El plan no elimina recursos."
    return 0
  fi
  cuantos="$(printf '%s\n' "$lista" | wc -l | tr -d ' ')"
  echo "Recursos que el plan elimina o reemplaza ($cuantos):" >&2
  echo "$lista" >&2
  if [[ "${CONFIRMAR_DESTRUCCION:-}" == "true" ]]; then
    aviso "CONFIRMAR_DESTRUCCION=true: se aplicará la destrucción listada."
    return 0
  fi
  error "El plan destruye recursos. Si es intencional, repite con CONFIRMAR_DESTRUCCION=true (en deploy.yml: input confirmar_destruccion)."
}

stack_output() {
  # Uso: stack_output <OutputKey>. Salida del stack de bootstrap (vacío si no existe).
  local stack="${BOOTSTRAP_STACK:-${PREFIX}-bootstrap}"
  aws cloudformation describe-stacks --stack-name "$stack" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text 2>/dev/null || true
}

studio_console_url() {
  # Salida StudioConsoleUrl del stack de bootstrap (nombre por defecto ${PREFIX}-bootstrap).
  local stack="${BOOTSTRAP_STACK:-${PREFIX}-bootstrap}"
  aws cloudformation describe-stacks --stack-name "$stack" \
    --query "Stacks[0].Outputs[?OutputKey=='StudioConsoleUrl'].OutputValue" --output text 2>/dev/null || true
}
