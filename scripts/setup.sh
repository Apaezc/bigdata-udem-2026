#!/usr/bin/env bash
# Verifica herramientas, valida la región de Snowflake, alinea AWS_REGION (.env) y crea la
# configuración de AWS en S3 (config/aws.tfvars) si todavía no existe.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

msg "Verificando herramientas"
requerir python3 aws terraform snow jq zip

python3 -c 'import sys; sys.exit(0 if sys.version_info[:2] >= (3, 11) else 1)' \
  || error "Se requiere Python 3.11 o superior (python3 --version)."

if ! java -version 2>&1 | head -1 | grep -q '"17'; then
  aviso "Se recomienda Java 17 para PySpark 3.5 (java -version)."
fi

if ! command -v session-manager-plugin >/dev/null 2>&1; then
  aviso "session-manager-plugin no está instalado; 'make airflow-tunel' no funcionará."
fi

msg "Entorno virtual y dependencias de desarrollo"
if [[ ! -d "$ROOT_DIR/.venv" ]]; then
  python3 -m venv "$ROOT_DIR/.venv"
fi
if [[ -f "$ROOT_DIR/requirements-dev.txt" ]]; then
  "$ROOT_DIR/.venv/bin/python" -m pip install --quiet --upgrade pip
  "$ROOT_DIR/.venv/bin/python" -m pip install --quiet -r "$ROOT_DIR/requirements-dev.txt"
else
  aviso "No existe requirements-dev.txt; se omite la instalación de dependencias."
fi

msg "Validando región de Snowflake (snow sql)"
consultar_region_snow() {
  SNOW_OUT="$(snow sql -q "select current_region()" 2>&1)"
}
if ! consultar_region_snow; then
  aviso "No se pudo consultar Snowflake: $SNOW_OUT"
  RESPUESTA_CONEXION=n
  if [[ -t 0 ]]; then
    read -r -p "¿Configurar la conexión de snow ahora? [s/N]: " RESPUESTA_CONEXION
  fi
  [[ "$RESPUESTA_CONEXION" =~ ^[sS]$ ]] \
    || error "Configura la conexión con: make snowflake-conexion"
  bash "$ROOT_DIR/scripts/snowflake-conexion.sh"
  consultar_region_snow \
    || error "Snowflake sigue sin responder tras configurar la conexión. Revisa con 'make doctor'."
fi

SNOW_REGION="$(grep -oE '[A-Z]+_[A-Z0-9_]+' <<< "$SNOW_OUT" | grep -E '^(AWS|AZURE|GCP)_' | head -1 || true)"
[[ -n "$SNOW_REGION" ]] || error "No se pudo leer la región de Snowflake. Salida:\n$SNOW_OUT"
if [[ "$SNOW_REGION" != AWS_* ]]; then
  error "La cuenta de Snowflake está en '$SNOW_REGION'. Debe estar en AWS_* para usar el bucket S3 de este template."
fi

REGION_DESDE_SNOW="$(sed -e 's/^AWS_//' -e 's/_/-/g' <<< "$SNOW_REGION" | tr "[:upper:]" "[:lower:]")"
msg "Región de Snowflake: $SNOW_REGION -> $REGION_DESDE_SNOW"

if [[ "$REGION_DESDE_SNOW" != "$AWS_REGION" ]]; then
  aviso "AWS_REGION ($AWS_REGION) difiere de la región de Snowflake; se alinea a $REGION_DESDE_SNOW."
  AWS_REGION="$REGION_DESDE_SNOW"
fi

set_env_var PREFIX "$PREFIX"
set_env_var AWS_REGION "$AWS_REGION"
msg "Configuración guardada en .env (PREFIX=$PREFIX, AWS_REGION=$AWS_REGION)"

# Configuración de Terraform (infra/aws) en S3: fuente única de verdad. Si ya existe no se toca.
msg "Configuración de AWS en S3 ($(config_uri))"
if config_existe; then
  msg "Ya existe; no se modifica. Revísala con 'make config'."
else
  if [[ -z "${ALERT_EMAIL:-}" && -t 0 ]]; then
    read -r -p "Correo para las alertas de presupuesto (alert_email): " ALERT_EMAIL
  fi
  [[ -n "${ALERT_EMAIL:-}" ]] || error "Falta el correo de alertas. Ejecuta 'make setup' desde una terminal interactiva."
  [[ "$ALERT_EMAIL" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] || error "El correo de alertas no es válido: $ALERT_EMAIL"

  CONFIG_TMP="$(mktemp)"
  cat > "$CONFIG_TMP" <<EOF
# Configuración de infra/aws (fuente única de verdad). Ver 'make config' y CONTRATO.md.
prefix         = "$PREFIX"
aws_region     = "$AWS_REGION"
alert_email    = "$ALERT_EMAIL"
enable_glue    = true
enable_airflow = false
EOF
  config_push "$CONFIG_TMP"
  rm -f "$CONFIG_TMP"
  msg "Configuración creada en S3 (enable_glue=true, enable_airflow=false)."
fi
# Secrets del fork (AWS_ROLE_ARN, TF_STATE_BUCKET) desde los outputs del bootstrap.
if gh auth status >/dev/null 2>&1; then
  bash "$ROOT_DIR/scripts/secrets.sh" || aviso "No se pudieron cargar los secrets; reintenta con 'make secrets'."
else
  aviso "Falta autenticar gh para cargar los secrets del fork: 'gh auth login --web' y luego 'make secrets'."
fi
msg "Setup completado. Siguiente paso: make doctor"
