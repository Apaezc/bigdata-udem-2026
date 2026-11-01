variable "aws_region" {
  description = "Region AWS del template."
  type        = string
  default     = "us-east-2"
}

variable "prefix" {
  description = "Prefijo de los nombres de recursos (prefijo-recurso)."
  type        = string
  default     = "bigdata"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.prefix))
    error_message = "prefix: minusculas, numeros y guiones; 2-21 caracteres; empieza con letra."
  }
}

variable "enable_glue" {
  description = "Crea modules/glue (jobs Glue small/medium/large)."
  type        = bool
  default     = true
}

variable "enable_airflow" {
  description = "Crea modules/airflow_vm (VM Airflow)."
  type        = bool
  default     = false
}

variable "airflow_instance_type" {
  description = "Tipo de instancia de la VM Airflow. Fallback: c7i-flex.large."
  type        = string
  default     = "m7i-flex.large"
}

variable "snowflake_iam_user_arn" {
  description = "Fase 2: STORAGE_AWS_IAM_USER_ARN de la storage integration. Vacio = fase 1."
  type        = string
  default     = ""
}

variable "snowflake_external_id" {
  description = "Fase 2: STORAGE_AWS_EXTERNAL_ID de la storage integration. Vacio = fase 1 (external id 0000)."
  type        = string
  default     = ""
}

variable "budget_usd" {
  description = "Presupuesto mensual en USD."
  type        = number
  default     = 50
}

variable "permissions_boundary_arn" {
  description = "ARN de la politica boundary ($${prefix}-boundary, creada por bootstrap) que llevan TODOS los roles IAM que crea Terraform. Null = se arma con el ID de cuenta y el prefijo."
  type        = string
  default     = null
}

variable "alert_email" {
  description = "Correo para las alertas de Budgets. No versionar el valor real. En deploy y CI llega desde s3://<state>/config/aws.tfvars (-var-file)."
  type        = string

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$", var.alert_email))
    error_message = "alert_email debe ser un correo valido."
  }
}
