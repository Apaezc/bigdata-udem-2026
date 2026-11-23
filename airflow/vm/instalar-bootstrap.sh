#!/bin/bash
# Acción única para una VM de Airflow creada antes de que existiera el arranque mínimo (o antes de la
# clase 7): instala refresh.env, el arranque y el cron. Después, el CI/CD basta para actualizar la VM.
# La VM es la de prod: su secreto de Snowflake es <PREFIX>/snowflake_prod (rol BIGDATA_PROD).
# Uso normal: "make actualizar-vm" (lo corre por SSM). A mano (como root):
#   LAKE=... REGION=... PREFIX=... bash instalar-bootstrap.sh
set -euo pipefail
: "${LAKE:?falta LAKE}" "${REGION:?falta REGION}" "${PREFIX:?falta PREFIX}"
export AWS_DEFAULT_REGION="$REGION"
mkdir -p /opt/airflow/pipeline
cat > /opt/airflow/refresh.env <<ENV
REGION=$REGION
LAKE=$LAKE
SNOWFLAKE_SECRET=$PREFIX/snowflake_prod
ENV
aws s3 cp "s3://$LAKE/code/airflow/airflow-bootstrap.sh" /usr/local/bin/airflow-refresh.sh
chmod 755 /usr/local/bin/airflow-refresh.sh
cat > /etc/cron.d/airflow-dags-sync <<CRON
* * * * * root /usr/local/bin/airflow-refresh.sh sync >> /var/log/airflow-dags-sync.log 2>&1
CRON
chmod 644 /etc/cron.d/airflow-dags-sync
/usr/local/bin/airflow-refresh.sh
systemctl restart airflow.service
