#!/bin/bash
# Cuerpo del refresco de la VM de Airflow. Vive en el repo y "make deploy" lo sube a
# s3://<lake>/code/airflow/airflow-refresh.sh. La VM tiene un arranque mínimo
# (infra/aws/modules/airflow_vm/refresh-bootstrap.sh) que lo baja en cada ejecución: así un
# cambio aquí llega a las VMs que ya existen sin recrearlas ni repetir el user_data.
#
# Sin argumentos: refresco completo (antes de cada arranque de airflow.service).
# Con "sync": solo el código (DAGs, framework, pipeline); es lo que corre el cron cada minuto.
# No imprime secretos.
set -uo pipefail
source /opt/airflow/refresh.env   # REGION, LAKE, SNOWFLAKE_SECRET (los escribe el user_data)
export AWS_DEFAULT_REGION="$REGION"
AIRFLOW_HOME=/opt/airflow

sincronizar_codigo() {
  aws s3 sync "s3://$LAKE/dags/" "$AIRFLOW_HOME/dags" --delete \
    || echo "AVISO: no se pudieron sincronizar los DAGs"
  aws s3 sync "s3://$LAKE/code/airflow/framework/" "$AIRFLOW_HOME/framework/" --delete \
    || echo "AVISO: no se pudo sincronizar framework/"
  # pipeline/ es el paquete que importan las tareas (p. ej. cargar_gold).
  aws s3 sync "s3://$LAKE/code/airflow/pipeline/" "$AIRFLOW_HOME/pipeline/" --delete \
    || echo "AVISO: no se pudo sincronizar pipeline/"
  chown -R 50000:0 "$AIRFLOW_HOME/framework" "$AIRFLOW_HOME/pipeline" "$AIRFLOW_HOME/dags" 2>/dev/null || true
}

mkdir -p "$AIRFLOW_HOME/dags" "$AIRFLOW_HOME/framework" "$AIRFLOW_HOME/pipeline"

if [ "${1:-}" = "sync" ]; then
  sincronizar_codigo
  exit 0
fi

aws s3 cp "s3://$LAKE/code/airflow/docker-compose.yaml" "$AIRFLOW_HOME/docker-compose.yaml" \
  || echo "AVISO: no hay docker-compose.yaml en s3://$LAKE/code/airflow/ (ejecuta make deploy)"
sincronizar_codigo

# Conexion snowflake_default: el secreto guarda el JSON de la conexion de Airflow.
# Si esta vacio o no es valido, queda sin conexion (cargar_gold fallara hasta completarlo).
SNOW_JSON=$(aws secretsmanager get-secret-value --secret-id "$SNOWFLAKE_SECRET" \
  --query SecretString --output text 2>/dev/null || true)
: > "$AIRFLOW_HOME/snowflake.env"
if [ -n "$SNOW_JSON" ]; then
  SNOW_JSON="$SNOW_JSON" python3 -c '
import json, os, sys
d = json.loads(os.environ["SNOW_JSON"])
if not isinstance(d, dict) or "conn_type" not in d:
    sys.exit(1)
c = json.dumps(d, separators=(",", ":"))
if "\x27" in c:
    sys.exit(1)
print("AIRFLOW_CONN_SNOWFLAKE_DEFAULT=\x27" + c + "\x27")
' >> "$AIRFLOW_HOME/snowflake.env" \
    || { : > "$AIRFLOW_HOME/snowflake.env"; echo "AVISO: el secreto de Snowflake no es un JSON de conexion valido"; }
fi
unset SNOW_JSON

# Bucket del lake para los contenedores (pipeline.herramientas.rutas lo lee de LAKE_BUCKET;
# en prod nunca se adivina). Sin esta línea correr_bronze falla con «Falta LAKE_BUCKET».
echo "LAKE_BUCKET=$LAKE" > "$AIRFLOW_HOME/lake.env"
chmod 600 "$AIRFLOW_HOME/lake.env"
chown 50000:0 "$AIRFLOW_HOME/lake.env"
chmod 600 "$AIRFLOW_HOME/snowflake.env"
chown 50000:0 "$AIRFLOW_HOME/snowflake.env"
