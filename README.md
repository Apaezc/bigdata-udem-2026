# bigdata-udem-2026

Template del curso de Big Data de la UdeM: un pipeline de datos de punta a punta (SQL, PySpark, AWS y Snowflake) que cada estudiante despliega en su propia cuenta con Terraform y GitHub Actions.

El pipeline procesa los viajes de Uber/Lyft de NYC (NYC TLC FHVHV: ~20 M filas por mes, ~240 M por año), las zonas de taxi y el clima diario (Open-Meteo) en tres capas, y publica una tabla de métricas diarias por zona y empresa en Snowflake. Se desarrolla en tres entornos con el mismo código y distinta configuración.

## Arquitectura

```
                     NYC TLC FHVHV (Parquet)   taxi zones (CSV)   Open-Meteo (JSON)
                                    \               |                 /
                                     v              v                v
 +--------------------------------------+    +------------------------------------------+
 | Code Editor (SageMaker, 8 GB)        |    | S3  bigdata-lake-<cuenta>-us-east-2      |
 |  - tu código, tests                  |    |  bronze/  (crudo, compartido dev y prod) |
 |  - Airflow de dev (make airflow-local)|-->|  muestra/ (~100 k filas, para local)     |
 |     entorno=local: Spark aquí,       |    |  dev/  silver/ gold/                     |
 |       sobre la muestra (gratis)      |    |  prod/ silver/ gold/                     |
 |     entorno=dev: Glue small, 1 mes   |    +----------+-------------------------------+
 +------------------+-------------------+               | COPY INTO
                    | PR -> merge a main                 v
                    v                          +----------------------------+
 GitHub Actions (OIDC): CI, Deploy             | Snowflake BIGDATA.DEV /    |
   Terraform + código y DAGs a S3              |   BIGDATA.PROD             |
   + enciende el Airflow de prod  ------+      |   DAILY_ZONE_METRICS       |
                                        v      +----------------------------+
                          +---------------------------+       ^
                          | VM Airflow de prod (EC2)  |-------+
                          | entorno=prod: Glue large, |  Glue 5.0 jobs
                          | el año; apagado nocturno; |  bigdata-small|medium|large
                          | acceso por túnel SSM      |
                          +---------------------------+

  Guardrails: Budget (gasto bruto) con bloqueo al 60 % + resource monitor de Snowflake
```

| Entorno | Airflow | Spark | Datos | Salida |
|---|---|---|---|---|
| **local** | Code Editor (`make airflow-local`) | En el Code Editor | Muestra (~100 k filas) | `./lake` |
| **dev** | Code Editor | Glue `small` | 1 mes completo | `s3://<lake>/dev/`, `BIGDATA.DEV` |
| **prod** | VM dedicada (se enciende con el Deploy) | Glue `medium`/`large` | 12 meses | `s3://<lake>/prod/`, `BIGDATA.PROD` |

- **Bootstrap** (`bootstrap/`): una plantilla de CloudFormation que crea tu entorno de trabajo (SageMaker Code Editor), el acceso de GitHub Actions a AWS por OIDC (sin claves), el bucket de state de Terraform y un presupuesto con alertas; más un script SQL para Snowflake.
- **Infraestructura** (`infra/aws`, `infra/snowflake`): Terraform. AWS: lake S3, catálogo Glue y Athena, jobs Glue, VM de Airflow opcional y guardrails de costo. Snowflake: warehouse XS, base `BIGDATA` (BRONZE/SILVER/GOLD para SQL; DEV/PROD para el pipeline), rol `BIGDATA_DEV` y stages externos sobre `gold/`, `dev/gold/` y `prod/gold/`.
- **Pipeline** (`src/pipeline`): bronze (descarga sin transformar) -> silver (limpieza y enriquecimiento) -> gold (métricas diarias por zona y empresa), más el paso `muestra`. Corre con Spark local o en Glue; la configuración de cada entorno está en `src/pipeline/config/<entorno>.yaml`.
- **Orquestación** (`airflow/`): DAG `pipeline_taxi` con un camino por entorno (local, dev, prod). Snowpark Connect se compara aparte, en el laboratorio de la sesión 7.
- **Automatización**: `Makefile` + `scripts/` + `.github/workflows/`.

