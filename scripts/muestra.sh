#!/usr/bin/env bash
# Prepara los datos en la nube con Glue: (1) bronze del año de prod (solo descarga lo que falta)
# y (2) la muestra en s3://<lake>/muestra que usa el entorno local. Una vez por curso.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

requerir aws jq

correr() {
  # Uso: correr <perfil> <step>. Lanza el job Glue y espera a que termine.
  local job="${PREFIX}-$1" step="$2" id estado
  id="$(aws glue start-job-run --job-name "$job" \
    --arguments "{\"--step\":\"$step\",\"--env\":\"prod\"}" --query JobRunId --output text)" \
    || error "No se pudo lanzar $job (¿otro run en curso o bloqueo por presupuesto?)."
  msg "Glue $job --step $step (run $id)"
  while :; do
    estado="$(aws glue get-job-run --job-name "$job" --run-id "$id" --query JobRun.JobRunState --output text)"
    case "$estado" in
      SUCCEEDED) msg "$step OK"; return 0 ;;
      FAILED|ERROR|TIMEOUT|STOPPED)
        error "$step terminó en $estado. Revisa los logs en CloudWatch (/aws-glue/jobs/${PREFIX})." ;;
    esac
    sleep 20
  done
}

correr small bronze
correr medium muestra
msg "Muestra lista en s3://$(lake_bucket)/muestra. En local: make run-local (la descarga la primera vez)."
