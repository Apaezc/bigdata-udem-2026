data "aws_caller_identity" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  bucket_name  = "${var.prefix}-lake-${local.account_id}-${var.aws_region}"
  glue_db_name = "${replace(var.prefix, "-", "_")}_lake"

  # Fase 1 (valores vacios): confia en la propia cuenta con external id "0000".
  # Fase 2 (valores de Snowflake): confia en su usuario IAM con el external id real.
  snowflake_phase2    = var.snowflake_iam_user_arn != "" && var.snowflake_external_id != ""
  snowflake_principal = local.snowflake_phase2 ? var.snowflake_iam_user_arn : "arn:aws:iam::${local.account_id}:root"
  snowflake_ext_id    = local.snowflake_phase2 ? var.snowflake_external_id : "0000"
  # gold/ (sesiones de SQL) y gold del pipeline por entorno.
  prefijos_snowflake = ["gold/", "dev/gold/", "prod/gold/"]
}

# ---------------------------------------------------------------------------
# Bucket del lake
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "lake" {
  bucket = local.bucket_name
  # El curso destruye el stack completo (make destroy); sin esto el bucket con objetos no se borra.
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "lake" {
  bucket                  = aws_s3_bucket.lake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lake" {
  bucket = aws_s3_bucket.lake.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Prefijos "carpeta" persistentes. tmp/ y logs/ no tienen marcador porque su lifecycle los
# expira; code/ y dags/ tampoco, porque "aws s3 sync --delete" (deploy) borraria el marcador y
# Terraform lo recrearia en cada apply.
resource "aws_s3_object" "prefijos" {
  for_each = toset(["bronze/", "silver/", "gold/"])

  bucket  = aws_s3_bucket.lake.id
  key     = each.value
  content = ""
}

resource "aws_s3_bucket_lifecycle_configuration" "lake" {
  bucket = aws_s3_bucket.lake.id

  rule {
    id     = "tmp-7-dias"
    status = "Enabled"

    filter {
      prefix = "tmp/"
    }

    expiration {
      days = 7
    }
  }

  rule {
    id     = "logs-30-dias"
    status = "Enabled"

    filter {
      prefix = "logs/"
    }

    expiration {
      days = 30
    }
  }

  rule {
    id     = "abortar-multipart"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# ---------------------------------------------------------------------------
# Glue database y Athena
# ---------------------------------------------------------------------------

resource "aws_glue_catalog_database" "lake" {
  name        = local.glue_db_name
  description = "Catalogo del lake. Tablas por DDL de Athena (sin crawlers)."
}

resource "aws_athena_workgroup" "this" {
  name          = "${var.prefix}-wg"
  force_destroy = true

  configuration {
    enforce_workgroup_configuration = true
    # Athena cancela la consulta si supera 1 GB escaneado.
    bytes_scanned_cutoff_per_query = 1 * 1024 * 1024 * 1024

    result_configuration {
      output_location = "s3://${aws_s3_bucket.lake.id}/tmp/athena/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Rol para la storage integration de Snowflake (stage GOLD)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "snowflake_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [local.snowflake_principal]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [local.snowflake_ext_id]
    }
  }
}

resource "aws_iam_role" "snowflake_s3" {
  name               = "${var.prefix}-snowflake-s3"
  description        = "Storage integration de Snowflake sobre gold/. Fase 1: placeholder; fase 2: STORAGE_AWS_IAM_USER_ARN y EXTERNAL_ID."
  assume_role_policy = data.aws_iam_policy_document.snowflake_trust.json

  permissions_boundary = var.permissions_boundary_arn
}

data "aws_iam_policy_document" "snowflake_access" {
  statement {
    sid       = "GoldLecturaEscritura"
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
    resources = [for p in local.prefijos_snowflake : "${aws_s3_bucket.lake.arn}/${p}*"]
  }

  statement {
    sid       = "GoldListar"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.lake.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [for p in local.prefijos_snowflake : "${p}*"]
    }
  }

  statement {
    sid       = "UbicacionBucket"
    actions   = ["s3:GetBucketLocation"]
    resources = [aws_s3_bucket.lake.arn]
  }
}

resource "aws_iam_role_policy" "snowflake_s3" {
  name   = "gold-lectura-escritura"
  role   = aws_iam_role.snowflake_s3.id
  policy = data.aws_iam_policy_document.snowflake_access.json
}
