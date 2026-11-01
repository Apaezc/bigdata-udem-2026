# Contrato de interfaces del template (Fase 3)

Todos los componentes DEBEN usar estos nombres. No incluir IDs de cuenta, correos ni usuarios reales.

## Generales
- Región por defecto: `us-east-2`. Variable Terraform `aws_region`.
- Prefijo: variable `prefix` (default `bigdata`). Nombres: `${prefix}-<recurso>`.
- Python 3.11, PySpark 3.5.6. Glue `GlueVersion = "5.0"` (validado; 5.1 pendiente), WorkerType `G.1X`.
- Free plan AWS: **sin EMR**; EC2 solo tipos elegibles → VM Airflow `m7i-flex.large` (fallback `c7i-flex.large`).

## Bootstrap CloudFormation (`bootstrap/cloudformation/bootstrap.yaml`)
Parámetros: `GitHubOwner`, `GitHubRepo`, `GitHubOwnerId`, `GitHubRepoId` (para `sub` numérico), `VpcId`, `SubnetIds`, `AlertEmail`, `Prefix`, `BudgetUsd`, `ExistingGitHubOidcProviderArn` (opcional; si se pasa, no se crea el provider OIDC).
Crea: SageMaker Domain (VPC por defecto, AuthMode IAM, idle shutdown 60 min), UserProfile `estudiante`, Space CodeEditor `dev` (ml.t3.large), rol de ejecución SageMaker `${Prefix}-sagemaker-exec`, OIDC provider GitHub + rol `${Prefix}-github-actions`, bucket de state `${Prefix}-tfstate-${AWS::AccountId}-${AWS::Region}` (versionado, cifrado, bloqueo público, `Retain`), Budget mensual `${Prefix}-total` (gasto bruto) con alerta al 100 %, Lambda custom resource de limpieza del dominio al borrar.
IAM: política `${Prefix}-terraform-access` (+ PowerUserAccess) en los roles de SageMaker y GitHub, y política `${Prefix}-boundary` (permissions boundary).
- Los roles `${Prefix}-*` solo se pueden crear / modificar con `iam:PermissionsBoundary = arn:aws:iam::<cuenta>:policy/${Prefix}-boundary` (`CreateRole`, `PutRolePolicy`, `AttachRolePolicy`, `PutRolePermissionsBoundary`). Deny explícito: adjuntar `AdministratorAccess`/`IAMFullAccess`/`PowerUserAccess`, quitar el boundary, alterar `${Prefix}-boundary` y `${Prefix}-terraform-access`, y modificar los roles `github-actions` y `sagemaker-exec`.
- `iam:PassRole` sobre `${Prefix}-*` solo hacia `glue`, `ec2`, `scheduler` y `budgets` (`.amazonaws.com`); el último es para el rol de la acción de Budgets.
Outputs: `GitHubActionsRoleArn`, `TfStateBucket`, `PermissionsBoundaryArn`, `SageMakerExecutionRoleArn`, `DomainId`, `StudioConsoleUrl`.

