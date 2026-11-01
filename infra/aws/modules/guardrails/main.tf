data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  role_arns  = [for n in var.role_names : "arn:aws:iam::${local.account_id}:role/${n}"]
}

# ---------------------------------------------------------------------------
# Presupuesto mensual con alertas
# ---------------------------------------------------------------------------

resource "aws_budgets_budget" "mensual" {
  name         = "${var.prefix}-mensual"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Sin descontar créditos: con el free plan el gasto neto es ~0 y los topes no actuarían.
  cost_types {
    include_credit = false
  }

  dynamic "notification" {
    for_each = var.alert_thresholds

    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [var.alert_email]
    }
  }
}

# ---------------------------------------------------------------------------
# Politica Deny: se adjunta a los roles solo cuando Budgets dispara la accion
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "bloqueo" {
  statement {
    sid       = "BloqueoPorPresupuesto"
    effect    = "Deny"
    actions   = ["glue:StartJobRun", "ec2:StartInstances", "ec2:RunInstances"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "bloqueo" {
  name        = "${var.prefix}-bloqueo-presupuesto"
  description = "Deny aplicado por AWS Budgets al alcanzar el umbral de bloqueo. Ver README del modulo."
  policy      = data.aws_iam_policy_document.bloqueo.json
}

# ---------------------------------------------------------------------------
# Rol que Budgets asume para adjuntar la politica
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "budgets_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "budgets_action" {
  name               = "${var.prefix}-budgets-action"
  description        = "Rol de ejecucion de AWS Budgets para adjuntar la politica de bloqueo."
  assume_role_policy = data.aws_iam_policy_document.budgets_trust.json

  permissions_boundary = var.permissions_boundary_arn
}

data "aws_iam_policy_document" "budgets_action" {
  statement {
    sid       = "AdjuntarSoloLaPoliticaDeBloqueo"
    actions   = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
    resources = local.role_arns

    condition {
      test     = "ArnEquals"
      variable = "iam:PolicyARN"
      values   = [aws_iam_policy.bloqueo.arn]
    }
  }

  dynamic "statement" {
    for_each = length(var.instance_ids) > 0 ? [1] : []
    content {
      sid       = "DetenerVmPorSsm"
      actions   = ["ec2:StopInstances"]
      resources = [for i in var.instance_ids : "arn:aws:ec2:${data.aws_region.current.region}:${local.account_id}:instance/${i}"]
    }
  }

  dynamic "statement" {
    for_each = length(var.instance_ids) > 0 ? [1] : []
    content {
      sid       = "AutomatizacionSsm"
      actions   = ["ec2:DescribeInstances", "ec2:DescribeInstanceStatus", "ssm:StartAutomationExecution", "ssm:GetAutomationExecution"]
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = length(var.instance_ids) > 0 ? [1] : []
    content {
      sid       = "PasarseASiMismoASsm"
      actions   = ["iam:PassRole"]
      resources = [aws_iam_role.budgets_action.arn]
      condition {
        test     = "StringEquals"
        variable = "iam:PassedToService"
        values   = ["ssm.amazonaws.com"]
      }
    }
  }
}

resource "aws_iam_role_policy" "budgets_action" {
  name   = "adjuntar-politica-bloqueo"
  role   = aws_iam_role.budgets_action.id
  policy = data.aws_iam_policy_document.budgets_action.json
}

# ---------------------------------------------------------------------------
# Accion de Budgets: al 60 % (gasto real) adjunta el Deny a los roles
# ---------------------------------------------------------------------------

resource "aws_budgets_budget_action" "bloqueo" {
  budget_name        = aws_budgets_budget.mensual.name
  action_type        = "APPLY_IAM_POLICY"
  approval_model     = "AUTOMATIC"
  notification_type  = "ACTUAL"
  execution_role_arn = aws_iam_role.budgets_action.arn

  action_threshold {
    action_threshold_type  = "PERCENTAGE"
    action_threshold_value = var.action_threshold
  }

  definition {
    iam_action_definition {
      policy_arn = aws_iam_policy.bloqueo.arn
      roles      = var.role_names
    }
  }

  subscriber {
    subscription_type = "EMAIL"
    address           = var.alert_email
  }

  depends_on = [aws_iam_role_policy.budgets_action]
}

# ---------------------------------------------------------------------------
# Accion de Budgets: al mismo umbral detiene la VM de Airflow (si existe) por SSM
# ---------------------------------------------------------------------------

resource "aws_budgets_budget_action" "detener_vm" {
  count = length(var.instance_ids) > 0 ? 1 : 0

  budget_name        = aws_budgets_budget.mensual.name
  action_type        = "RUN_SSM_DOCUMENTS"
  approval_model     = "AUTOMATIC"
  notification_type  = "ACTUAL"
  execution_role_arn = aws_iam_role.budgets_action.arn

  action_threshold {
    action_threshold_type  = "PERCENTAGE"
    action_threshold_value = var.action_threshold
  }

  definition {
    ssm_action_definition {
      action_sub_type = "STOP_EC2_INSTANCES"
      region          = data.aws_region.current.region
      instance_ids    = var.instance_ids
    }
  }

  subscriber {
    subscription_type = "EMAIL"
    address           = var.alert_email
  }

  depends_on = [aws_iam_role_policy.budgets_action]
}
