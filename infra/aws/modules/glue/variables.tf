variable "prefix" {
  description = "Prefijo de los nombres de recursos."
  type        = string
}

variable "aws_region" {
  description = "Region AWS (para el ARN del log group)."
  type        = string
}

variable "lake_bucket" {
  description = "Nombre del bucket del lake (code/, bronze/, silver/, gold/, tmp/, logs/)."
  type        = string
}

variable "env" {
  description = "Valor del argumento --env que recibe run_glue.py."
  type        = string
  default     = "dev"
}

variable "permissions_boundary_arn" {
  description = "ARN de la permissions boundary que llevan todos los roles IAM del modulo."
  type        = string
}

variable "snowflake_secret_arn" {
  description = "ARN del secreto <prefix>/snowflake (conexión de AIRFLOW_SVC). Los jobs lo leen para registrar en BIGDATA.CONTROL.WATERMARK."
  type        = string
}

variable "snowflake_secret_name" {
  description = "Nombre del secreto <prefix>/snowflake: se pasa al job como --snowflake-secret."
  type        = string
}
