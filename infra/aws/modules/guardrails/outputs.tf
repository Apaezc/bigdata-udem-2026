output "budget_name" {
  description = "Nombre del presupuesto mensual."
  value       = aws_budgets_budget.mensual.name
}

output "bloqueo_policy_arn" {
  description = "ARN de la politica Deny que Budgets adjunta. Para desbloquear, ver README."
  value       = aws_iam_policy.bloqueo.arn
}

output "budgets_action_role_arn" {
  description = "ARN del rol de ejecucion de Budgets. El rol que aplica Terraform necesita iam:PassRole sobre el."
  value       = aws_iam_role.budgets_action.arn
}