Detalle de nombres e interfaces: [CONTRATO.md](CONTRATO.md). Más documentos: [docs/bootstrap.md](docs/bootstrap.md), [airflow/README.md](airflow/README.md), [infra/snowflake/README.md](infra/snowflake/README.md).

## Quickstart del estudiante

Haz los pasos en este orden.

1. **Snowflake: cuenta trial en AWS, región `us-east-2`.** Crea la cuenta de prueba en snowflake.com eligiendo la nube **AWS** y la región **US East (Ohio)**. Si queda en Azure/GCP o en otra región de AWS, `make setup` te lo avisará y tendrás que crear otra cuenta.
2. **Cuenta AWS.** Crea tu cuenta de AWS (plan gratuito) y trabaja siempre en `us-east-2`. Entra con un usuario con permisos de administrador solo para lanzar el bootstrap.
3. **Fork y Actions.** Haz fork de este repositorio en tu GitHub. En el fork, pestaña **Actions**, habilita los workflows ("I understand my workflows, go ahead and enable them").
4. **Launch Stack (bootstrap AWS).** Sigue [docs/bootstrap.md](docs/bootstrap.md): obtén los IDs numéricos de tu usuario y repo, elige la VPC por defecto y lanza el stack `bigdata-bootstrap` con CloudFormation. Espera `CREATE_COMPLETE` y copia los outputs `GitHubActionsRoleArn` y `TfStateBucket`.
5. **Code Editor.** Abre `StudioConsoleUrl` -> perfil `estudiante` -> Space `dev` -> **Code Editor**.
6. **Clona tu fork** en la terminal del Code Editor:
   ```bash
   git clone https://github.com/<TU_USUARIO>/<TU_FORK>.git && cd <TU_FORK>
   ```
