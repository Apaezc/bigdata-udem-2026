#!/usr/bin/env bash
# Escribe en Secrets Manager las dos conexiones snowflake_default de Airflow (JSON de conexión con la
# llave privada del usuario de servicio):
#   <prefix>/snowflake        AIRFLOW_SVC       rol BIGDATA_DEV   (Airflow del Code Editor y Glue en dev)
#   <prefix>/snowflake_prod   AIRFLOW_PROD_SVC  rol BIGDATA_PROD   (la VM y Glue en prod)
# `make snowflake` lo ejecuta solo; se puede repetir cuando quieras.
# Los secretos los crea Terraform (infra/aws, `make deploy`); aquí solo se escribe su valor.
# No imprime la llave ni el JSON.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

requerir aws terraform jq
SF_DIR="$ROOT_DIR/infra/snowflake"
SECRETO_SNOWFLAKE_PROD="${SECRETO_SNOWFLAKE_PROD:-$PREFIX/snowflake_prod}" # lo define lib.sh (P7); respaldo local

# Uso: escribir_secreto <usuario> <llave.p8> <output-de-terraform> <secreto>
escribir_secreto() {
  local usuario="$1" llave="$2" salida="$3" secreto="$4"
  [[ -s "$llave" ]] || error "Falta la llave de $usuario ($llave). Corre 'make snowflake': la genera y registra el usuario."

  local conexion
  conexion="$(terraform -chdir="$SF_DIR" output -json "$salida" 2>/dev/null || true)"
  jq -e 'type == "object"' >/dev/null 2>&1 <<< "$conexion" \
    || error "infra/snowflake no tiene el output $salida. Corre 'make snowflake' (crea $usuario)."

  campo() { jq -r --arg k "$1" '.[$k] // empty' <<< "$conexion"; }
  local nuevo
  nuevo="$(conexion_snowflake_json "$(campo login)" "$(campo account)" "$(campo warehouse)" \
    "$(campo database)" "$(campo role)" "$llave")"
  # La VM descarta el secreto si el JSON trae una comilla simple (lo mete entre comillas simples en snowflake.env).
  [[ "$nuevo" != *"'"* ]] || error "El JSON de conexión de $usuario contiene una comilla simple; no se puede usar en la VM."

  aws secretsmanager describe-secret --secret-id "$secreto" >/dev/null 2>&1 \
    || error "No existe el secreto $secreto. Lo crea Terraform: corre 'make deploy' (o 'make snowflake' sin SIN_DEPLOY) y repite."

  local actual
  actual="$(aws secretsmanager get-secret-value --secret-id "$secreto" --query SecretString --output text 2>/dev/null || true)"
  if [[ "$actual" == "$nuevo" ]]; then
    msg "El secreto $secreto ya tiene la conexión de $usuario."
    return 0
  fi

  # El valor viaja por un archivo temporal 600 (no por argumentos, que se ven en `ps`).
  (
    umask 077
    TMP="$(mktemp)"
    trap 'rm -f "$TMP"' EXIT
    printf '%s' "$nuevo" > "$TMP"
    aws secretsmanager put-secret-value --secret-id "$secreto" --secret-string "file://$TMP" >/dev/null
  )
  msg "Conexión de $usuario guardada en el secreto $secreto."
}

escribir_secreto AIRFLOW_SVC "${AIRFLOW_KEY:-$HOME/.snowflake/keys/airflow_svc_rsa_key.p8}" \
  airflow_conexion "$PREFIX/snowflake"
escribir_secreto AIRFLOW_PROD_SVC "${AIRFLOW_PROD_KEY:-$HOME/.snowflake/keys/airflow_prod_svc_rsa_key.p8}" \
  airflow_prod_conexion "$SECRETO_SNOWFLAKE_PROD"

echo "Si Airflow ya estaba encendido: 'make airflow-local-down && make airflow-local' (dev) y 'make airflow-off && make airflow-on' (prod)."
