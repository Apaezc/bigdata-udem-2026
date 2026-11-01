# Integración de la Fase 3

> **Nota (2026-11-01):** registro histórico de la integración de la Fase 3. Partes reemplazadas por el rediseño de
> entornos: dataset FHVHV en lugar de yellow, entornos local/dev/prod, DAG por entorno sin rama `snowpark_connect`,
> VM de prod sin EIP ni workflows `permitir-ip`/`quitar-ips`, presupuestos sin créditos y alertas sin duplicar.
> El estado vigente está en [README.md](../README.md) y [CONTRATO.md](../CONTRATO.md).

Resultado de integrar los componentes del template (bootstrap, `infra/aws`, `infra/snowflake`, `airflow/`, `src/`, workflows, scripts y Makefile) escritos en paralelo según [CONTRATO.md](../CONTRATO.md). Todo se validó solo en local: no se hizo ninguna llamada a AWS ni a Snowflake (sin `terraform plan/apply`, sin `aws` contra la cuenta, sin `snow`).

## 1. Cambios hechos

### Coherencia de nombres y referencias cruzadas
- VM de Airflow: tag `Name=${prefix}-airflow` (lo buscan `scripts/lib.sh`, `airflow-on/off`, `estado`) y tag `Project=${prefix}` (condición SSM del bootstrap); security group `${prefix}-airflow-sg` (lo buscan `permitir-ip.yml` y `quitar-ips.yml`). Antes la instancia y el SG se llamaban `${prefix}-airflow-vm`; el rol y el instance profile conservan `${prefix}-airflow-vm`.
- Secreto `${prefix}/snowflake`: estaba en el contrato y en la política de la VM pero no existía en Terraform. Ahora `airflow_vm` crea el contenedor y la VM arma la conexión `snowflake_default` desde él.
- Variable de Airflow `prefix`: la VM la fija con `AIRFLOW_VAR_PREFIX` (los DAGs arman `${prefix}-small|medium|large`).
- `run_glue.py`: pedía `--engine` como obligatorio, pero ni el job de Glue ni Airflow lo pasan. Ahora el engine es siempre `glue`; además se corrigió la conversión `lake_bucket` -> `--lake-bucket` y el job recibe `--lake-bucket` por defecto (antes `dev.yaml` no podía resolver `{lake_bucket}` en Glue). Test nuevo `tests/test_run_glue.py`.
- Glue: la política de `${prefix}-glue-exec` agrega `s3:AbortMultipartUpload`, métricas de CloudWatch (namespace `Glue`) y los prefijos sin barra final en `ListBucket`.
- Gold: la partición era `fecha`, y una columna de partición no queda dentro del Parquet; `COPY ... MATCH_BY_COLUMN_NAME` habría cargado `FECHA` nula. Ahora gold se escribe en `gold/daily_zone_metrics/mes=YYYY-MM/` (partición derivada `mes`), con las 7 columnas del contrato dentro del archivo y en orden. Test nuevo que lo comprueba.
- `copy_gold.sql`: `DELETE` del mes + `COPY INTO ... MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE ... FORCE = TRUE` desde `mes={{ params.mes }}/`. Tipos: FECHA DATE, ZONA VARCHAR, VIAJES NUMBER(38,0), resto FLOAT. Reprocesar un mes es idempotente.
- DAG `pipeline_taxi`: `cargar_gold` ahora solo cuelga de la rama Glue (la rama `snowpark_connect` escribe directo en Snowflake; con el `DELETE` por mes la rama Snowpark habría quedado borrada). Test actualizado.
- `GlueJobOperator` con `verbose=False`: con `True` lee CloudWatch Logs y el rol de la VM no tiene (ni debe tener, por contrato) permisos de logs; el task habría fallado con `AccessDenied`.
- `lake`: se quitan los marcadores `code/` y `dags/` de `aws_s3_object` porque `aws s3 sync --delete` los borraría en cada deploy y Terraform los recrearía.
- Versiones de GitHub Actions verificadas contra los releases reales con `gh` (checkout v7, setup-python v7, setup-java v6, setup-terraform v4, configure-aws-credentials v6.3.0).

### Deploy (`deploy.yml` y `scripts/deploy.sh`)
Suben `pipeline.zip` (con la carpeta `pipeline/` en la raíz del zip) -> `code/pipeline.zip`, `run_glue.py` -> `code/run_glue.py`, `airflow/dags` -> `dags/`, `airflow/framework` -> `code/airflow/framework/` y `docker-compose.yaml` -> `code/airflow/docker-compose.yaml`.
La VM instala `/usr/local/bin/airflow-refresh.sh` (user_data), que copia compose, framework y DAGs a `/opt/airflow/` y arma `snowflake.env`; corre al crear la VM y antes de cada arranque de `airflow.service` (la VM se apaga y enciende a diario), y por cron cada minuto sincroniza `dags/` y `framework/`. El compose monta `./framework` y fija `PYTHONPATH=/opt/airflow`; el DAG hace `sys.path.insert` de la carpeta padre de `dags/`.

