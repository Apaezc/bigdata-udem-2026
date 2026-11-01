# Bootstrap de la cuenta AWS

Este paso se hace una sola vez por alumno, desde la consola de AWS, con la cuenta de prueba (región `us-east-2`). Crea con CloudFormation (`bootstrap/cloudformation/bootstrap.yaml`):

- SageMaker Domain en la VPC por defecto, con autenticación IAM y Code Editor.
- Usuario `estudiante` y Space `dev` (Code Editor, `ml.t3.large` de 8 GB, 20 GB EBS; se puede bajar a `ml.t3.medium` desde Studio). Apagado por inactividad a los 60 min.
- Rol de ejecución de SageMaker, con permisos para ejecutar Terraform sobre recursos `${prefix}-*`.
- Proveedor OIDC de GitHub (si no lo tienes ya) y rol `${prefix}-github-actions` para GitHub Actions (sin claves de acceso).
- Política `${prefix}-boundary` (permissions boundary). Terraform solo puede crear roles `${prefix}-*` que la lleven, y tiene prohibido adjuntar `AdministratorAccess`, quitar el boundary o alterar las políticas de gobierno.
- Bucket de state de Terraform (versionado, cifrado, sin acceso público, no se borra con el stack).
- Presupuesto `${prefix}-total` (gasto bruto) con alerta al 100 % como red de seguridad.
- Lambda que, al borrar el stack, elimina apps, spaces y user profiles del dominio antes de borrarlo.

Nota: este paso no crea Snowflake ni los recursos de `infra/aws/` (eso lo hace Terraform después).

## 1. Generar tu enlace (sin copiar IDs)

1. Haz fork del repositorio y habilita Actions en el fork.
2. En el fork: **Actions > "Enlace de bootstrap" > Run workflow** (rama `main`).
3. Abre el run terminado: el resumen trae el enlace **Launch Stack** con `GitHubOwner`, `GitHubOwnerId`,
   `GitHubRepo` y `GitHubRepoId` ya completados con los datos de **tu fork**. No los cambies.

## 2. Lanzar el stack

1. Entra a la consola de AWS con tu usuario administrador, región **US East (Ohio) `us-east-2`**.
2. Abre el enlace. En el formulario completa solo:
   - **VpcId**: la VPC que dice *default*.
   - **SubnetIds**: marca todas las subnets de esa VPC.
   - **AlertEmail**: tu correo (confirma la suscripción que te llega).
3. Marca *I acknowledge that AWS CloudFormation might create IAM resources with custom names* y pulsa
   **Create stack**. Espera `CREATE_COMPLETE` (~4 min).

Si la cuenta ya tiene el proveedor OIDC de GitHub, el stack falla con `EntityAlreadyExists`: bórralo y
relánzalo con `ExistingGitHubOidcProviderArn` (ver "Problemas frecuentes").

## 3. Secrets del fork (automáticos)

No copies outputs a mano. En el Code Editor, después de clonar tu fork, `make setup` carga
`AWS_ROLE_ARN` y `TF_STATE_BUCKET` en el fork leyendo los outputs del stack. La primera vez autentica
GitHub (`gh auth login --hostname github.com --git-protocol https --web`) y corre `make secrets`.

## 4. Para el instructor

El enlace apunta a la plantilla en `s3://bigdata-udem-2026-publico/bootstrap/` (versionado, solo
lectura, solo usuarios autenticados de AWS: sin descargas anónimas). Después de cada cambio en
`bootstrap/cloudformation/bootstrap.yaml`: `make publicar-bootstrap` (publica una versión nueva, fija
el enlace del workflow a esa versión y deja el cambio listo para commit). Al cerrar la semana de
inscripción: `make retirar-bootstrap` (borra todas las versiones; los enlaces dejan de funcionar).

## 5. Abrir Code Editor

1. Abre `StudioConsoleUrl`, o ve a SageMaker > Domains > `${prefix}-studio`.
2. Abre el perfil `estudiante` (**Open Studio**).
3. En Studio, abre el Space `dev` y ejecútalo como **Code Editor**.
4. En la terminal del Space puedes comprobar la identidad con `aws sts get-caller-identity`. Debe mostrar el rol `${prefix}-sagemaker-exec`.

Terraform se ejecuta desde esa terminal con las credenciales del rol de ejecución. Las instancias que Terraform cree (por ejemplo, la VM de Airflow) deben tener la etiqueta `Project=<prefix>`. Sin ella, la sesión SSM no las alcanza.

## 6. Borrar el stack al terminar

Lo más simple: `make destroy`. Vacía el lake, destruye Snowflake y AWS (Terraform) y, si lo confirmas, borra también el stack `bigdata-bootstrap` y el bucket de state (vaciando todas sus versiones).

Confirmaciones del script (hay que escribirlas en una terminal interactiva):

1. Antes de destruir nada, escribe `destruir <prefix> <cuenta>`, con tu prefijo (`bigdata` por defecto) y el ID de tu cuenta AWS. El script muestra ambos antes de pedir la confirmación: si no son los tuyos, no escribas la frase y cancela con Ctrl-C.
2. Después, si quieres borrar también el bootstrap, responde `si` a la pregunta. Luego escribe `borrar bootstrap <prefix>`. Si respondes `no`, el stack y el bucket de state se quedan.

Desde el Code Editor puedes correrlo y responder `no` a la pregunta del bootstrap. Para borrar también el bootstrap, usa una terminal local que tenga `infra/snowflake/terraform.tfvars` y la llave de Snowflake (`~/.snowflake/keys/terraform_svc_rsa_key.p8`): el borrado elimina el dominio de SageMaker y, con él, tu Code Editor. Si falta el `terraform.tfvars` o la llave, el script omite el destroy de Snowflake con un aviso; no lo ignores, porque entonces Snowflake queda sin borrar.

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
