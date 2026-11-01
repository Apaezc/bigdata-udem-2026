#!/usr/bin/env bash
# Resumen del estado: Airflow, últimos job runs de Glue, warehouse Snowflake y costos.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

requerir aws jq

msg "Airflow"
ID="$(find_airflow_instance_id)"
if [[ -z "$ID" ]]; then
  echo "  Instancia ${PREFIX}-airflow: no encontrada (¿enable_airflow = true?)"
else
  ESTADO="$(instance_state "$ID")"
  printf "  %-14s %s\n" "Estado:" "$ESTADO"
  printf "  %-14s %s\n" "Acceso:" "make airflow-tunel (túnel SSM desde el Code Editor)"
fi

msg "Últimos 3 job runs de Glue"
RUNS="$(for job in small medium large; do
  aws glue get-job-runs --job-name "${PREFIX}-${job}" --max-results 3 \
    --query 'JobRuns[].{job: JobName, estado: JobRunState, inicio: StartedOn}' \
    --output json 2>/dev/null || echo '[]'
done | jq -s 'add // [] | map(select(.inicio != null)) | sort_by(.inicio) | reverse | .[0:3]')"
if [[ "$(jq 'length' <<< "$RUNS")" == "0" ]]; then
  echo "  Sin ejecuciones registradas."
else
  jq -r '.[] | [.job, .estado, .inicio] | @tsv' <<< "$RUNS" | while IFS=$'\t' read -r job estado inicio; do
    printf "  %-18s %-12s %s\n" "$job" "$estado" "$inicio"
  done
fi

msg "Warehouse de Snowflake"
WH="$(echo "${PREFIX}_WH" | tr "[:lower:]" "[:upper:]")"
if WH_JSON="$(snow sql -q "SHOW WAREHOUSES LIKE '${WH}'" --format json 2>/dev/null)" && [[ "$(jq 'length' <<< "$WH_JSON" 2>/dev/null || echo 0)" != "0" ]]; then
  jq -r '.[0] | "  \(.name): estado=\(.state // "?") tamaño=\(.size // "?") auto_suspend=\(.auto_suspend // "?")s"' <<< "$WH_JSON"
else
  echo "  Warehouse ${WH} no encontrado o Snowflake no accesible."
fi

msg "Costos y créditos"
CUENTA="$(account_id)"
PLAN="$(aws freetier get-account-plan-state --output json 2>/dev/null || true)"
if [[ -n "$PLAN" ]]; then
  jq -r '"  Plan: \(.accountPlanType // "?") (\(.accountPlanStatus // "?"))  créditos restantes: \(.accountPlanRemainingCredits.amount // "?") \(.accountPlanRemainingCredits.unit // "")"' <<< "$PLAN" \
    || echo "  Free Tier: respuesta no reconocida."
else
  echo "  Free Tier: no disponible con las credenciales actuales."
fi

BUDGETS="$(aws budgets describe-budgets --account-id "$CUENTA" \
  --query 'Budgets[].[BudgetName,BudgetLimit.Amount,BudgetLimit.Unit,CalculatedSpend.ActualSpend.Amount,CalculatedSpend.ForecastedSpend.Amount]' \
  --output text 2>/dev/null || true)"
if [[ -n "$BUDGETS" ]]; then
  printf "  %-28s %-10s %-10s %-12s %s\n" "Budget" "Límite" "Unidad" "Gasto real" "Previsto"
  echo "$BUDGETS" | while IFS=$'\t' read -r nombre limite unidad real previsto; do
    printf "  %-28s %-10s %-10s %-12s %s\n" "$nombre" "$limite" "$unidad" "${real:-0}" "${previsto:-0}"
  done
else
  echo "  Budgets: no se pudo consultar."
fi
