# Bootstrap de la cuenta AWS

Este paso se hace una sola vez por alumno, desde la consola de AWS, con la cuenta de prueba (región `us-east-2`). Crea con CloudFormation (`bootstrap/cloudformation/bootstrap.yaml`):

- SageMaker Domain en la VPC por defecto, con autenticación IAM y Code Editor.
- Usuario `estudiante` y Space `dev` (Code Editor, `ml.t3.large` de 8 GB, 20 GB EBS; se puede bajar a `ml.t3.medium` desde Studio). Apagado por inactividad a los 60 min.
- Rol de ejecución de SageMaker, con permisos para ejecutar Terraform sobre recursos `${prefix}-*`.
- Proveedor OIDC de GitHub (si no lo tienes ya) y rol `${prefix}-github-actions` para GitHub Actions (sin claves de acceso).
- Política `${prefix}-boundary` (permissions boundary). Terraform solo puede crear roles `${prefix}-*` que la lleven, y tiene prohibido adjuntar `AdministratorAccess`, quitar el boundary o alterar las políticas de gobierno.
- Bucket de state de Terraform (versionado, cifrado, sin acceso público, no se borra con el stack).
- Presupuesto mensual con alertas al 50, 80 y 100 %.
- Lambda que, al borrar el stack, elimina apps, spaces y user profiles del dominio antes de borrarlo.

Nota: este paso no crea Snowflake ni los recursos de `infra/aws/` (eso lo hace Terraform después).

## 1. Datos de tu fork

Haz fork del repositorio en tu cuenta de GitHub. Anota el dueño (`OWNER`) y el nombre (`REPO`) del fork.

Obtén los IDs numéricos. Son el dueño y el repositorio del **fork**, no de la plantilla:

```bash
curl -s https://api.github.com/repos/OWNER/REPO | jq '{owner: .owner.login, owner_id: .owner.id, repo: .name, repo_id: .id}'
```

Sin `jq`, busca en la respuesta los campos `"id"` dentro de `"owner"` (es `GitHubOwnerId`) y el `"id"` del nivel superior (es `GitHubRepoId`).

## 2. VPC y subnets por defecto

En la consola de VPC, región `us-east-2`, elige la **VPC por defecto** y anota su ID (`VpcId`). Anota al menos dos subnets de esa VPC (`SubnetIds`), de zonas de disponibilidad distintas.

## 3. Lanzar el stack

Abre este enlace (reemplaza `REEMPLAZAR_TEMPLATE_URL` por la URL del template, codificada para URL; por ejemplo, la URL *raw* de `bootstrap/cloudformation/bootstrap.yaml` en tu fork):

```
https://us-east-2.console.aws.amazon.com/cloudformation/home?region=us-east-2#/stacks/create/review?stackName=bigdata-bootstrap&templateURL=REEMPLAZAR_TEMPLATE_URL
```

Completa los parámetros:

| Parámetro | Valor |
|---|---|
| `GitHubOwner` | Dueño del fork (`OWNER`) |
| `GitHubOwnerId` | ID numérico del dueño (paso 1) |
| `GitHubRepo` | Nombre del fork (`REPO`) |
| `GitHubRepoId` | ID numérico del repositorio (paso 1) |
| `VpcId` | VPC por defecto (paso 2) |
| `SubnetIds` | Subnets de la VPC por defecto (paso 2) |
| `Prefix` | `bigdata` (si lo cambias, usa el mismo valor en Terraform) |
| `AlertEmail` | Tu correo para alertas de presupuesto |
| `BudgetUsd` | `50` por defecto |
| `ExistingGitHubOidcProviderArn` | Déjalo vacío. Solo si la cuenta ya tiene el proveedor OIDC de GitHub, pega su ARN (ver "Problemas frecuentes") |

En la sección de capacidades marca **"I acknowledge that AWS CloudFormation might create IAM resources with custom names"**. El stack crea roles y políticas con nombre fijo.

Ejecuta **Submit** y espera a `CREATE_COMPLETE`.

## 4. Copiar los outputs

En la pestaña **Outputs** del stack:

| Output | Dónde va |
|---|---|
| `GitHubActionsRoleArn` | Secret `AWS_ROLE_ARN` de tu fork |
| `TfStateBucket` | Secret `TF_STATE_BUCKET` de tu fork |
| `PermissionsBoundaryArn` | Referencia (Terraform lo arma solo; variable `permissions_boundary_arn`) |
| `DomainId` | Referencia |
| `StudioConsoleUrl` | Abrir SageMaker Studio |
| `SageMakerExecutionRoleArn` | Solo referencia |

Los secrets se configuran en tu fork: **Settings > Secrets and variables > Actions**: `AWS_ROLE_ARN` (output `GitHubActionsRoleArn`) y `TF_STATE_BUCKET` (output `TfStateBucket`). Sin ellos, `ci.yml` y `deploy.yml` fallan con un mensaje claro (en PRs desde forks el plan se omite a propósito). Los secrets de Snowflake se configuran aparte.

La configuración de Terraform (correo de alertas del paso 3 = `AlertEmail`, Airflow, Glue y la fase 2 de Snowflake) no va en GitHub: `make setup` la guarda en `s3://<TfStateBucket>/config/aws.tfvars` (ver [README](../README.md#configuración-por-estudiante)).

## 5. Abrir Code Editor

1. Abre `StudioConsoleUrl`, o ve a SageMaker > Domains > `${prefix}-studio`.
2. Abre el perfil `estudiante` (**Open Studio**).
3. En Studio, abre el Space `dev` y ejecútalo como **Code Editor**.
4. En la terminal del Space puedes comprobar la identidad con `aws sts get-caller-identity`. Debe mostrar el rol `${prefix}-sagemaker-exec`.

Terraform se ejecuta desde esa terminal con las credenciales del rol de ejecución. Las instancias que Terraform cree (por ejemplo, la VM de Airflow) deben tener la etiqueta `Project=<prefix>`. Sin ella, la sesión SSM no las alcanza.

## 6. Borrar el stack al terminar

Lo más simple: `make destroy`. Vacía el lake, destruye Snowflake y AWS (Terraform) y, si lo confirmas, borra también el stack `bigdata-bootstrap` y el bucket de state (vaciando todas sus versiones). Hazlo desde una terminal local o CloudShell: borrar el bootstrap elimina el dominio de SageMaker y, con él, tu Code Editor.

A mano: borra el stack `bigdata-bootstrap` desde CloudFormation (después de `make destroy`). La Lambda elimina antes las apps, spaces y user profiles del dominio. Después CloudFormation borra el dominio.

Lo que **no** se borra solo:

- El bucket de state (`TfStateBucket`) tiene `DeletionPolicy: Retain` y está versionado. `make destroy` con bootstrap lo vacía y lo borra; a mano hay que borrar todas las versiones y marcadores antes del bucket.
- El sistema de archivos EFS del dominio puede quedar retenido. Revísalo en EFS y bórralo a mano si corresponde.
- Los recursos de `infra/aws/` (Terraform) se destruyen antes con `make destroy`.

## Problemas frecuentes

- **`EntityAlreadyExists` en el proveedor OIDC**: la cuenta ya tiene el proveedor `token.actions.githubusercontent.com`. Relanza el stack pasando su ARN en `ExistingGitHubOidcProviderArn` (`arn:aws:iam::<tu cuenta>:oidc-provider/token.actions.githubusercontent.com`; lo ves en IAM > Identity providers). El stack lo reutiliza y no lo crea ni lo borra.
- **`AccessDenied` al crear un rol con Terraform**: el rol debe llevar la boundary `${prefix}-boundary` (Terraform ya la asigna). Si añades un `aws_iam_role` propio, agrega `permissions_boundary = var.permissions_boundary_arn`. Con `iam:AttachRolePolicy` de `AdministratorAccess` el Deny es intencional.
- **`DELETE_FAILED` en `DomainCleanup`**: revisa los logs de la función `CleanupFunction` en CloudWatch Logs y vuelve a ejecutar el borrado del stack.
- **Error de subnets o de VPC**: las subnets deben pertenecer a la VPC elegida y estar en `us-east-2`.
