# infra/snowflake

Infraestructura de Snowflake del curso: warehouse `BIGDATA_WH`, base `BIGDATA` (esquemas `BRONZE`, `SILVER`, `GOLD` para SQL; `DEV` y `PROD` para el pipeline), rol `BIGDATA_DEV`, usuario de servicio `AIRFLOW_SVC`, integración S3 `BIGDATA_S3_INT` y stage `BIGDATA.GOLD.LAKE_GOLD` sobre `s3://<lake>/gold/`.

Terraform >= 1.10, provider `snowflakedb/snowflake` ~> 2.0, autenticación por key-pair (`SNOWFLAKE_JWT`). El resource monitor `BIGDATA_RM` lo crea y asigna a la cuenta `bootstrap/snowflake/01_admin.sql` con ACCOUNTADMIN, no Terraform (asignar un monitor requiere ACCOUNTADMIN; el warehouse lo ignora con `ignore_changes`).

`BIGDATA_DEV` recibe USAGE/CREATE en los schemas y `SELECT` sobre las tablas y vistas futuras (`FUTURE TABLES` / `FUTURE VIEWS`) de BRONZE, SILVER y GOLD.

## Orden de las dos fases

El stack de AWS y el de Snowflake dependen uno del otro. El orden es obligatorio:

1. **AWS fase 1** (`infra/aws`): crea el bucket del lake y el rol IAM `bigdata-snowflake-s3` con una trust policy placeholder. Anotar los outputs `lake_bucket` y `snowflake_s3_role_arn`.
2. **Snowflake** (esta carpeta):
   - `bootstrap/snowflake/gen_key.sh` genera el par de llaves.
   - `bootstrap/snowflake/01_admin.sql` se ejecuta en Snowsight como ACCOUNTADMIN, con la clave pública pegada.
   - Terraform crea también el usuario de servicio `AIRFLOW_SVC` (con el rol `BIGDATA_DEV`). Su llave la genera el Makefile la primera vez (`make airflow-key`, que llama a `gen_key.sh AIRFLOW_SVC`): privada en `~/.snowflake/keys/airflow_svc_rsa_key.p8` y pública en `airflow_svc_rsa_key.pub`. La pública se pasa a Terraform como `TF_VAR_airflow_public_key`. No hay que crear el usuario a mano.
   - `make init`, `make plan`, `make apply`, si trabajas solo en esta carpeta. Anotar los outputs `storage_aws_iam_user_arn` y `storage_aws_external_id`. Desde la raíz, `make snowflake` ya hace el `init` y el `apply`.
3. **AWS fase 2** (`infra/aws`): desde la raíz del repo, `make snowflake`. Hace `terraform init` (con `-reconfigure`), aplica este stack (`make -C infra/snowflake apply`), lee los dos outputs, los guarda en la configuración de AWS en S3 (`snowflake_iam_user_arn` y `snowflake_external_id`, con `config_set`) y ejecuta `make deploy` para actualizar la trust policy del rol (`Principal` y `sts:ExternalId`). Al final escribe la conexión de Airflow en el secreto `<prefix>/snowflake` (`scripts/snowflake-secreto.sh`). No hay que copiar valores a `.env` ni a variables del fork. Con `SIN_DEPLOY=true make snowflake` solo se actualiza la configuración y el secreto (si el secreto aún no existe, corre `make deploy` y después `make snowflake-secreto`).

   Dos casos especiales:
   - **`AIRFLOW_SVC` creado a mano** (no por Terraform): el comando se detiene con un error, porque el apply fallaría con `already exists`. En Snowsight, como ACCOUNTADMIN, ejecuta `DROP USER AIRFLOW_SVC;` y repite `make snowflake`. Terraform lo recrea con la llave de `~/.snowflake/keys/airflow_svc_rsa_key.pub`.
   - **`TERRAFORM_ROLE` sin `CREATE USER`** (cuentas ya bootstrapeadas): `make snowflake` lo concede con la conexión `snow` como ACCOUNTADMIN. Si falla, ejecuta tú `GRANT CREATE USER ON ACCOUNT TO ROLE TERRAFORM_ROLE;` como ACCOUNTADMIN.
