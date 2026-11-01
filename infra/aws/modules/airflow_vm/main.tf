data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_vpc" "default" {
  count   = var.vpc_id == null ? 1 : 0
  default = true
}

locals {
  region     = data.aws_region.current.region
  account_id = data.aws_caller_identity.current.account_id

  vpc_id = var.vpc_id != null ? var.vpc_id : data.aws_vpc.default[0].id

  role_name      = "${var.prefix}-airflow-vm" # rol e instance profile
  instance_name  = "${var.prefix}-airflow"    # tag Name: lo buscan scripts/ y workflows
  sg_name        = "${var.prefix}-airflow-sg"
  secret_name    = "${var.prefix}/airflow-admin"
  snowflake_name = "${var.prefix}/snowflake"

  lake_arn           = "arn:aws:s3:::${var.lake_bucket}"
  secret_arn_pattern = "arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:${var.prefix}/*"
}

data "aws_subnets" "in_vpc" {
  count = var.subnet_id == null ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
}

locals {
  subnet_id = var.subnet_id != null ? var.subnet_id : sort(data.aws_subnets.in_vpc[0].ids)[0]
}

# ---------------------------------------------------------------------------
# AMI: Amazon Linux 2023 (x86_64) vía parámetro SSM público.
# ---------------------------------------------------------------------------
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ---------------------------------------------------------------------------
# Secreto con la contraseña admin de la UI de Airflow.
# ---------------------------------------------------------------------------
resource "random_password" "admin" {
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "admin" {
  name                    = local.secret_name
  description             = "Credenciales admin de la UI de Airflow (usuario admin)."
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "admin" {
  secret_id = aws_secretsmanager_secret.admin.id
  secret_string = jsonencode({
    username = "admin"
    password = random_password.admin.result
  })
}

# ---------------------------------------------------------------------------
# Secreto con la conexion de Snowflake para Airflow (snowflake_default).
# Terraform solo crea el contenedor; el alumno guarda el JSON de la conexion
# (ver airflow/README.md). La VM lo lee en cada arranque.
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "snowflake" {
  name                    = local.snowflake_name
  description             = "Conexion Airflow a Snowflake (JSON de conexion de Airflow). Lo completa el alumno."
  recovery_window_in_days = 0
}

# ---------------------------------------------------------------------------
# Permisos del rol de la VM. El techo lo pone la boundary ${prefix}-boundary (bootstrap).
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "airflow_vm_access" {
  statement {
    sid       = "GlueJobs"
    actions   = ["glue:StartJobRun", "glue:GetJobRun", "glue:BatchStopJobRun", "glue:GetJob"]
    resources = var.glue_job_arns
  }

  statement {
    sid       = "LakeReadCodeDagsLogs"
    actions   = ["s3:GetObject"]
    resources = ["${local.lake_arn}/code/*", "${local.lake_arn}/dags/*", "${local.lake_arn}/logs/*"]
  }

  statement {
    sid       = "LakeListCodeDagsLogs"
    actions   = ["s3:ListBucket"]
    resources = [local.lake_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["code/*", "dags/*", "logs/*"]
    }
  }

  statement {
    sid       = "SecretsPrefix"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [local.secret_arn_pattern]
  }

  # Lectura de los logs de los jobs Glue (verbose=True en glue_task los copia al log de Airflow).
  statement {
    sid       = "LeerLogsDeGlue"
    actions   = ["logs:GetLogEvents", "logs:FilterLogEvents", "logs:DescribeLogStreams"]
    resources = ["arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws-glue/jobs/*"]
  }
}

# ---------------------------------------------------------------------------
# Rol e instance profile de la VM.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "airflow" {
  name                 = local.role_name
  assume_role_policy   = data.aws_iam_policy_document.ec2_trust.json
  permissions_boundary = var.permissions_boundary_arn
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.airflow.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "airflow_vm_access" {
  name   = "${var.prefix}-airflow-vm-access"
  role   = aws_iam_role.airflow.id
  policy = data.aws_iam_policy_document.airflow_vm_access.json
}

resource "aws_iam_instance_profile" "airflow" {
  name = local.role_name
  role = aws_iam_role.airflow.name
}

# ---------------------------------------------------------------------------
# Red: SG sin ingress. La UI se usa solo por túnel SSM (make airflow-tunel) desde el Code Editor.
# ---------------------------------------------------------------------------
resource "aws_security_group" "airflow" {
  name = local.sg_name
  # La descripción no se puede cambiar sin recrear el SG: se conserva la original.
  description = "Airflow VM: UI en 8080 solo desde allowed_cidrs"
  vpc_id      = local.vpc_id

  tags = {
    Name    = local.instance_name
    Project = var.prefix
  }
}

resource "aws_vpc_security_group_egress_rule" "all_out" {
  security_group_id = aws_security_group.airflow.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Salida libre (dnf, S3, Docker Hub, Secrets Manager)"
}

# ---------------------------------------------------------------------------
# VM Airflow.
# ---------------------------------------------------------------------------
resource "aws_instance" "airflow" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = local.subnet_id
  vpc_security_group_ids = [aws_security_group.airflow.id]
  iam_instance_profile   = aws_iam_instance_profile.airflow.name
  # IP pública automática (sin EIP) solo para salir a internet; se cobra solo mientras está encendida.
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    region           = local.region
    prefix           = var.prefix
    lake_bucket      = var.lake_bucket
    secret_name      = local.secret_name
    snowflake_secret = local.snowflake_name
  })

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2 # los contenedores Docker necesitan hop 2 para llegar a IMDS
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }

  tags = {
    Name    = local.instance_name
    Project = var.prefix
  }

  lifecycle {
    # associate_public_ip_address: con la VM apagada AWS no reporta IP pública y Terraform leería
    # false, proponiendo recrear la instancia en cada deploy. La IP automática vuelve al encenderla.
    ignore_changes = [ami, associate_public_ip_address]
  }
}

# ---------------------------------------------------------------------------
# Apagado programado: EventBridge Scheduler con target universal ec2:stopInstances.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "scheduler_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name                 = "${var.prefix}-airflow-stop-scheduler"
  assume_role_policy   = data.aws_iam_policy_document.scheduler_trust.json
  permissions_boundary = var.permissions_boundary_arn
}

resource "aws_iam_role_policy" "scheduler_stop" {
  name = "${var.prefix}-airflow-stop-scheduler"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "StopAirflowVm"
      Effect   = "Allow"
      Action   = "ec2:StopInstances"
      Resource = "arn:aws:ec2:${local.region}:${local.account_id}:instance/${aws_instance.airflow.id}"
    }]
  })
}

resource "aws_scheduler_schedule" "stop" {
  name                         = "${var.prefix}-airflow-stop"
  schedule_expression          = var.stop_cron
  schedule_expression_timezone = var.timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:stopInstances"
    role_arn = aws_iam_role.scheduler.arn
    input = jsonencode({
      InstanceIds = [aws_instance.airflow.id]
    })
  }
}
