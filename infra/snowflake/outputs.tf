output "storage_aws_iam_user_arn" {
  description = "STORAGE_AWS_IAM_USER_ARN de BIGDATA_S3_INT. Va como Principal en la trust policy del rol (infra/aws, fase 2)."
  value       = snowflake_storage_integration_aws.s3.describe_output[0].iam_user_arn
}

output "storage_aws_external_id" {
  description = "STORAGE_AWS_EXTERNAL_ID de BIGDATA_S3_INT. Va como sts:ExternalId en la trust policy del rol (infra/aws, fase 2)."
  value       = snowflake_storage_integration_aws.s3.describe_output[0].external_id
}

# Datos (no secretos) de la conexión snowflake_default de Airflow; scripts/snowflake.sh añade la llave privada.
output "airflow_conexion" {
  description = "Campos de la conexión de Airflow a Snowflake (login, account, warehouse, database, role). null si no se creó AIRFLOW_SVC."
  value = var.airflow_public_key == null ? null : {
    login     = snowflake_service_user.airflow[0].name
    account   = "${var.organization_name}-${var.account_name}"
    warehouse = snowflake_warehouse.bigdata.name
    database  = snowflake_database.bigdata.name
    role      = snowflake_account_role.dev.name
  }
}

# Datos (no secretos) de la conexión de prod; scripts/snowflake-secreto.sh añade la llave de AIRFLOW_PROD_SVC.
output "airflow_prod_conexion" {
  description = "Campos de la conexión de Airflow en prod a Snowflake (rol BIGDATA_PROD). null si no se creó AIRFLOW_PROD_SVC."
  value = var.airflow_prod_public_key == null ? null : {
    login     = snowflake_service_user.airflow_prod[0].name
    account   = "${var.organization_name}-${var.account_name}"
    warehouse = snowflake_warehouse.bigdata.name
    database  = snowflake_database.bigdata.name
    role      = snowflake_account_role.prod.name
  }
}
