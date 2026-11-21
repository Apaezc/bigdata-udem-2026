#!/bin/bash
# Acción única para una VM de Airflow creada antes de que existiera el arranque mínimo: instala
# refresh.env, el arranque y el cron. Después, "make deploy" basta para actualizar la VM.
# Uso (como root, por SSM): LAKE=... REGION=... PREFIX=... bash instalar-bootstrap.sh
set -euo pipefail
: "${LAKE:?falta LAKE}" "${REGION:?falta REGION}" "${PREFIX:?falta PREFIX}"
export AWS_DEFAULT_REGION="$REGION"
mkdir -p /opt/airflow/pipeline
cat > /opt/airflow/refresh.env <<ENV
REGION=$REGION
LAKE=$LAKE
SNOWFLAKE_SECRET=$PREFIX/snowflake
ENV
aws s3 cp "s3://$LAKE/code/airflow/airflow-bootstrap.sh" /usr/local/bin/airflow-refresh.sh
chmod 755 /usr/local/bin/airflow-refresh.sh
cat > /etc/cron.d/airflow-dags-sync <<CRON
* * * * * root /usr/local/bin/airflow-refresh.sh sync >> /var/log/airflow-dags-sync.log 2>&1
CRON
chmod 644 /etc/cron.d/airflow-dags-sync
/usr/local/bin/airflow-refresh.sh
systemctl restart airflow.service
