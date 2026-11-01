#!/usr/bin/env bash
# Revierte las acciones de Budgets que aplicaron una política Deny (o apagaron EC2) tras superar el límite.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

requerir aws jq
CUENTA="$(account_id)"

ACCIONES="$(aws budgets describe-budget-actions-for-account --account-id "$CUENTA" --output json)"
ACTIVAS="$(jq -c '[.Actions[] | select(.Status == "EXECUTION_SUCCESS")]' <<< "$ACCIONES")"

if [[ "$(jq 'length' <<< "$ACTIVAS")" == "0" ]]; then
  msg "No hay acciones de Budgets aplicadas (estado EXECUTION_SUCCESS)."
  exit 0
fi

msg "Acciones de Budgets aplicadas:"
jq -r '.[] | "  \(.BudgetName)  tipo=\(.ActionType)  id=\(.ActionId)  política=\(.Definition.IamActionDefinition.PolicyArn // "n/a")"' <<< "$ACTIVAS"

echo
echo "Esto revierte la acción (quita la política Deny o restaura los permisos)."
echo "Aviso: si el gasto sigue por encima del límite, Budgets volverá a aplicarla en su siguiente evaluación (hasta ~24 h)."
confirmar "Se revertirán las acciones listadas para la cuenta $CUENTA." "SI"

jq -r '.[] | [.BudgetName, .ActionId] | @tsv' <<< "$ACTIVAS" | while IFS=$'\t' read -r presupuesto accion; do
  aws budgets execute-budget-action --account-id "$CUENTA" --budget-name "$presupuesto" \
    --action-id "$accion" --execution-type REVERSE_BUDGET_ACTION >/dev/null
  msg "Revertida acción $accion del presupuesto $presupuesto"
done

msg "Listo. Verifica con 'make estado'."
