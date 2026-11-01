provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.prefix
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  permissions_boundary_arn = coalesce(var.permissions_boundary_arn, "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.prefix}-boundary")

  github_role_name    = "${var.prefix}-github-actions"
  airflow_role_name   = "${var.prefix}-airflow-vm"
  sagemaker_role_name = "${var.prefix}-sagemaker-exec" # Code Editor (lo crea el bootstrap)
  # El Deny solo frena cómputo (Glue, EC2): desde Code Editor se puede seguir leyendo, desbloquear y destruir.
  guardrail_role_names = concat([local.github_role_name, local.sagemaker_role_name], var.enable_airflow ? [local.airflow_role_name] : [])
  glue_job_arns        = var.enable_glue ? module.glue[0].job_arns : []
}

module "lake" {
  source = "./modules/lake"

  prefix                   = var.prefix
  aws_region               = var.aws_region
  permissions_boundary_arn = local.permissions_boundary_arn
  snowflake_iam_user_arn   = var.snowflake_iam_user_arn
  snowflake_external_id    = var.snowflake_external_id
}

module "glue" {
  source = "./modules/glue"
  count  = var.enable_glue ? 1 : 0

  prefix                   = var.prefix
  aws_region               = var.aws_region
  lake_bucket              = module.lake.bucket_name
  permissions_boundary_arn = local.permissions_boundary_arn
}

module "airflow_vm" {
  source = "./modules/airflow_vm"
  count  = var.enable_airflow ? 1 : 0

  prefix                   = var.prefix
  lake_bucket              = module.lake.bucket_name
  glue_job_arns            = local.glue_job_arns
  instance_type            = var.airflow_instance_type
  permissions_boundary_arn = local.permissions_boundary_arn
}

module "guardrails" {
  source = "./modules/guardrails"

  prefix                   = var.prefix
  budget_usd               = var.budget_usd
  alert_email              = var.alert_email
  role_names               = local.guardrail_role_names
  instance_ids             = var.enable_airflow ? [module.airflow_vm[0].instance_id] : []
  permissions_boundary_arn = local.permissions_boundary_arn

  # El rol de Airflow debe existir antes de que Budgets lo referencie.
  depends_on = [module.airflow_vm]
}
