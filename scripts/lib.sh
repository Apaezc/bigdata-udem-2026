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
# Secretos de conexión a Snowflake: dev (rol BIGDATA_DEV) y prod (rol BIGDATA_PROD, solo lo lee la VM
# de prod y los jobs de Glue que lanza). Los usan snowflake*.sh y la VM (refresh.env).
export SECRETO_SNOWFLAKE="${PREFIX}/snowflake"
export SECRETO_SNOWFLAKE_PROD="${PREFIX}/snowflake_prod"
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

# Entorno virtual del proyecto: siempre con Python 3.12. Los notebooks de la clase 5 y PySpark 3.5
# lo necesitan, y no se puede depender de 'python3' del sistema: SageMaker actualiza la imagen del
# Code Editor y /opt/conda/bin/python3 cambia de versión (pasó de 3.12 a 3.13).
VENV_PYTHON_VERSION="3.12"
VENV_DIR="$ROOT_DIR/.venv"

buscar_uv() {
  # Imprime la ruta de uv (en el PATH o en conda) o sale con 1 si no existe.
  if command -v uv >/dev/null 2>&1; then
    command -v uv
  elif [[ -x /opt/conda/bin/uv ]]; then
    echo /opt/conda/bin/uv
  else
    return 1
  fi
}

venv_sano() {
  # 0 si .venv existe, es Python 3.12 y puede importar pip y pyspark; 1 en cualquier otro caso
  # (por ejemplo, cuando su Python era un enlace a conda y conda cambió de versión).
  local py="$VENV_DIR/bin/python"
  [[ -x "$py" ]] || return 1
  "$py" -c "
import sys
import pip
import pyspark
sys.exit(0 if sys.version_info[:2] == (3, 12) else 1)
" >/dev/null 2>&1
}

crear_venv() {
  # Borra .venv y lo crea de nuevo con Python 3.12: con uv si existe y, si no, con python3.12.
  local uv_bin=""
  uv_bin="$(buscar_uv)" || uv_bin=""
  rm -rf "$VENV_DIR"
  if [[ -n "$uv_bin" ]]; then
    msg "Creando .venv con Python $VENV_PYTHON_VERSION (uv)"
    "$uv_bin" venv --seed --python "$VENV_PYTHON_VERSION" "$VENV_DIR"
  elif command -v "python$VENV_PYTHON_VERSION" >/dev/null 2>&1; then
    msg "Creando .venv con python$VENV_PYTHON_VERSION (no hay uv)"
    "python$VENV_PYTHON_VERSION" -m venv "$VENV_DIR"
  else
    error "No hay uv ni python$VENV_PYTHON_VERSION para crear .venv. Instala uv (https://docs.astral.sh/uv/) o Python $VENV_PYTHON_VERSION y repite."
  fi
  export PATH="$VENV_DIR/bin:$PATH"
}

instalar_dependencias_venv() {
  # Instala requirements-dev.txt en .venv (con uv si existe; si no, con pip).
  local requisitos="$ROOT_DIR/requirements-dev.txt" uv_bin=""
  if [[ ! -f "$requisitos" ]]; then
    aviso "No existe requirements-dev.txt; se omite la instalación de dependencias."
    return 0
  fi
  uv_bin="$(buscar_uv)" || uv_bin=""
  msg "Instalando dependencias de requirements-dev.txt"
  if [[ -n "$uv_bin" ]]; then
    "$uv_bin" pip install --quiet --python "$VENV_DIR/bin/python" -r "$requisitos"
  else
    "$VENV_DIR/bin/python" -m pip install --quiet --upgrade pip
    "$VENV_DIR/bin/python" -m pip install --quiet -r "$requisitos"
  fi
}

registrar_kernel() {
  # Registra .venv como el kernel de Jupyter «Python (bigdata)».
  msg "Registrando el kernel «Python (bigdata)»"
  "$VENV_DIR/bin/python" -m ipykernel install --user --name bigdata --display-name "Python (bigdata)" >/dev/null
}

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

export CUENTA_AWS=""
exigir_cuenta() {
  # Verifica la cuenta AWS real antes de cambiar infraestructura. Guarda el ID en CUENTA_AWS.
  local real
  real="$(account_id 2>/dev/null || true)"
  if [[ -z "$real" || "$real" == "None" ]]; then
    error "No hay credenciales AWS válidas (aws sts get-caller-identity falló). Define AWS_PROFILE con un perfil válido (en Code Editor no hace falta)."
  fi
  if [[ -n "${AWS_ACCOUNT_ID:-}" && "$AWS_ACCOUNT_ID" != "$real" ]]; then
    error "AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID no coincide con la cuenta real $real. Corrige el entorno (o .env) o usa AWS_PROFILE correcto."
  fi
  CUENTA_AWS="$real"
  msg "Cuenta AWS: $real · región: $AWS_REGION · perfil: ${AWS_PROFILE:-por defecto}"
}