## Terraform AWS (`infra/aws/`)
Backend S3 `use_lockfile = true`, bucket = output `TfStateBucket`, key `aws/terraform.tfstate`.
Módulos: `modules/lake`, `modules/glue`, `modules/airflow_vm`, `modules/guardrails`. Flags: `enable_glue` (default true), `enable_airflow` (default false).
Configuración por estudiante (fuente única de verdad): `s3://<TF_STATE_BUCKET>/config/aws.tfvars` (HCL, bucket de state con versionado). `make deploy`, `make snowflake`, `deploy.yml` y `ci.yml` la descargan (`config_pull` en `scripts/lib.sh`) y la pasan con `-var-file`; no se usan `-var` ni `TF_VAR_*` para estas variables, ni `terraform.tfvars`. Claves: `prefix`, `aws_region`, `alert_email` (obligatoria), `enable_glue`, `enable_airflow`, `snowflake_iam_user_arn` y `snowflake_external_id` (fase 2 de la integración; si faltan, la trust policy del rol de Snowflake queda en fase 1). Funciones de `lib.sh`: `config_pull`, `config_push`, `config_set clave valor` (actualiza o agrega preservando las demás).
Guardia de destrucción: `make deploy` y `deploy.yml` generan el plan con `-out`, lo revisan con `terraform show -json` y abortan si hay acciones `delete` (también reemplazos), salvo `CONFIRMAR_DESTRUCCION=true` (script) o el input `confirmar_destruccion` (workflow manual). `make destroy` no la usa.
- Variable `permissions_boundary_arn` (default: `arn:aws:iam::<cuenta>:policy/${prefix}-boundary`): la llevan TODOS los `aws_iam_role` que crea Terraform (`snowflake-s3`, `glue-exec`, `airflow-vm`, `airflow-stop-scheduler`, `budgets-action`).
- Lake bucket: `${prefix}-lake-${account_id}-${region}` con prefijos `bronze/` (crudo, compartido), `muestra/`, `dev/{silver,gold}/`, `prod/{silver,gold}/`, `gold/` (SQL), `code/ dags/ logs/ tmp/`.
- Glue database: `${prefix}_lake`. Athena workgroup `${prefix}-wg` con límite de 1 GB escaneado por consulta.
- Glue jobs: `${prefix}-small` (2 workers, timeout 10), `${prefix}-medium` (4, 20), `${prefix}-large` (6, 30); `MaxConcurrentRuns = 1` con `JobRunQueuingEnabled` (los siguientes runs esperan en cola); script `s3://<lake>/code/run_glue.py`, `--extra-py-files s3://<lake>/code/pipeline.zip` (zip con la carpeta `pipeline/` en su raíz); argumentos por defecto `--env dev` y `--lake-bucket <lake>`; Airflow agrega `--step`, `--env`, `--mes` y `--limite` (`todos`/`0` = sin valor). El engine siempre es `glue` (lo fija `run_glue.py`). Spark UI y logs continuos activados.
- Rol Glue `${prefix}-glue-exec`: solo su bucket (bronze/silver/gold/code/tmp/logs).
- VM Airflow: rol e instance profile `${prefix}-airflow-vm` (solo glue:StartJobRun/GetJobRun/BatchStopJobRun/GetJob sobre los 3 jobs, s3 read code/ dags/ logs/, secretsmanager GetSecretValue sobre `${prefix}/*`, logs:Get/Filter/DescribeLogStreams sobre `/aws-glue/jobs/*`, SSM managed instance core), permissions boundary `${prefix}-boundary`, instancia con tag `Name=${prefix}-airflow` y `Project=${prefix}` (la sesión SSM exige este tag), SG `${prefix}-airflow-sg` sin ingress (UI solo por túnel SSM), IP pública automática sin EIP, EventBridge Scheduler apagado 23:00 America/Bogota. Es el Airflow de **prod**; el de dev corre en el Code Editor (`scripts/airflow-local.sh`).
- Guardrails: presupuesto `${prefix}-mensual`, política Deny `${prefix}-bloqueo-presupuesto` (glue:StartJobRun, ec2:StartInstances, ec2:RunInstances) que Budgets adjunta a `${prefix}-github-actions`, `${prefix}-sagemaker-exec` y `${prefix}-airflow-vm` al 60 % de gasto real (gasto bruto, sin créditos); al mismo umbral otra acción detiene la VM por SSM mediante el rol `${prefix}-budgets-action`; se revierte con `make desbloquear`.
- Secrets Manager: `${prefix}/airflow-admin` (JSON `username`/`password`, lo crea Terraform) y `${prefix}/snowflake` (JSON de conexión de Airflow `conn_type: snowflake`, usuario `AIRFLOW_SVC` con key pair; Terraform lo crea siempre en `infra/aws` como contenedor vacío y `make snowflake` escribe el valor con `put-secret-value`).
- Outputs: `lake_bucket`, `glue_jobs`, `airflow_instance_id`, `snowflake_s3_role_arn`.

