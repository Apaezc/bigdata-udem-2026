# Recursos de Snowflake del curso. Nombres fijos según CONTRATO.md.
# BIGDATA_RM NO lo crea ni lo asigna Terraform: lo crea bootstrap/snowflake/01_admin.sql con
# ACCOUNTADMIN, que lo asigna a la cuenta (ALTER ACCOUNT): aplica a todos los warehouses, incluido
# BIGDATA_WH. Snowflake no deja asignarlo además al warehouse mientras esté a nivel de cuenta.
# Asignar un resource monitor requiere ACCOUNTADMIN; por eso el warehouse lo ignora en lifecycle.

# ---------- Warehouse y base ----------

resource "snowflake_warehouse" "bigdata" {
  name                = "BIGDATA_WH"
  warehouse_size      = "XSMALL"
  auto_suspend        = 60
  auto_resume         = true
  initially_suspended = true
  comment             = "Warehouse XS del curso Big Data"

  lifecycle {
    # Lo gestiona 01_admin.sql con ACCOUNTADMIN (a nivel de cuenta); sin esto Terraform intentaría quitarlo.
    ignore_changes = [resource_monitor]
  }
}

resource "snowflake_database" "bigdata" {
  name    = "BIGDATA"
  comment = "Base del curso Big Data (BRONZE/SILVER/GOLD para SQL; DEV/PROD para el pipeline)"
}

# BRONZE/SILVER/GOLD: sesiones de SQL y P1. DEV/PROD: gold del pipeline por entorno (Airflow).
locals {
  entornos = { DEV = "dev", PROD = "prod" }
}

resource "snowflake_schema" "layer" {
  for_each = toset(["BRONZE", "SILVER", "GOLD", "DEV", "PROD"])

  database = snowflake_database.bigdata.name
  name     = each.key
  comment  = contains(keys(local.entornos), each.key) ? "Gold del pipeline, entorno ${local.entornos[each.key]}" : "Capa ${each.key}"
}

# ---------- Rol de desarrollo para estudiantes ----------

resource "snowflake_account_role" "dev" {
  name    = "BIGDATA_DEV"
  comment = "Rol de estudiantes: usa BIGDATA_WH y crea objetos en BIGDATA"
}

resource "snowflake_grant_account_role" "dev_users" {
  for_each = toset(var.dev_users)

  role_name = snowflake_account_role.dev.name
  user_name = each.value
}

