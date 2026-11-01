data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  lake_arn   = "arn:aws:s3:::${var.lake_bucket}"
  script_s3  = "s3://${var.lake_bucket}/code/run_glue.py"

  # Prefijos de datos del pipeline: bronze compartido, muestra para local, dev/ y prod/ por entorno;
  # silver/ y gold/ quedan para las sesiones de SQL.
  datos     = ["bronze", "muestra", "dev", "prod", "silver", "gold"]
  lectura   = concat(["code", "tmp"], local.datos)
  escritura = concat(local.datos, ["tmp", "logs"])
  listables = concat(local.datos, ["code", "tmp", "logs"])

  # Perfiles del contrato: workers G.1X y timeout en minutos.
  profiles = {
    small  = { workers = 2, timeout = 10 }
    medium = { workers = 4, timeout = 20 }
    large  = { workers = 6, timeout = 30 }
  }
}

# ---------------------------------------------------------------------------
# Rol de ejecucion de Glue (minimo privilegio, solo el bucket del lake)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "glue_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "glue_exec" {
  name               = "${var.prefix}-glue-exec"
  description        = "Ejecucion de los jobs Glue del pipeline. Solo prefijos del lake."
  assume_role_policy = data.aws_iam_policy_document.glue_trust.json

  permissions_boundary = var.permissions_boundary_arn
}

data "aws_iam_policy_document" "glue_exec" {
  statement {
    sid       = "LeerCodigoYZonas"
    actions   = ["s3:GetObject"]
    resources = [for p in local.lectura : "${local.lake_arn}/${p}/*"]
  }

  statement {
    sid       = "EscribirZonasTmpYLogs"
    actions   = ["s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload"]
    resources = [for p in local.escritura : "${local.lake_arn}/${p}/*"]
  }

  statement {
    sid       = "ListarPrefijosDelLake"
    actions   = ["s3:ListBucket"]
    resources = [local.lake_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = flatten([for p in local.listables : [p, "${p}/*"]])
    }
  }

  statement {
    sid       = "UbicacionBucket"
    actions   = ["s3:GetBucketLocation"]
    resources = [local.lake_arn]
  }

  statement {
    sid       = "MetricasDeGlue"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["Glue"]
    }
  }

  statement {
    sid       = "LogsDeGlue"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws-glue/*"]
  }
}

resource "aws_iam_role_policy" "glue_exec" {
  name   = "lake-y-logs"
  role   = aws_iam_role.glue_exec.id
  policy = data.aws_iam_policy_document.glue_exec.json
}

# ---------------------------------------------------------------------------
# Logs y jobs
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "glue" {
  name              = "/aws-glue/jobs/${var.prefix}"
  retention_in_days = 14
}

resource "aws_glue_job" "this" {
  for_each = local.profiles

  name              = "${var.prefix}-${each.key}"
  description       = "Pipeline ${each.key}: run_glue.py invoca pipeline.run."
  role_arn          = aws_iam_role.glue_exec.arn
  glue_version      = "5.0"
  worker_type       = "G.1X"
  number_of_workers = each.value.workers
  timeout           = each.value.timeout
  max_retries       = 0

  command {
    name            = "glueetl"
    script_location = local.script_s3
    python_version  = "3"
  }

  # Un job a la vez por perfil; los siguientes esperan en cola en vez de fallar.
  job_run_queuing_enabled = true

  execution_property {
    max_concurrent_runs = 1
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--extra-py-files"                   = "s3://${var.lake_bucket}/code/pipeline.zip"
    "--additional-python-modules"        = "pyyaml==6.0.2" # la imagen de Glue 5.0 no trae PyYAML
    "--enable-spark-ui"                  = "true"
    "--spark-event-logs-path"            = "s3://${var.lake_bucket}/logs/spark-ui/"
    "--enable-continuous-cloudwatch-log" = "true"
    "--continuous-log-logGroup"          = aws_cloudwatch_log_group.glue.name
    "--enable-metrics"                   = "true"
    "--TempDir"                          = "s3://${var.lake_bucket}/tmp/glue/"
    "--env"                              = var.env
    "--lake-bucket"                      = var.lake_bucket
  }
}
