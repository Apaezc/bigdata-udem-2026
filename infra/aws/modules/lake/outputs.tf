output "bucket_name" {
  description = "Nombre del bucket del lake."
  value       = aws_s3_bucket.lake.id
}

output "bucket_arn" {
  description = "ARN del bucket del lake."
  value       = aws_s3_bucket.lake.arn
}

output "glue_database_name" {
  description = "Nombre de la base de Glue Data Catalog."
  value       = aws_glue_catalog_database.lake.name
}

output "athena_workgroup_name" {
  description = "Nombre del workgroup de Athena."
  value       = aws_athena_workgroup.this.name
}

output "snowflake_s3_role_arn" {
  description = "ARN del rol para la storage integration de Snowflake."
  value       = aws_iam_role.snowflake_s3.arn
}

output "snowflake_s3_role_name" {
  description = "Nombre del rol para la storage integration de Snowflake."
  value       = aws_iam_role.snowflake_s3.name
}