## Terraform Snowflake (`infra/snowflake/`)
Provider `snowflakedb/snowflake` ~> 2.x, auth `SNOWFLAKE_JWT`. Backend S3 key `snowflake/terraform.tfstate`.
- Warehouse `${PREFIX}_WH` XSMALL, auto_suspend 60. Database `${PREFIX}`; schemas `BRONZE`, `SILVER`, `GOLD`.
- Resource monitor `${PREFIX}_RM` (60 créditos, notify 50/75, suspend 90, suspend_immediate 100) — creado y asignado a la cuenta (`ALTER ACCOUNT`, cubre a todos los warehouses) por `bootstrap/snowflake/01_admin.sql` con ACCOUNTADMIN; Terraform no lo asigna (el warehouse ignora `resource_monitor`). Snowflake rechaza asignarlo además al warehouse mientras esté a nivel de cuenta, así que 01_admin.sql se ejecuta una sola vez.
- Rol `BIGDATA_DEV`: USAGE en warehouse/database/schemas, CREATE TABLE/VIEW/STAGE/FILE FORMAT en schemas, USAGE+READ sobre el stage y SELECT sobre FUTURE TABLES / FUTURE VIEWS de BRONZE, SILVER y GOLD.
- Usuario de servicio `AIRFLOW_SVC` (key pair, rol por defecto `BIGDATA_DEV`): lo crea Terraform con la pública de `~/.snowflake/keys/airflow_svc_rsa_key.pub` (el Makefile genera el par con `gen_key.sh` si falta); output `airflow_conexion`. `01_admin.sql` concede `CREATE USER` a `TERRAFORM_ROLE`.
- Storage integration `${PREFIX}_S3_INT` en dos fases (rol IAM `${prefix}-snowflake-s3` creado en infra/aws con trust placeholder → actualizado con `STORAGE_AWS_IAM_USER_ARN` / `EXTERNAL_ID`). Stage `${PREFIX}.GOLD.LAKE_GOLD` → `s3://<lake>/gold/`.

## Pipeline (`src/pipeline/`)
- `run.py --step {bronze,muestra,silver,gold,all} --env {local,dev,prod} --engine {local,glue} [--mes YYYY-MM] [--limite N]`. Sin `--mes`, todos los meses del entorno en una pasada; `all` en local = silver + gold.
- Entornos (`config/<env>.yaml`): local lee `./lake/muestra` (descargada de `s3://<lake>/muestra`) y escribe en `./lake`; dev = 1 mes, prod = 12 meses; bronze compartido, silver/gold bajo `dev/` o `prod/`.
- `muestra.py`: `--step muestra` (Glue, sample reproducible ~100 k filas de todos los meses), `sincronizar` (local) y `aplicar_muestra` (recorte con `--limite`/`muestra.max_rows`).
- `engine.py` crea la SparkSession (`local`, `glue`; `snowpark_connect` solo para el laboratorio de motores); `io.py` define rutas y lectura/escritura.
- `bronze.py`, `silver.py`, `gold.py`: funciones puras `DataFrame -> DataFrame` + `main(spark, cfg, args)`. `quality.py` con chequeos.
- Datos: NYC TLC FHVHV Parquet (`https://d37ci6vzurychx.cloudfront.net/trip-data/fhvhv_tripdata_YYYY-MM.parquet`, ~450 MB/mes), taxi zones CSV, clima Open-Meteo (archive API) JSON.
- Gold: `<env>/gold/daily_zone_metrics/mes=YYYY-MM/*.parquet`. Columnas, en este orden: `fecha` DATE, `zona` VARCHAR, `empresa` VARCHAR (Uber, Lyft...), `viajes` LONG, `ingreso_total` DOUBLE, `propina_promedio` DOUBLE, `distancia_promedio` DOUBLE, `lluvia_mm` DOUBLE. La carpeta `mes=` solo es partición física (permite reprocesar un mes); todas las columnas, incluida `fecha`, van dentro de los Parquet porque Snowflake no lee columnas de partición.
- Snowflake: tablas `BIGDATA.DEV.DAILY_ZONE_METRICS` y `BIGDATA.PROD.DAILY_ZONE_METRICS` (FECHA DATE, ZONA VARCHAR, EMPRESA VARCHAR, VIAJES NUMBER(38,0), INGRESO_TOTAL/PROPINA_PROMEDIO/DISTANCIA_PROMEDIO/LLUVIA_MM FLOAT). `airflow/dags/sql/copy_gold.sql` borra el mes (o vacía la tabla si no hay mes) y hace `COPY INTO ... MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE ... FORCE = TRUE` desde `@BIGDATA.<DEV|PROD>.LAKE_GOLD/daily_zone_metrics/` (reprocesos idempotentes).
- `run_glue.py`: entrypoint de Glue; fija `--engine glue` y delega en `pipeline.run.main`.

