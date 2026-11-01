variable "prefix" {
  description = "Prefijo de los nombres de recursos."
  type        = string
}

variable "aws_region" {
  description = "Region AWS (parte del nombre del bucket)."
  type        = string
}

variable "snowflake_iam_user_arn" {
  description = "Fase 2: STORAGE_AWS_IAM_USER_ARN. Vacio = fase 1 (confia en la propia cuenta)."
  type        = string
  default     = ""
}

variable "snowflake_external_id" {
  description = "Fase 2: STORAGE_AWS_EXTERNAL_ID. Vacio = fase 1 (external id 0000)."
  type        = string
  default     = ""
}

variable "permissions_boundary_arn" {
  description = "ARN de la permissions boundary que llevan todos los roles IAM del modulo."
  type        = string
}
