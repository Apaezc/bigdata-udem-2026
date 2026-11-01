#!/usr/bin/env bash
# PROTOTIPO: Airflow 3.3.2 dentro del Code Editor (sin VM ni Docker), para evaluar si reemplaza la VM.
# Uso: airflow-local.sh up | down | estado
#   up     instala (solo la primera vez), levanta nginx en 8080 y `airflow standalone` en 8081
#   down   detiene Airflow y nginx
#   estado procesos, memoria y salud
# UI: https://<id-del-space>.studio.<region>.sagemaker.aws/codeeditor/default/ports/8080/
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BASE="$HOME/.airflow-local"
VENV="$BASE/venv"
export AIRFLOW_HOME="$BASE/home"
NGINX_CONF="$BASE/nginx.conf"
PREFIJO="/codeeditor/default/ports/8080/"
AIRFLOW_VERSION="3.3.2"

instalar() {
  mkdir -p "$BASE" "$AIRFLOW_HOME"
  if ! command -v nginx >/dev/null; then
    msg "Instalando nginx (paquete del sistema; se pierde al reiniciar el space)"
    sudo apt-get update -qq && sudo apt-get install -y -qq nginx >/dev/null
  fi
  if [[ ! -x "$VENV/bin/airflow" ]]; then
    msg "Instalando Airflow $AIRFLOW_VERSION en $VENV (unos minutos, solo la primera vez)"
    python3 -m venv "$VENV"
    local py constraints
    py="$("$VENV/bin/python" -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
    constraints="https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_VERSION}/constraints-${py}.txt"
    "$VENV/bin/pip" install --quiet --upgrade pip
    "$VENV/bin/pip" install --quiet --constraint "$constraints" \
      "apache-airflow==$AIRFLOW_VERSION" \
      apache-airflow-providers-amazon \
      apache-airflow-providers-snowflake \
      apache-airflow-providers-common-sql \
      apache-airflow-providers-standard
  fi
}

