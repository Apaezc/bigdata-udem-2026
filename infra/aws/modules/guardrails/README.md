# Módulo guardrails

Topes de costo sobre la cuenta del alumno: presupuesto mensual con alertas y una acción de Budgets que bloquea el cómputo.

## Qué crea

| Recurso | Nombre | Función |
|---|---|---|
| `aws_budgets_budget` | `${prefix}-mensual` | Presupuesto COST mensual en USD (`budget_usd`, default 50). Gasto bruto (sin descontar créditos del free plan). Alertas por email al 40 % y 80 %; al 60 % la acción de bloqueo también avisa. El bootstrap crea además `${Prefix}-total`, que solo alerta al 100 % como red de seguridad del total de la cuenta. |
| `aws_iam_policy` | `${prefix}-bloqueo-presupuesto` | Deny sobre `glue:StartJobRun`, `ec2:StartInstances` y `ec2:RunInstances`. No se adjunta en Terraform: solo la adjunta Budgets. |
| `aws_iam_role` | `${prefix}-budgets-action` | Rol de ejecución de Budgets (trust `budgets.amazonaws.com`, lleva la permissions boundary `${prefix}-boundary`). Solo puede adjuntar y quitar la política Deny a los roles de `role_names`. |
| `aws_budgets_budget_action` | sobre `${prefix}-mensual` | Al 60 % de gasto real (`action_threshold`), adjunta la política Deny a `role_names` (AUTOMATIC) y envía email. |
| `aws_budgets_budget_action` | `detener_vm` (si hay `instance_ids`) | Al mismo umbral detiene la VM de Airflow con SSM (`STOP_EC2_INSTANCES`, AUTOMATIC). |

`role_names` lo arma el root: el rol de GitHub `${prefix}-github-actions` (bootstrap) y, si `enable_airflow = true`, el rol `${prefix}-airflow-vm`.

No hay Lambda. Budgets actúa solo.

## Limitaciones

- Budgets actualiza los datos de costo como mínimo una vez al día. La acción puede tardar hasta ~24 h en dispararse. No es un tope en tiempo real: los topes duros son los del pipeline (workers, timeout, `MaxConcurrentRuns`, límite de bytes de Athena).
- Budgets bloquea roles, no al usuario humano. El Deny afecta también al rol de GitHub, así que `terraform apply` de recursos Glue/EC2 fallará mientras esté activo.
- No está verificado si el presupuesto cuenta gasto bruto o neto de créditos del plan free.

## Prerrequisitos en el rol que aplica Terraform

El rol de GitHub (`${prefix}-github-actions`) y el de SageMaker los reciben del bootstrap:

- `budgets:*` (PowerUserAccess).
- `iam:PassRole` sobre `${prefix}-*` con `iam:PassedToService = budgets.amazonaws.com` (entre otros servicios).
- `iam:CreateRole` / `AttachRolePolicy` / `PutRolePolicy` solo con la boundary `${prefix}-boundary`, y creación de políticas `${prefix}-*`.
- La boundary permite además `iam:AttachRolePolicy` / `DetachRolePolicy` de `${prefix}-bloqueo-presupuesto` sobre roles `${prefix}-*`, que hace el rol de la acción, y `ec2:Describe*` + `iam:PassRole` de `${prefix}-budgets-action` a SSM para detener la VM.

Estos permisos no se verificaron contra cuenta real (no se hizo `plan` ni `apply`): son de la lista de la Fase V.

## Desbloquear (`make desbloquear`)

Cuando la acción se dispara, los roles quedan con el Deny adjunto y el cómputo falla con `AccessDenied`. Para desbloquear hay que quitar la política de cada rol afectado:

```bash
POLICY_ARN=arn:aws:iam::<ACCOUNT_ID>:policy/bigdata-bloqueo-presupuesto
for ROLE in bigdata-github-actions bigdata-airflow-vm; do
  aws iam detach-role-policy --role-name "$ROLE" --policy-arn "$POLICY_ARN" || true
done
```

Sustituir `bigdata` por el valor de `prefix`. `make desbloquear` hace lo equivalente con `aws budgets execute-budget-action --execution-type REVERSE_BUDGET_ACTION` (con confirmación).

Antes de desbloquear, revisar el gasto en Cost Explorer. Si el gasto sigue por encima del 60 %, la acción puede volver a dispararse cuando Budgets reevalúe. Para subir el tope, cambiar `budget_usd` y aplicar de nuevo.

## Variables

| Variable | Default | Descripción |
|---|---|---|
| `prefix` | - | Prefijo de nombres. |
| `budget_usd` | `50` | Presupuesto mensual en USD. |
| `alert_email` | - | Destinatario de alertas y de la acción. |
| `role_names` | - | Roles que reciben el Deny (no vacío). |
| `alert_thresholds` | `[50, 80]` | Umbrales de alerta por email. |
| `action_threshold` | `60` | Umbral del Deny. |
