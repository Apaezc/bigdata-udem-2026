terraform {
  required_version = ">= 1.10"

  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 2.0"
    }
  }

  # Configuración en backend.hcl (ver backend.hcl.example). use_lockfile requiere Terraform >= 1.10.
  backend "s3" {}
}

provider "snowflake" {
  organization_name = var.organization_name
  account_name      = var.account_name
  user              = var.user
  role              = "TERRAFORM_ROLE"
  authenticator     = "SNOWFLAKE_JWT"
  private_key       = var.private_key
}
