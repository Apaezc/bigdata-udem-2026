output "job_names" {
  description = "Nombre de cada job por perfil (small/medium/large)."
  value       = { for k, j in aws_glue_job.this : k => j.name }
}

output "job_arns" {
  description = "ARN de los jobs Glue. Para la politica de la VM Airflow."
  value       = [for j in aws_glue_job.this : j.arn]
}

output "role_arn" {
  description = "ARN del rol de ejecucion de Glue."
  value       = aws_iam_role.glue_exec.arn
}

output "log_group_name" {
  description = "Log group de logs continuos de Glue."
  value       = aws_cloudwatch_log_group.glue.name
}