resource "snowflake_grant_privileges_to_account_role" "dev_warehouse" {
  account_role_name = snowflake_account_role.dev.name
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.bigdata.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "dev_database" {
  account_role_name = snowflake_account_role.dev.name
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.bigdata.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "dev_schemas" {
  for_each = snowflake_schema.layer

  account_role_name = snowflake_account_role.dev.name
  privileges        = ["USAGE", "CREATE TABLE", "CREATE VIEW", "CREATE STAGE", "CREATE FILE FORMAT"]

  on_schema {
    schema_name = "${snowflake_database.bigdata.name}.${each.key}"
  }
}

# ---------- Usuario de servicio de Airflow (dev en el Code Editor y prod en la VM) ----------
# Autentica con key-pair. La llave privada vive solo en ~/.snowflake/keys/airflow_svc_rsa_key.p8;
# scripts/snowflake.sh la copia al secreto <prefix>/snowflake de Secrets Manager (conexión snowflake_default).
# Usa BIGDATA_DEV: crea y recarga las tablas de BIGDATA.DEV / BIGDATA.PROD (copy_gold.sql).

resource "snowflake_service_user" "airflow" {
  count = var.airflow_public_key == null ? 0 : 1

  name              = "AIRFLOW_SVC"
  default_warehouse = snowflake_warehouse.bigdata.name
  default_role      = snowflake_account_role.dev.name
  rsa_public_key    = var.airflow_public_key
  comment           = "Usuario de servicio de Airflow (curso Big Data)"
}

resource "snowflake_grant_account_role" "dev_airflow" {
  count = var.airflow_public_key == null ? 0 : 1

  role_name = snowflake_account_role.dev.name
  user_name = snowflake_service_user.airflow[0].name
}

# SELECT sobre tablas y vistas futuras de cada capa (las que cree el pipeline u otros roles).
locals {
  future_selects = {
    for p in setproduct(keys(snowflake_schema.layer), ["TABLES", "VIEWS"]) :
    "${p[0]}_${p[1]}" => { schema = p[0], plural = p[1] }
  }
}

resource "snowflake_grant_privileges_to_account_role" "dev_future_select" {
  for_each = local.future_selects

  account_role_name = snowflake_account_role.dev.name
  privileges        = ["SELECT"]

  on_schema_object {
    future {
      object_type_plural = each.value.plural
      in_schema          = snowflake_schema.layer[each.value.schema].fully_qualified_name
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "dev_integration" {
  account_role_name = snowflake_account_role.dev.name
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "INTEGRATION"
    object_name = snowflake_storage_integration_aws.s3.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "dev_stage" {
  account_role_name = snowflake_account_role.dev.name
  privileges        = ["USAGE", "READ"]

  on_schema_object {
    object_type = "STAGE"
    object_name = "${snowflake_database.bigdata.name}.${snowflake_schema.layer["GOLD"].name}.${snowflake_stage_external_s3.lake_gold.name}"
  }
}

resource "snowflake_grant_privileges_to_account_role" "dev_stage_entorno" {
  for_each = local.entornos

  account_role_name = snowflake_account_role.dev.name
  privileges        = ["USAGE", "READ"]

  on_schema_object {
    object_type = "STAGE"
    object_name = snowflake_stage_external_s3.lake_entorno[each.key].fully_qualified_name
  }
}

# ---------- Integración con S3 y stage externo sobre gold/ ----------
# Dos fases: aquí se crea la integración con el rol de infra/aws (trust placeholder).
# Snowflake genera STORAGE_AWS_IAM_USER_ARN y STORAGE_AWS_EXTERNAL_ID (outputs de este stack);
# se pegan en la trust policy del rol en infra/aws (fase 2).

resource "snowflake_storage_integration_aws" "s3" {
  name                 = "BIGDATA_S3_INT"
  enabled              = true
  storage_provider     = "S3"
  storage_aws_role_arn = var.s3_role_arn
  storage_allowed_locations = [
    "s3://${var.lake_bucket}/gold/",
    "s3://${var.lake_bucket}/dev/gold/",
    "s3://${var.lake_bucket}/prod/gold/",
  ]
  comment = "Acceso de Snowflake a gold/ (SQL) y a <entorno>/gold/ (pipeline) del lake"
}

resource "snowflake_file_format_parquet" "parquet" {
  database = snowflake_database.bigdata.name
  schema   = snowflake_schema.layer["GOLD"].name
  name     = "PARQUET_FF"
  comment  = "Formato Parquet para leer gold/"
}

resource "snowflake_stage_external_s3" "lake_gold" {
  database            = snowflake_database.bigdata.name
  schema              = snowflake_schema.layer["GOLD"].name
  name                = "LAKE_GOLD"
  url                 = "s3://${var.lake_bucket}/gold/"
  storage_integration = snowflake_storage_integration_aws.s3.name
  comment             = "Stage externo sobre s3://<lake>/gold/"

  file_format {
    format_name = "${snowflake_database.bigdata.name}.${snowflake_schema.layer["GOLD"].name}.${snowflake_file_format_parquet.parquet.name}"
  }
}

# ---------- Stages del pipeline por entorno: BIGDATA.<DEV|PROD>.LAKE_GOLD -> s3://<lake>/<env>/gold/ ----------
# Los usa airflow/dags/sql/copy_gold.sql (cargar_dev / cargar_prod).

resource "snowflake_file_format_parquet" "entorno" {
  for_each = local.entornos

  database = snowflake_database.bigdata.name
  schema   = snowflake_schema.layer[each.key].name
  name     = "PARQUET_FF"
  comment  = "Formato Parquet para leer ${each.value}/gold/"
}

resource "snowflake_stage_external_s3" "lake_entorno" {
  for_each = local.entornos

  database            = snowflake_database.bigdata.name
  schema              = snowflake_schema.layer[each.key].name
  name                = "LAKE_GOLD"
  url                 = "s3://${var.lake_bucket}/${each.value}/gold/"
  storage_integration = snowflake_storage_integration_aws.s3.name
  comment             = "Stage externo sobre s3://<lake>/${each.value}/gold/"

  file_format {
    format_name = snowflake_file_format_parquet.entorno[each.key].fully_qualified_name
  }
}