7. **`make setup`.** Verifica herramientas (Python 3.11+, Java 17, AWS CLI, Terraform, Snowflake CLI `snow`, jq, zip), crea `.venv`, valida que Snowflake esté en AWS, alinea `AWS_REGION` y, si todavía no existe, crea en S3 la configuración de Terraform (te pide el correo de alertas). Antes configura `snow` (`~/.snowflake/connections.toml`, conexión `[default]`) y comprueba con `make doctor`. Las herramientas las instala el Lifecycle Config del Code Editor al arrancar.
8. **Secrets del fork** (Settings > Secrets and variables > Actions):

   | Nombre | Tipo | Valor |
   |---|---|---|
   | `AWS_ROLE_ARN` | secret | output `GitHubActionsRoleArn` del bootstrap |
   | `TF_STATE_BUCKET` | secret | output `TfStateBucket` del bootstrap |
   | `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`, `SNOWFLAKE_PRIVATE_KEY` | secrets | reservados para workflows de Snowflake; los workflows actuales no los usan |

   La configuración de Terraform (correo de alertas, Airflow, Glue y la fase 2 de Snowflake) no va en secrets ni variables: está en S3 ([ver abajo](#configuración-por-estudiante)).

9. **`make deploy`.** Aplica `infra/aws` (lake, Glue, Athena, guardrails y, si lo activas, Airflow) y sube a S3 el código del pipeline (`pipeline.zip`, `run_glue.py`), los DAGs y el framework de Airflow. Para activar Airflow usa `make airflow-habilitar` (cambia la configuración y despliega). También se ejecuta solo en cada push a `main`.

10. **Snowflake (después de AWS).** El orden importa porque AWS y Snowflake se necesitan mutuamente:
    1. `bootstrap/snowflake/gen_key.sh` genera la llave; pega la clave pública en `bootstrap/snowflake/01_admin.sql` y ejecútalo en Snowsight como `ACCOUNTADMIN` (crea el resource monitor y el usuario `TERRAFORM_SVC`).
    2. En `infra/snowflake`: `cp terraform.tfvars.example terraform.tfvars`, `cp backend.hcl.example backend.hcl` y completa los valores (la llave privada queda en `~/.snowflake/keys/`).
    3. Desde la raíz, `make snowflake`: aplica `infra/snowflake`, guarda `storage_aws_iam_user_arn` y `storage_aws_external_id` en la configuración de S3 y aplica la fase 2 de AWS (trust policy del rol). No hay que copiar valores a mano.

    Detalle: [infra/snowflake/README.md](infra/snowflake/README.md).

11. **Prepara los datos (una vez).** `make muestra`: Glue baja el año de FHVHV a `bronze/` (~5.4 GB) y genera la muestra en `muestra/` (~US$0.15).
12. **Desarrolla en local y dev.** `make run-local` (o `LIMITE=100` para una prueba rapidísima) y `make airflow-local` para el Airflow de dev: abre `https://<id-del-space>.studio.us-east-2.sagemaker.aws/codeeditor/default/ports/8080/` y lanza `pipeline_taxi` con `entorno=local` (gratis) o `entorno=dev` (Glue small, centavos).
13. **Pasa a prod con un PR.** Al hacer merge a `main`, el Deploy publica código y DAGs y enciende la VM de prod si cambiaron `airflow/` o `src/`. Desde el Code Editor: `make airflow-tunel`, la misma URL, usuario `admin` y contraseña de `make airflow-password`; lanza `pipeline_taxi` con `entorno=prod`. La conexión de Snowflake va en el secreto `bigdata/snowflake` ([airflow/README.md](airflow/README.md)).

## Configuración por estudiante

Una sola fuente de verdad para Terraform de `infra/aws`: el archivo `s3://<TF_STATE_BUCKET>/config/aws.tfvars` (HCL, en el bucket de state, con versionado). Lo usan por igual `make deploy` (local) y `deploy.yml` / `ci.yml` (GitHub Actions), que lo descargan y lo pasan con `-var-file`. No hay variables de Terraform en `.env` ni en el fork.

Contenido típico:

```hcl
prefix                 = "bigdata"
aws_region             = "us-east-2"
alert_email            = "tu-correo@ejemplo.com"
enable_glue            = true
enable_airflow         = true
snowflake_iam_user_arn = "arn:aws:iam::...:user/..."   # lo pone make snowflake
snowflake_external_id  = "..."                          # lo pone make snowflake
```

- `make config`: muestra el archivo.
- `make airflow-habilitar` / `make airflow-deshabilitar`: cambian `enable_airflow` y despliegan. Apagar Airflow destruye la VM: el deploy lo exige con `CONFIRMAR_DESTRUCCION=true make airflow-deshabilitar`.
- `make snowflake`: copia los outputs de Snowflake. Con `SIN_DEPLOY=true` solo actualiza el archivo.
- Guardia de destrucción: `make deploy` y `deploy.yml` muestran el plan y abortan si elimina o reemplaza recursos, salvo que lo confirmes (`CONFIRMAR_DESTRUCCION=true` o el input `confirmar_destruccion` en el workflow manual). `make destroy` no usa esta guardia.
- Si el archivo no existe, `make deploy` falla con "Falta la configuración en S3. Corre 'make setup' en Code Editor."

## Targets de `make`

Ejecuta `make help` para ver la lista actualizada.

| Target | Qué hace |
|---|---|
| `make setup` | Verifica herramientas, crea `.venv`, valida la región de Snowflake, alinea `AWS_REGION` y crea la configuración de AWS en S3 si no existe |
| `make config` | Muestra la configuración de AWS guardada en S3 |
| `make doctor` | Diagnóstico: versiones, AWS, Snowflake, Terraform, OIDC |
| `make estado` | Estado de Airflow, últimos job runs de Glue, warehouse y costos |
| `make test` | `ruff check`, `ruff format --check`, `pytest` (y tests de DAGs si Airflow está instalado) |
| `make muestra` | Glue: bronze del año de prod + muestra para local (una vez por curso) |
| `make run-local` | Pipeline en local sobre la muestra (`STEP=silver\|gold\|all`, `MES=YYYY-MM`, `LIMITE=N`) |
| `make airflow-local` / `-down` / `-estado` | Airflow de dev dentro del Code Editor (entornos local y dev) |
| `make deploy` | `terraform apply` de `infra/aws` (con la guardia de destrucción) y sincronización de código, DAGs y framework a S3 |
| `make snowflake` | `terraform apply` de `infra/snowflake`, guarda sus outputs en S3 y aplica la fase 2 de AWS (`SIN_DEPLOY=true` omite el deploy) |
| `make airflow-habilitar` / `make airflow-deshabilitar` | `enable_airflow` = true / false en S3 y `make deploy` |
| `make airflow-on` / `make airflow-off` | Enciende / apaga la VM de Airflow de prod |
| `make airflow-tunel` | Túnel SSM al Airflow de prod desde el Code Editor |
| `make airflow-password` | Usuario y contraseña de Airflow (Secrets Manager) |
| `make desbloquear` | Revierte la acción de Budgets (quita el Deny), con confirmación |
| `make snowflake-ampliar-cuota` | Sube la cuota del resource monitor (`CUOTA=N`) |
| `make destroy` | Vacía el lake y destruye Snowflake y AWS; opcionalmente el bootstrap y el state |

## Costos y apagado

Estimaciones aproximadas; verifica precios vigentes en la consola de AWS y de Snowflake.

- **Presupuesto**: se mide el gasto bruto (sin descontar créditos del free plan). Terraform crea `bigdata-mensual` (50 USD por defecto) con alertas al 40 y 80 %; al 60 % AWS Budgets adjunta una política Deny (`bigdata-bloqueo-presupuesto`) que impide iniciar jobs Glue e instancias EC2 (CI, Code Editor y VM) y detiene la VM de Airflow. El bootstrap crea `bigdata-total`, que solo alerta al 100 % como red de seguridad. Budgets actualiza el gasto como mucho una vez al día, así que no es un tope en tiempo real. Para revertirlo: `make desbloquear`.
- **Glue**: se paga por segundo de cómputo de los workers. Los jobs tienen 2, 4 o 6 workers G.1X, tiempos límite de 10, 20 y 30 minutos y un job a la vez por perfil (los siguientes esperan en cola; el tiempo en cola no cuenta para el límite). Referencia medida: 1 mes de FHVHV en `small` ≈ US$0.02; el año en `large` ≈ US$0.12.
- **Athena**: cada consulta se cancela al pasar de 1 GB escaneado.
- **VM de Airflow de prod**: `m7i-flex.large` elegible en el plan gratuito. La enciende el Deploy; se apaga sola a las 23:00 (hora de Bogotá) o con `make airflow-off`. Apagada solo paga el disco (~US$2.4/mes); no tiene IP fija.
- **SageMaker Code Editor** (`ml.t3.large`, 8 GB, ~US$0.10/h): se apaga solo tras 60 minutos de inactividad; eso también detiene el Airflow de dev (`make airflow-local` para volver a levantarlo).
- **Snowflake**: warehouse XS con `auto_suspend` de 60 s; el resource monitor `BIGDATA_RM` (60 créditos al mes) avisa al 50 y 75 % y suspende al 90 y 100 %, pero actúa con retraso: el freno inmediato es el `auto_suspend`. Para ampliarlo: `make snowflake-ampliar-cuota CUOTA=<n>`.
- **Al terminar el curso**: `make destroy` (borra el lake, Snowflake y AWS y, si confirmas, el bootstrap y el bucket de state). Las cuentas de AWS y Snowflake siguen siendo tuyas.

## Troubleshooting

| Síntoma | Qué revisar |
|---|---|
| El stack falla con `EntityAlreadyExists` (OIDC) | La cuenta ya tiene el proveedor de GitHub: relanza el stack con `ExistingGitHubOidcProviderArn` ([docs/bootstrap.md](docs/bootstrap.md)) |
| GitHub Actions: `Not authorized to perform sts:AssumeRoleWithWebIdentity` | Revisa `AWS_ROLE_ARN` y los IDs numéricos del bootstrap. Ejecuta el workflow **Debug OIDC** y compara el claim `sub` |
| `make setup` dice que Snowflake no está en AWS | Crea otra cuenta trial eligiendo AWS y `us-east-2` |
| `ci.yml` o `deploy.yml` fallan pidiendo `AWS_ROLE_ARN` o `TF_STATE_BUCKET` | Crea esos secrets en el fork (en PRs desde forks el plan se omite a propósito) |
| `Falta la configuración en S3. Corre 'make setup' en Code Editor.` | Corre `make setup` en el Code Editor; crea `config/aws.tfvars` |
| `El plan destruye recursos` en el deploy | Revisa la lista del plan. Si es intencional (p. ej. apagar Airflow), repite con `CONFIRMAR_DESTRUCCION=true` o el input `confirmar_destruccion` |
| `AccessDenied` al lanzar jobs Glue o encender la VM | Probablemente actuó el presupuesto: `make estado` y `make desbloquear` |
| Terraform: `AccessDenied` al crear un rol IAM | El rol debe llevar la boundary `<prefix>-boundary` (`permissions_boundary_arn`) |
| Un job Glue falla con `ModuleNotFoundError: pipeline` | Falta subir el código: `make deploy` (sube `pipeline.zip` con la carpeta `pipeline/`) |
| `make airflow-tunel` no abre el túnel | La VM debe estar encendida (`make airflow-on`); `session-manager-plugin` lo instala el Lifecycle Config |
| La UI de Airflow sale en blanco o "Unsupported URL path" | Usa exactamente `.../codeeditor/default/ports/8080/` (no `/proxy/` ni `/ports/8080/` sin `/codeeditor/default`) |
| "Invalid or Expired Auth Token" al abrir la UI | Venció la sesión de Studio: vuelve a abrir Studio desde la consola de AWS |
| `make run-local`: "No hay muestra ... falta LAKE_BUCKET" | Corre `make muestra` primero (una vez) |
| El DAG falla en `cargar_gold` | Falta la conexión: guarda el JSON en el secreto `bigdata/snowflake` y reinicia la VM ([airflow/README.md](airflow/README.md)) |
| Terraform: `Error acquiring the state lock` | Otro apply está corriendo; si no (quedó de un apply interrumpido), `terraform force-unlock <ID>` en la carpeta de Terraform |
| `make deploy` se queda colgado o pierde el lock | Córrelo en una terminal normal, no desde herramientas con tiempo límite |
| `Falta la configuración en S3` aunque ya corriste `make setup` | Tu terminal tiene otro `AWS_REGION`: `export AWS_REGION=us-east-2` |
| `make test` o `make run-local` fallan por Java | Instala Java 17 (versión con la que se validó PySpark 3.5) y revisa `java -version` / `JAVA_HOME` |

## Estructura

```
bootstrap/    CloudFormation (AWS) y SQL/llaves (Snowflake)
infra/aws/    Terraform: lake, glue, airflow_vm, guardrails
infra/snowflake/  Terraform: warehouse, base, rol, integración S3
src/pipeline/ pipeline bronze/silver/gold (+ run_glue.py)
airflow/      docker-compose, framework y DAGs
tests/        pruebas del pipeline (pytest + PySpark local)
scripts/      implementación de los targets de make
docs/         bootstrap e integración
.github/workflows/  ci, deploy (enciende prod), airflow-on/off, debug-oidc
```
