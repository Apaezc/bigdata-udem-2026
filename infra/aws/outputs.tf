output "lake_bucket" {
  description = "Nombre del bucket del lake."
  value       = module.lake.bucket_name
}

output "glue_jobs" {
  description = "Jobs Glue por perfil (small/medium/large). Vacio si enable_glue = false."
  value       = var.enable_glue ? module.glue[0].job_names : {}
}

output "airflow_instance_id" {
  description = "ID de la VM Airflow. null si enable_airflow = false."
  value       = var.enable_airflow ? module.airflow_vm[0].instance_id : null
}

output "snowflake_s3_role_arn" {
  description = "ARN del rol para la storage integration de Snowflake."
  value       = module.lake.snowflake_s3_role_arn
}