escribir_nginx() {
  # Misma lógica que proxy-studio en la VM: el proxy de Studio quita el prefijo y rechaza %2F.
  cat > "$NGINX_CONF" <<EOF
worker_processes 1;
pid $BASE/nginx.pid;
error_log $BASE/nginx-error.log;
events { worker_connections 256; }
http {
  access_log $BASE/nginx-access.log;
  client_body_temp_path $BASE/nginx-tmp/body;
  proxy_temp_path $BASE/nginx-tmp/proxy;
  fastcgi_temp_path $BASE/nginx-tmp/fastcgi;
  uwsgi_temp_path $BASE/nginx-tmp/uwsgi;
  scgi_temp_path $BASE/nginx-tmp/scgi;
  map \$upstream_http_location \$location_sin_next {
    ~^(https?://[^/]+)?(?<base>[^?]*)(\\?next=[^&]*)?\$ \$base;
    default \$upstream_http_location;
  }
  server {
    listen 127.0.0.1:8080;
    absolute_redirect off;
    proxy_set_header Host \$host;
    proxy_hide_header Location;
    add_header Location \$location_sin_next always;
    # Redirección al login relativa: el proxy de Studio antepone /ports/<puerto> a las rutas absolutas.
    location = /api/v2/auth/login { return 307 ../../../auth/login; }
    location $PREFIJO { proxy_pass http://127.0.0.1:8081; }
    location / { proxy_pass http://127.0.0.1:8081$PREFIJO; }
  }
}
EOF
  mkdir -p "$BASE/nginx-tmp"
}

entorno_airflow() {
  # standalone lanza sus componentes como subprocesos `airflow`: el venv debe estar en el PATH.
  export PATH="$VENV/bin:$PATH"
  export AIRFLOW__CORE__DAGS_FOLDER="$ROOT_DIR/airflow/dags"
  export PYTHONPATH="$ROOT_DIR/airflow"
  export AIRFLOW__CORE__LOAD_EXAMPLES=false
  export AIRFLOW__API__PORT=8081
  export AIRFLOW__API__BASE_URL="http://localhost:8080$PREFIJO"
  export AIRFLOW__CORE__EXECUTION_API_SERVER_URL="http://127.0.0.1:8081${PREFIJO}execution/"
  export AIRFLOW__CORE__SIMPLE_AUTH_MANAGER_USERS="admin:admin"
  export AIRFLOW_CONN_AWS_DEFAULT="{\"conn_type\": \"aws\", \"extra\": {\"region_name\": \"$AWS_REGION\"}}"
  export AWS_DEFAULT_REGION="$AWS_REGION"
  export AIRFLOW_VAR_PREFIX="$PREFIX"
  # Conexión snowflake_default desde el secreto <prefix>/snowflake (igual que en la VM).
  local snow
  snow="$(aws secretsmanager get-secret-value --secret-id "$PREFIX/snowflake" \
    --query SecretString --output text 2>/dev/null || true)"
  if [[ -n "$snow" ]] && jq -e '.conn_type' >/dev/null 2>&1 <<< "$snow"; then
    export AIRFLOW_CONN_SNOWFLAKE_DEFAULT="$snow"
  else
    aviso "Sin conexión snowflake_default (secreto $PREFIX/snowflake vacío o inválido): cargar_gold fallará."
  fi
}

up() {
  requerir python3 aws jq
  instalar
  escribir_nginx
  if [[ -f "$BASE/nginx.pid" ]] && kill -0 "$(cat "$BASE/nginx.pid")" 2>/dev/null; then
    nginx -p "$BASE" -e "$BASE/nginx-error.log" -c "$NGINX_CONF" -s reload
  else
    nginx -p "$BASE" -e "$BASE/nginx-error.log" -c "$NGINX_CONF"
  fi
  if pgrep -f "airflow standalone" >/dev/null; then
    msg "Airflow ya está corriendo."
  else
    entorno_airflow
    msg "Arrancando airflow standalone (log: $BASE/airflow.log)"
    nohup "$VENV/bin/airflow" standalone > "$BASE/airflow.log" 2>&1 &
    for _ in $(seq 1 60); do
      curl -sf -o /dev/null "http://127.0.0.1:8081${PREFIJO}api/v2/monitor/health" && break
      sleep 3
    done
  fi
  estado
  local pw="$AIRFLOW_HOME/simple_auth_manager_passwords.json.generated"
  [[ -f "$pw" ]] && echo "Usuario: admin  Contraseña: $(jq -r '.admin' "$pw")"
  echo "UI: https://<id-del-space>.studio.${AWS_REGION}.sagemaker.aws${PREFIJO}"
}

down() {
  pkill -f "airflow standalone" 2>/dev/null || true
  pkill -f "$VENV/bin/airflow" 2>/dev/null || true
  [[ -f "$BASE/nginx.pid" ]] && nginx -p "$BASE" -e "$BASE/nginx-error.log" -c "$NGINX_CONF" -s stop 2>/dev/null || true
  msg "Airflow local y nginx detenidos."
}

estado() {
  msg "Salud"
  curl -s "http://127.0.0.1:8080/api/v2/monitor/health" | jq -c '{metadatabase: .metadatabase.status, scheduler: .scheduler.status, triggerer: .triggerer.status, dag_processor: .dag_processor.status}' 2>/dev/null \
    || echo "Airflow no responde en 8080"
  msg "Memoria"
  free -m | awk 'NR<=2'
  echo "Airflow (RSS total MB): $(ps -eo rss,cmd | grep -E '[a]irflow' | awk '{s+=$1} END {print int(s/1024)}')"
}

case "${1:-}" in
  up) up ;;
  down) down ;;
  estado) estado ;;
  *) error "Uso: airflow-local.sh up|down|estado" ;;
esac
