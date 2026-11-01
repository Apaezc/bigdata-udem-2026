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
