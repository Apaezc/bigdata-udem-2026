#!/usr/bin/env bash
# Escribe en el secreto <prefix>/snowflake de Secrets Manager la conexión snowflake_default de Airflow
# (usuario AIRFLOW_SVC + su llave privada). Lo usan el Airflow de dev (airflow-local.sh) y el de prod
# (la VM, airflow-refresh.sh). `make snowflake` lo ejecuta solo; se puede repetir cuando quieras.
# El secreto lo crea Terraform (infra/aws, `make deploy`); aquí solo se escribe su valor.
# No imprime la llave ni el JSON.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

requerir aws terraform jq
SF_DIR="$ROOT_DIR/infra/snowflake"
LLAVE="${AIRFLOW_KEY:-$HOME/.snowflake/keys/airflow_svc_rsa_key.p8}"
SECRETO="$PREFIX/snowflake"

[[ -s "$LLAVE" ]] || error "Falta la llave de AIRFLOW_SVC ($LLAVE). Corre 'make snowflake': la genera y registra el usuario."

CONEXION="$(terraform -chdir="$SF_DIR" output -json airflow_conexion 2>/dev/null || true)"
jq -e 'type == "object"' >/dev/null 2>&1 <<< "$CONEXION" \
  || error "infra/snowflake no tiene el output airflow_conexion. Corre 'make snowflake' (crea AIRFLOW_SVC)."

campo() { jq -r --arg k "$1" '.[$k] // empty' <<< "$CONEXION"; }
NUEVO="$(conexion_snowflake_json "$(campo login)" "$(campo account)" "$(campo warehouse)" \
  "$(campo database)" "$(campo role)" "$LLAVE")"
# La VM descarta el secreto si el JSON trae una comilla simple (lo mete entre comillas simples en snowflake.env).
[[ "$NUEVO" != *"'"* ]] || error "El JSON de conexión contiene una comilla simple; no se puede usar en la VM."

aws secretsmanager describe-secret --secret-id "$SECRETO" >/dev/null 2>&1 \
  || error "No existe el secreto $SECRETO. Lo crea Terraform: corre 'make deploy' (o 'make snowflake' sin SIN_DEPLOY) y repite."

ACTUAL="$(aws secretsmanager get-secret-value --secret-id "$SECRETO" --query SecretString --output text 2>/dev/null || true)"
if [[ "$ACTUAL" == "$NUEVO" ]]; then
  msg "El secreto $SECRETO ya tiene la conexión de AIRFLOW_SVC."
  exit 0
fi

# El valor viaja por un archivo temporal 600 (no por argumentos, que se ven en `ps`).
(
  umask 077
  TMP="$(mktemp)"
  trap 'rm -f "$TMP"' EXIT
  printf '%s' "$NUEVO" > "$TMP"
  aws secretsmanager put-secret-value --secret-id "$SECRETO" --secret-string "file://$TMP" >/dev/null
)
msg "Conexión de AIRFLOW_SVC guardada en el secreto $SECRETO."
echo "Si Airflow ya estaba encendido: 'make airflow-local-down && make airflow-local' (dev) y 'make airflow-off && make airflow-on' (prod)."