### Bootstrap: permissions boundary y OIDC
- Política `${Prefix}-boundary` (techo: S3 del prefijo, Glue, logs/métricas, `GetSecretValue` de `${Prefix}/*`, SSM, `ec2:StopInstances`, adjuntar/quitar solo `${Prefix}-bloqueo-presupuesto`).
- `${Prefix}-terraform-access` reescrita: `iam:CreateRole`, `PutRolePolicy`, `AttachRolePolicy`, `PutRolePermissionsBoundary` sobre `role/${Prefix}-*` solo con `iam:PermissionsBoundary = ...:policy/${Prefix}-boundary`; `iam:PassRole` limitado por `iam:PassedToService` a `glue`, `ec2`, `scheduler` y `budgets` (para el rol de la acción de Budgets); Deny explícito para `AdministratorAccess`/`IAMFullAccess`/`PowerUserAccess`, `DeleteRolePermissionsBoundary`, alterar las políticas `boundary` y `terraform-access`, y modificar los roles `github-actions` y `sagemaker-exec`.
- Terraform: variable `permissions_boundary_arn` (default null = se arma con cuenta y prefijo) pasada a lake, glue, airflow_vm y guardrails; la llevan los 5 `aws_iam_role` (`snowflake-s3`, `glue-exec`, `airflow-vm`, `airflow-stop-scheduler`, `budgets-action`). Se eliminó la política `${prefix}-airflow-boundary` propia de `airflow_vm` (la sustituye la compartida).
- Parámetro `ExistingGitHubOidcProviderArn` (vacío = crea el provider; con valor lo reutiliza). Nuevo output `PermissionsBoundaryArn`.

### Configuración de Terraform en S3 (`config/aws.tfvars`)
Las variables de `infra/aws` que dependen del alumno (`alert_email`, `enable_glue`, `enable_airflow`, `snowflake_iam_user_arn`, `snowflake_external_id`, además de `prefix` y `aws_region`) viven en `s3://<TF_STATE_BUCKET>/config/aws.tfvars`. `make setup` la crea si no existe (con `enable_airflow = false`); `make config` la muestra. `deploy.sh`, `deploy.yml` y `ci.yml` la descargan con `config_pull` (`scripts/lib.sh`) y planifican con `-var-file`, así local y CI aplican exactamente lo mismo. Ya no hay `ALERT_EMAIL`, `ENABLE_*` ni `SNOWFLAKE_*` en `.env` ni en variables del fork; por eso el plan de GitHub Actions no intenta destruir Airflow ni revertir la trust de Snowflake.
La fase 2 de Snowflake la escribe `make snowflake` (`config_set` con los outputs de `infra/snowflake`). Sin esos valores, la trust policy del rol queda en fase 1.

### Guardia de destrucción
`deploy.sh` y `deploy.yml` guardan el plan con `-out`, lo leen con `terraform show -json` y abortan si hay acciones `delete` (o reemplazos), listando los recursos. Se permite con `CONFIRMAR_DESTRUCCION=true` (script) o con el input `confirmar_destruccion` (workflow manual). `make destroy` no usa esta guardia.

### `scripts/destroy.sh`
Vacía el lake -> `terraform destroy` de `infra/snowflake` (necesita `terraform.tfvars` y la llave; si faltan avisa y sigue) -> `terraform destroy` de `infra/aws` -> opcional (segunda confirmación escrita o `INCLUIR_BOOTSTRAP=si`) borra el stack de bootstrap y vacía (todas las versiones y marcadores) y borra el bucket de state. Confirmación escrita `destruir <prefix>`.

### Snowflake
- `FUTURE TABLES` y `FUTURE VIEWS` `SELECT` para `BIGDATA_DEV` en BRONZE, SILVER y GOLD (`dev_future_select`).
- La asignación de `BIGDATA_RM` al warehouse requiere `ACCOUNTADMIN`: se quitó de Terraform (`ignore_changes = [resource_monitor]`) y de los grants de `TERRAFORM_ROLE`; `01_admin.sql` ejecuta `ALTER WAREHOUSE IF EXISTS BIGDATA_WH SET RESOURCE_MONITOR = BIGDATA_RM` (orden: 01_admin -> `make apply` -> volver a ejecutar 01_admin; el `ALTER ACCOUNT` ya cubre desde el inicio).