4. **Resource monitor**: no hay paso adicional. `01_admin.sql` lo asigna a la cuenta (`ALTER ACCOUNT`) y eso cubre a `BIGDATA_WH` desde que existe; Snowflake no permite asignarlo además al warehouse mientras esté a nivel de cuenta.

Snowflake necesita que el rol exista antes de crear la integración, y la trust policy necesita los valores que genera Snowflake. Por eso son dos pasadas.

## Pasos

### 0. Llaves y bootstrap (una vez)

```bash
bootstrap/snowflake/gen_key.sh          # crea ~/.snowflake/keys/terraform_svc_rsa_key.p8 y .pub
```

El script imprime la clave pública en una línea. Pegarla entre las comillas de `RSA_PUBLIC_KEY` dentro de `bootstrap/snowflake/01_admin.sql` y ejecutar el script completo en Snowsight como ACCOUNTADMIN (con **Run All**). Si el usuario `TERRAFORM_SVC` ya existe con otra llave, `01_admin.sql` no cambia su clave (usa `CREATE USER IF NOT EXISTS`): ejecuta el `ALTER USER` que imprime `gen_key.sh` con la clave pública nueva. Sin eso, `make snowflake` falla con `JWT token is invalid`. Comprueba con `DESC USER TERRAFORM_SVC` que `RSA_PUBLIC_KEY_FP` coincide con el fingerprint que imprime `gen_key.sh`.

La llave de `AIRFLOW_SVC` no va aquí: `make airflow-key` (o `make snowflake`) la genera sola.

### 1. Terraform

```bash
cd infra/snowflake
cp backend.hcl.example backend.hcl                  # bucket = output TfStateBucket del bootstrap AWS
cp terraform.tfvars.example terraform.tfvars        # organization_name, account_name, s3_role_arn, lake_bucket
make init
make plan
make apply
make outputs                                        # storage_aws_iam_user_arn, storage_aws_external_id
```

`backend.hcl` y `terraform.tfvars` no se versionan (están en `.gitignore`). La llave privada no va en `tfvars`: el Makefile la lee de `KEY` (por defecto `~/.snowflake/keys/terraform_svc_rsa_key.p8`) y la pasa como `TF_VAR_private_key`.

### Comandos make

| Target | Qué hace |
|---|---|
| `make help` | Lista los targets |
| `make init` | `terraform init` con backend S3 (`backend.hcl`) |
| `make fmt` / `make fmt-check` | Formatea / verifica formato (CI) |
| `make validate` | `terraform validate` |
| `make plan` / `make apply` | Requiere la llave privada en `KEY` |
| `make airflow-key` | Genera la llave de `AIRFLOW_SVC` si falta (no sobrescribe) |
| `make outputs` | Muestra los outputs para la fase 2 de AWS (`storage_aws_*` y `airflow_conexion`, sin la llave) |
| `make destroy` | Destruye los recursos de este stack (no toca `BIGDATA_RM`). Desde la raíz, `make destroy` hace Snowflake y AWS en orden |

Para sobrescribir la llave o el backend: `make plan KEY=/ruta/llave.p8 BACKEND=otro.hcl`.

## Notas

- El secret `SNOWFLAKE_PRIVATE_KEY` está reservado: los workflows de GitHub Actions no lo usan (ver [CONTRATO.md](../../CONTRATO.md)). Terraform local usa `TERRAFORM_SVC` con la llave de `gen_key.sh`.
- Rotar la llave: `gen_key.sh` no sobrescribe. Mover el `.p8` antes de regenerarla y actualizar la clave pública con `ALTER USER ... SET RSA_PUBLIC_KEY` (o `RSA_PUBLIC_KEY_2` para tener dos activas durante el cambio). Actualizar también el secret de GitHub.
- Si cambia el ID de la integración con `CREATE OR REPLACE`, Snowflake genera un nuevo `STORAGE_AWS_EXTERNAL_ID`: repetir la fase 2.
