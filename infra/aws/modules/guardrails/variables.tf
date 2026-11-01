variable "prefix" {
  description = "Prefijo de los nombres de recursos."
  type        = string
}

variable "budget_usd" {
  description = "Presupuesto mensual en USD."
  type        = number
  default     = 50
}

variable "alert_email" {
  description = "Correo de las alertas de Budgets."
  type        = string
}

variable "role_names" {
  description = "Nombres de los roles que reciben la politica Deny al alcanzar el umbral de bloqueo (GitHub, Code Editor y Airflow)."
  type        = list(string)

  validation {
    condition     = length(var.role_names) > 0
    error_message = "role_names debe tener al menos un rol."
  }
}

variable "alert_thresholds" {
  description = "Umbrales de alerta por email (porcentaje del presupuesto, gasto real)."
  type        = list(number)
  default     = [40, 80] # el 60 % lo notifica la accion de bloqueo
}

variable "action_threshold" {
  description = "Umbral (porcentaje, gasto real) que aplica la politica Deny."
  type        = number
  default     = 60
}

variable "instance_ids" {
  description = "Instancias EC2 (VM de Airflow) que Budgets detiene por SSM al alcanzar el umbral de bloqueo."
  type        = list(string)
  default     = []
}

variable "permissions_boundary_arn" {
  description = "ARN de la permissions boundary que llevan todos los roles IAM del modulo."
  type        = string
}
