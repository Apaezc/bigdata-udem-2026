variable "prefix" {
  description = "Prefijo de los nombres de recursos."
  type        = string
}

variable "aws_region" {
  description = "Region AWS (para el ARN del log group)."
  type        = string
}

variable "lake_bucket" {
  description = "Nombre del bucket del lake (dev/, prod/, code/, tmp/, logs/)."
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

variable "snowflake_secret_arns" {
  description = "ARNs de los secretos de Snowflake que pueden leer los jobs: <prefix>/snowflake (dev, BIGDATA_DEV) y <prefix>/snowflake_prod (prod, BIGDATA_PROD). Los usan la tabla de control y la carga a Snowflake."
  type        = list(string)
}

variable "snowflake_secret_name" {
  description = "Nombre del secreto <prefix>/snowflake: valor por defecto de --snowflake-secret. El DAG de prod lo reemplaza por <prefix>/snowflake_prod en cada corrida."
  type        = string
}