### Calidad
`ruff format` aplicado (airflow/framework y airflow/dags); `ruff check` y `ruff format --check` en todo el repo, también en CI. CI nuevo job `airflow-dags` (instala Airflow 3.3.2 con los constraints y corre `airflow/tests`). `make test` corre los tests de DAGs si Airflow está instalado. Se agregó `infra/aws/.terraform.lock.hcl` (4 plataformas).

### Documentación
`README.md` raíz (arquitectura, quickstart, targets, costos, troubleshooting), `CONTRATO.md` (SG `etiqueta;fecha`, `MaxConcurrentRuns = 3`, Glue 5.0, Deny `${prefix}-bloqueo-presupuesto`, boundary, deploy y variables), `docs/bootstrap.md`, `airflow/README.md`, `infra/snowflake/README.md`, README de guardrails y `terraform.tfvars.example`.

## 2. Resultados de la validación local

| Validación | Resultado |
|---|---|
| `cfn-lint bootstrap/cloudformation/bootstrap.yaml` | OK, sin hallazgos |
| `terraform fmt -check -recursive infra` | OK |
| `terraform init -backend=false` + `validate` en `infra/aws` (copia en scratch, Terraform 1.17) | OK |
| `terraform init -backend=false` + `validate` en `infra/snowflake` (copia en scratch) | OK |
| `pytest` (`tests/`, PySpark 3.5.6 local, Java 17) | 27 passed |
| `pytest airflow/tests` (Airflow 3.3.2 real con constraints, Python 3.11) | 6 passed |
| `ruff check .` y `ruff format --check .` | OK (28 archivos) |
| `actionlint` (7 workflows, con shellcheck integrado) | OK |
| `shellcheck -x scripts/*.sh bootstrap/snowflake/gen_key.sh` y `user_data.sh.tftpl` renderizado | OK |
| `docker-compose -f airflow/docker-compose.yaml --env-file airflow/.env.example config -q` | OK (también con un `snowflake.env` de prueba: conserva el JSON con `\n`) |
| `make -n` de los 14 targets (incluido `help`) | OK |
| `make test` | OK (omite `airflow/tests` si Airflow no está instalado, con aviso) |
| Búsqueda de IDs de cuenta de 12 dígitos, correos y claves privadas | Sin hallazgos (solo placeholders `example.com` / `ejemplo.com` y un PEM de ejemplo con `...` en el README de Airflow) |
| Repo sin `.terraform`, `tfstate`, `.env` | Verificado |

No se pudo validar sin credenciales: `terraform plan`, sintaxis de IAM contra el servicio real, creación del stack de CloudFormation, ejecución en Glue, arranque de la VM, `COPY INTO` y aplicación del stack de Snowflake.

## 3. A validar en Fase V (supuestos no verificados, por prioridad)

### P0: bloquean el flujo si fallan
1. **Lanzar el stack de bootstrap en una cuenta real** (`us-east-2`): propiedades del SageMaker Domain/UserProfile/Space (`CodeEditorAppSettings`, `AppLifecycleManagement`, 60 min), la Lambda de limpieza al borrar, y que `ExistingGitHubOidcProviderArn` funcione en una cuenta que ya tiene el provider.
2. **`terraform apply` real con el rol `github-actions` y con el de SageMaker**: que la boundary y `terraform-access` cubran todas las acciones IAM y de servicio que usa el provider AWS 6 (lectura de roles/políticas/instance profiles, `iam:PassRole` con `iam:PassedToService`, `CreateRole` solo con boundary, creación del Budget action, `scheduler:*`, `iam:CreateServiceLinkedRole`, tags de roles). El Deny de `modificar roles del bootstrap` puede chocar con algún flujo no previsto.
3. **Claim `sub` del OIDC** (`repo:owner/repo` frente a la forma numérica `owner@id/repo@id`) y que `permitir-ip`/`airflow-on` asuman el rol. El workflow `debug-oidc` sirve para esto.
4. **Job Glue 5.0 de punta a punta** (`bronze` -> `silver` -> `gold`, un mes): `pyyaml` disponible en la imagen de Glue 5.0 (si no, `--additional-python-modules`), `importlib.resources` leyendo `config/*.yaml` desde `pipeline.zip` en `--extra-py-files`, `getResolvedOptions` con `--lake-bucket`, `GlueContext` y descarga por `urllib` desde el driver, y que las condiciones de prefijo en `s3:ListBucket` (y `AbortMultipartUpload`) alcancen para Spark/boto3 (si falla con `AccessDenied` en listados, ampliar a `s3:prefix` vacío).
5. **Terraform de Snowflake contra una cuenta trial**: recursos `snowflake_storage_integration_aws`, `snowflake_stage_external_s3`, `snowflake_file_format_parquet`, el grant `future` con `fully_qualified_name`, la ruta `describe_output[0].iam_user_arn`, privilegios suficientes de `TERRAFORM_ROLE` (CREATE INTEGRATION, MANAGE GRANTS) y que `ignore_changes = [resource_monitor]` evite el drift; el `ALTER WAREHOUSE IF EXISTS` de `01_admin.sql` y la coexistencia con `ALTER ACCOUNT SET RESOURCE_MONITOR`.
6. **Dos fases AWS <-> Snowflake**: que la trust policy con `STORAGE_AWS_IAM_USER_ARN` / `EXTERNAL_ID` permita el `COPY INTO`, y que `make snowflake` / `deploy.yml` conserven la fase 2 desde `config/aws.tfvars`.
7. **`COPY INTO` real** desde `@BIGDATA.GOLD.LAKE_GOLD/daily_zone_metrics/mes=<mes>/` (ruta entre comillas) con `MATCH_BY_COLUMN_NAME`, tipos `date32`/`long`/`double` de Spark y `FORCE = TRUE`; que `{{ params.mes }}` se renderice dentro del `.sql` y que `split_statements` ejecute los tres statements.

