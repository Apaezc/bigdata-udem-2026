output "instance_id" {
  description = "ID de la instancia EC2 de Airflow."
  value       = aws_instance.airflow.id
}

output "secret_name" {
  description = "Nombre del secreto con las credenciales admin de Airflow."
  value       = aws_secretsmanager_secret.admin.name
}
