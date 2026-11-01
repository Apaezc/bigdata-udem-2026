variable "organization_name" {
  description = "Nombre de la organización Snowflake (ver Snowsight)."
  type        = string
}

variable "account_name" {
  description = "Nombre de la cuenta Snowflake dentro de la organización."
  type        = string
}

variable "user" {
  description = "Usuario de servicio con key-pair creado por bootstrap/snowflake/01_admin.sql."
  type        = string
  default     = "TERRAFORM_SVC"
}

variable "private_key" {
  description = "Contenido PEM (PKCS8) de la llave privada. No va en tfvars: el Makefile la lee de KEY y la pasa como TF_VAR_private_key."
  type        = string
  sensitive   = true
}

variable "s3_role_arn" {
  description = "ARN del rol IAM de Snowflake. Output snowflake_s3_role_arn de infra/aws (fase 1)."
  type        = string
}

variable "lake_bucket" {
  description = "Nombre del bucket del lake (sin s3://). Output lake_bucket de infra/aws (fase 1)."
  type        = string
}

variable "dev_users" {
  description = "Usuarios de Snowflake a los que se asigna BIGDATA_DEV. Lista vacía por defecto."
  type        = list(string)
  default     = []
}