lake_bucket() {
  echo "${PREFIX}-lake-$(account_id)-${AWS_REGION}"
}

# --- Rutas del lake ---------------------------------------------------------------------------
# Misma regla que ruta_lake (src/pipeline/herramientas/rutas.py): s3://<lake>/<entorno>/<capa>/<tabla>/...
# dev y prod no comparten ningún prefijo. code/, dags/, logs/ y tmp/ son del lake, no de un entorno.
ENTORNOS_LAKE="dev prod"
CAPAS_LAKE="bronze silver gold"
PREFIJOS_ANTIGUOS_LAKE="bronze muestra silver gold"  # diseño anterior: en la raíz del bucket

s3_tiene_objetos() {
  # Uso: s3_tiene_objetos <bucket> <prefijo>. Éxito si hay al menos un objeto bajo el prefijo.
  local cuantos
  cuantos="$(aws s3api list-objects-v2 --bucket "$1" --prefix "$2" --max-keys 1 \
    --query 'KeyCount' --output text 2>/dev/null || echo 0)"
  [[ "$cuantos" != "0" && "$cuantos" != "None" ]]
}

mostrar_rutas_del_lake() {
  # Uso: mostrar_rutas_del_lake [con-estado]. Imprime el bucket y la carpeta de cada capa por
  # entorno; con "con-estado" dice si la carpeta ya tiene datos (una consulta a S3 por carpeta).
  local lake entorno capa estado
  lake="$(lake_bucket)"
  echo "  Bucket del lake: $lake"
  for entorno in $ENTORNOS_LAKE; do
    for capa in $CAPAS_LAKE; do
      estado=""
      if [[ "${1:-}" == "con-estado" ]]; then
        if s3_tiene_objetos "$lake" "$entorno/$capa/"; then estado="con datos"; else estado="vacía"; fi
      fi
      printf "  s3://%s/%s/%s/  %s\n" "$lake" "$entorno" "$capa" "$estado"
    done
  done
  echo "  Del lake, no de un entorno: code/  dags/  logs/  tmp/"
}

avisar_rutas_antiguas_del_lake() {
  # Uso: avisar_rutas_antiguas_del_lake. Avisa si en la raíz del bucket quedan carpetas del diseño
  # anterior (bronze/, muestra/...). Devuelve 1 si encontró alguna.
  local lake prefijo encontradas=""
  lake="$(lake_bucket)"
  for prefijo in $PREFIJOS_ANTIGUOS_LAKE; do
    if s3_tiene_objetos "$lake" "$prefijo/"; then
      encontradas="$encontradas s3://$lake/$prefijo/"
    fi
  done
  [[ -z "$encontradas" ]] && return 0
  aviso "Quedan carpetas del diseño anterior:$encontradas"
  aviso "Ya nadie las lee. Cómo moverlas o borrarlas: docs/rutas_del_lake.md"
  return 1
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

conexion_snowflake_json() {
  # Uso: conexion_snowflake_json <login> <account> <warehouse> <database> <role> <archivo-llave-privada>
  # Imprime (en una línea) el JSON de conexión de Airflow para snowflake_default con key pair:
  # el formato que leen airflow-local.sh y airflow-refresh.sh (user_data de la VM) y que
  # apache-airflow-providers-snowflake 6.x entiende (login + extra.account/warehouse/database/role
  # + extra.private_key_content con el PEM). La llave se lee del archivo, nunca de argumentos.
  [[ $# -eq 6 ]] || error "conexion_snowflake_json: se esperan 6 argumentos."
  [[ -s "$6" ]] || error "conexion_snowflake_json: no existe o está vacía la llave $6."
  jq -cn --arg login "$1" --arg account "$2" --arg warehouse "$3" --arg database "$4" --arg role "$5" \
    --rawfile key "$6" \
    '{conn_type: "snowflake", login: $login,
      extra: {account: $account, warehouse: $warehouse, database: $database, role: $role,
              private_key_content: $key}}'
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

url_airflow_studio() {
  # Imprime la URL del Airflow (puerto 8080) a través del proxy del Code Editor. Lee el dominio y el
  # Space de los metadatos de SageMaker y pide su URL con DescribeSpace; si no se puede (fuera del
  # Code Editor o sin permiso), imprime la plantilla con <id-del-space>.
  local meta=/opt/ml/metadata/resource-metadata.json base="" dominio espacio
  if [[ -f "$meta" ]] && command -v jq >/dev/null 2>&1; then
    dominio="$(jq -r '.DomainId // empty' "$meta")"
    espacio="$(jq -r '.SpaceName // empty' "$meta")"
    if [[ -n "$dominio" && -n "$espacio" ]]; then
      base="$(aws sagemaker describe-space --domain-id "$dominio" --space-name "$espacio" \
        --query Url --output text 2>/dev/null | grep -oE '^https://[^/]+' || true)"
    fi
  fi
  echo "${base:-https://<id-del-space>.studio.${AWS_REGION}.sagemaker.aws}/codeeditor/default/ports/8080/"
}