## Airflow (`airflow/`)
- Airflow 3.x, `docker-compose.yaml` con LocalExecutor + Postgres (sin Celery/Redis), `PYTHONPATH=/opt/airflow`.
- Despliegue a S3 (`make deploy` / `deploy.yml`): `build/pipeline.zip` → `s3://<lake>/code/pipeline.zip`; `src/pipeline/run_glue.py` → `code/run_glue.py`; `airflow/dags/` → `dags/`; `airflow/framework/` → `code/airflow/framework/`; `airflow/docker-compose.yaml` → `code/airflow/docker-compose.yaml`.
- La VM (`/usr/local/bin/airflow-refresh.sh`, en user_data, antes de cada arranque de `airflow.service` y por cron cada minuto para dags/ y framework/) copia esos objetos a `/opt/airflow/{dags,framework,docker-compose.yaml}` y arma `snowflake.env` (`AIRFLOW_CONN_SNOWFLAKE_DEFAULT`) desde el secreto `${prefix}/snowflake`. Los DAGs hacen `sys.path.insert` de la carpeta padre de `dags/` (donde vive `framework/`).
- `framework/tasks.py`: `glue_task(task_id, step, profile, env)` → GlueJobOperator sobre `${prefix}-<profile>` con `verbose=True` (variable de Airflow `prefix`, que se fija con `AIRFLOW_VAR_PREFIX`); `pipeline_local_task(task_id, step)` → BashOperator con Spark local (`.venv` del repo); `snowflake_task(task_id, sql_file)` con la conexión `snowflake_default`.
- `framework/profiles.yaml`: small/medium/large.
- DAG `dags/pipeline_taxi.py`: el entorno es fijo por Airflow (`PIPELINE_ENTORNO`: `dev` en el Code Editor, `prod` en la VM). Params `computo` (dev: `spark_local|glue_small|glue_medium|glue_large`; prod: `glue_medium|glue_large`), `mes` (vacío = todos) y `limite`. Tareas: `preparar_entorno` (límite efectivo: 10 000 filas solo con spark_local; ninguno en prod) → `elegir_computo` → `silver_spark_local → gold_spark_local` o `bronze (small) → silver → gold (perfil de computo) → cargar_gold` (`BIGDATA.DEV` o `BIGDATA.PROD`).
- Airflow de dev: `scripts/airflow-local.sh` (Airflow con pip + nginx en el Code Editor; `AIRFLOW__API__BASE_URL` y la API de ejecución bajo `/codeeditor/default/ports/8080/`). Prod: la VM con `proxy-studio` (nginx) en 127.0.0.1:8081 y túnel SSM.

## GitHub Actions (`.github/workflows/`) y secrets
Secrets: `AWS_ROLE_ARN`, `TF_STATE_BUCKET`, `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`, `SNOWFLAKE_PRIVATE_KEY` (estos últimos reservados; los workflows actuales no los usan).
Variables del repo (opcionales): `PREFIX`. La configuración de Terraform (alert_email, enable_*, fase 2 de Snowflake) no está en GitHub: vive en S3 (ver Terraform AWS).
`ci.yml` (PR): ruff lint y formato, pytest, pytest de DAGs, terraform fmt/validate; el job `terraform-plan` falla si faltan `AWS_ROLE_ARN` o `TF_STATE_BUCKET` y solo se omite en PRs desde forks (con aviso).
Workflows: `ci.yml` (PR: ruff lint y formato, pytest, pytest de DAGs, terraform fmt/validate/plan), `deploy.yml` (main/dispatch: falla si faltan los secrets, descarga la configuración, plan, guardia de destrucción, apply + empaquetar src → zip + sync dags/code/framework a S3 + enciende la VM de prod si el push cambió `airflow/` o `src/`, o con el input `encender_prod`), `airflow-on.yml`, `airflow-off.yml`, `debug-oidc.yml`. Acción `aws-actions/configure-aws-credentials@v6.3.0` (versiones verificadas contra GitHub en Fase 3).

## Makefile
`setup`, `config`, `doctor`, `estado`, `test`, `run-local`, `deploy`, `snowflake`, `airflow-on`, `airflow-off`, `airflow-habilitar`, `airflow-deshabilitar`, `airflow-tunel`, `airflow-password`, `desbloquear`, `snowflake-ampliar-cuota`, `snowflake-conexion`, `destroy` (+ `help`).
`.env` (no versionado) guarda solo `PREFIX` y `AWS_REGION`; `scripts/lib.sh` lo lee (el entorno tiene prioridad). `ALERT_EMAIL`, `ENABLE_*` y `SNOWFLAKE_*` ya no se leen de `.env`: van en `config/aws.tfvars`.
`make destroy`: vacía el lake, destruye infra/snowflake y luego infra/aws; opcionalmente (segunda confirmación) borra el stack de bootstrap y vacía/borra el bucket de state versionado.