### P1: afectan la experiencia pero hay rodeo
8. **VM de Airflow en Amazon Linux 2023**: `docker-compose-plugin` por `dnf` o el binario de GitHub, `env_file` con `required: false` (Compose >= 2.24) y el build inline de la imagen, variables de Airflow 3.3.2 (`AIRFLOW__API_AUTH__JWT_SECRET`, `AIRFLOW__CORE__SIMPLE_AUTH_MANAGER_*` y formato del archivo de contraseñas), healthcheck `/api/v2/version`, memoria (4.3 GB + swap) y el cron de sincronización.
9. **Conexión Snowflake de Airflow**: `private_key_content` en el provider 6.17, formato del JSON del secreto, y que el usuario tenga `BIGDATA_DEV` y una clave registrada (hay que decidir si el curso crea un usuario de servicio `AIRFLOW_SVC` en `01_admin.sql`).
10. **Guardrails**: semántica de `aws_budgets_budget_action` (60 % real, `AUTOMATIC`), que Budgets pueda adjuntar el Deny con el rol `${prefix}-budgets-action` limitado por boundary, el efecto sobre el rol `github-actions` y `make desbloquear` (`REVERSE_BUDGET_ACTION`). No se sabe si el presupuesto cuenta bruto o neto de créditos del plan free.
11. **Acceso a Airflow**: `ssm:StartSession` con la condición `ssm:resourceTag/Project`, el plugin en el Code Editor, y si la URL proxy de Studio `.../codeeditor/default/proxy/8080/` existe. Que el SG acepte la descripción `etiqueta;fecha` (carácter `;` permitido) y el límite de 3 reglas con varios alumnos.
12. **Tipos de instancia del plan free**: `m7i-flex.large` (y fallback `c7i-flex.large`) disponibles en la cuenta y sin cargo; costo de la IP elástica con la VM apagada.
13. **CI**: la instalación de `airflow/requirements.txt` en `ubuntu-latest` con Python 3.11 (tiempo y resolución) y el `terraform plan` en PRs del propio repo.

### P2: menores
14. ~~Alertas duplicadas~~ Resuelto: `${Prefix}-total` (bootstrap) solo alerta al 100 %; `${prefix}-mensual` (Terraform) alerta al 40/80 % y su acción al 60 % bloquea roles y detiene la VM.
15. Los secrets `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`, `SNOWFLAKE_PRIVATE_KEY` del contrato no los usa ningún workflow (`infra/snowflake` se aplica desde la terminal).
16. La rama `snowpark_connect` del DAG no funciona en la VM (la imagen no trae `src/` ni el paquete de Snowpark Connect; nombre de paquete no verificado).
17. Los logs de Glue no aparecen en la UI de Airflow (`verbose=False`); decidir si se amplía el rol de la VM con lectura de `/aws-glue/jobs/*`.
18. Enlaces a la consola de Glue y al Spark UI en el log de la tarea (formato marcado como no verificado en `tasks.py`).
19. `make setup` extrae la región con `snow sql` y una expresión regular sobre la salida; confirmar con el formato real de `snow`.
