#!/bin/bash
# Arranque mínimo del refresco: baja de S3 la versión vigente del cuerpo y la ejecuta.
# Por qué: el user_data solo corre en el primer arranque de la VM. Con este paso intermedio, un
# cambio en airflow/vm/airflow-refresh.sh llega con "make deploy", sin recrear la VM.
set -uo pipefail
source /opt/airflow/refresh.env   # REGION, LAKE, SNOWFLAKE_SECRET
export AWS_DEFAULT_REGION="$REGION"
CUERPO=/usr/local/bin/airflow-refresh-cuerpo.sh

if aws s3 cp "s3://$LAKE/code/airflow/airflow-refresh.sh" "$CUERPO.nuevo" --only-show-errors; then
  chmod 755 "$CUERPO.nuevo"
  mv "$CUERPO.nuevo" "$CUERPO"
else
  echo "AVISO: no se pudo bajar airflow-refresh.sh de s3://$LAKE/code/airflow/ (ejecuta make deploy)"
fi
if [ ! -x "$CUERPO" ]; then
  echo "AVISO: no hay cuerpo de refresco todavía; se omite."
  exit 0
fi
exec "$CUERPO" "$@"
