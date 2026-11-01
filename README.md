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
 |     computo=spark_local: Spark aquí, |    |  dev/  silver/ gold/                     |
 |       sobre la muestra (gratis)      |    |  prod/ silver/ gold/                     |
 |     computo=glue_small: 1 mes        |    +----------+-------------------------------+
 +------------------+-------------------+               | COPY INTO
                    | PR -> merge a main                 v
                    v                          +----------------------------+
 GitHub Actions (OIDC): CI, Deploy             | Snowflake BIGDATA.DEV /    |
   Terraform + código y DAGs a S3              |   BIGDATA.PROD             |
   + enciende el Airflow de prod  ------+      |   DAILY_ZONE_METRICS       |
                                        v      +----------------------------+
                          +---------------------------+       ^
                          | VM Airflow de prod (EC2)  |-------+
                          | prod (fijo): glue_large   |  Glue 5.0 jobs
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
4. **Launch Stack (bootstrap AWS).** En tu fork: **Actions > "Enlace de bootstrap" > Run workflow**. Abre el run y haz clic en el enlace **Launch Stack** del resumen: tus datos de GitHub ya vienen completados. Solo eliges la VPC *default*, todas sus subnets y tu correo, marcas la casilla de IAM y creas el stack. Espera `CREATE_COMPLETE` (~4 min). Detalle: [docs/bootstrap.md](docs/bootstrap.md).
5. **Code Editor.** Abre `StudioConsoleUrl` -> perfil `estudiante` -> Space `dev` -> **Code Editor**.
6. **Clona tu fork** en la terminal del Code Editor:
   ```bash
   git clone https://github.com/<TU_USUARIO>/<TU_FORK>.git && cd <TU_FORK>
   ```
7. **Conexión de Snowflake (`make snowflake-conexion`).** Si `make setup` dice que no hay conexión de `snow`, ejecuta este comando en la terminal del Code Editor. Te pedirá el *account identifier* (Snowsight: menú de tu cuenta > Account > View account details > Account identifier, formato `ORGNAME-ACCOUNTNAME`) y tu usuario (login name). Genera una llave privada en `~/.snowflake/keys/<usuario>_key.p8` (no se muestra ni se sube a ningún sitio), escribe la conexión `[default]` en `~/.snowflake/connections.toml` e imprime una sentencia `ALTER USER ... SET RSA_PUBLIC_KEY='...'`: pégala en una hoja de Snowsight con el rol ACCOUNTADMIN, ejecútala, pulsa Enter y el script prueba la conexión.
8. **`make setup`.** Verifica herramientas (Python 3.11+, Java 17, AWS CLI, Terraform, Snowflake CLI `snow`, jq, zip), crea `.venv`, valida que Snowflake esté en AWS, alinea `AWS_REGION` y, si todavía no existe, crea en S3 la configuración de Terraform (te pide el correo de alertas). Si no hay conexión de `snow`, te ofrece configurarla en ese momento (o hazlo con el paso 7). Después comprueba con `make doctor`. Las herramientas las instala el Lifecycle Config del Code Editor al arrancar.
9. **Secrets del fork: automáticos.** `make setup` los carga solo (`AWS_ROLE_ARN` y `TF_STATE_BUCKET`, leídos del bootstrap). La primera vez autentica GitHub en el Code Editor con `gh auth login --hostname github.com --git-protocol https --web` (abre el enlace, pega el código) y corre `make secrets`. No hay que copiar valores a mano.

10. **`make deploy`.** Aplica `infra/aws` (lake, Glue, Athena, guardrails y, si lo activas, Airflow) y sube a S3 el código del pipeline (`pipeline.zip`, `run_glue.py`), los DAGs y el framework de Airflow. La VM de prod solo existe si activas Airflow con `make airflow-habilitar` (cambia `enable_airflow` y despliega); el Airflow de dev corre en el Code Editor y no lo necesita. También se ejecuta solo en cada push a `main`.

11. **Snowflake (después de AWS).** El orden importa porque AWS y Snowflake se necesitan mutuamente:
    1. `bootstrap/snowflake/gen_key.sh` genera la llave de `TERRAFORM_SVC` y muestra la clave pública en una línea. Pégala entre las comillas de `RSA_PUBLIC_KEY` en `bootstrap/snowflake/01_admin.sql`. Abre una hoja de trabajo en Snowsight con el rol `ACCOUNTADMIN`, pega el script completo y pulsa **Run All**: crea el resource monitor y el usuario `TERRAFORM_SVC`. (Si no quieres modificar el archivo del repo, pega el script en Snowsight ya con la clave puesta.)
       Si `TERRAFORM_SVC` ya existe con otra llave, el script no la cambia (usa `CREATE USER IF NOT EXISTS`). En ese caso ejecuta el `ALTER USER TERRAFORM_SVC SET RSA_PUBLIC_KEY='...'` que imprime `gen_key.sh`, con la clave pública nueva. Si no, `make snowflake` falla con `JWT token is invalid`.
    2. En `infra/snowflake`: `cp terraform.tfvars.example terraform.tfvars` y `cp backend.hcl.example backend.hcl`, y completa los valores:
       - `organization_name` y `account_name`: las dos partes del account identifier (`ORGNAME-ACCOUNTNAME`).
       - `s3_role_arn` y `lake_bucket`: outputs de AWS fase 1, que se leen con `terraform -chdir=infra/aws output snowflake_s3_role_arn` y `terraform -chdir=infra/aws output lake_bucket`.
       - `dev_users`: tu usuario de Snowflake, para que reciba el rol `BIGDATA_DEV`.
       - `bucket` de `backend.hcl`: el output `TfStateBucket` del stack `bigdata-bootstrap` (pestaña **Outputs** en CloudFormation), con la forma `bigdata-tfstate-<cuenta>-us-east-2`.

       La llave privada no va en estos archivos: queda en `~/.snowflake/keys/`.
    3. Desde la raíz, `make snowflake`. Hace `terraform init` solo, aplica `infra/snowflake` (warehouse, base, rol y el usuario de servicio `AIRFLOW_SVC`), guarda `storage_aws_iam_user_arn` y `storage_aws_external_id` en la configuración de S3 y aplica la fase 2 de AWS (trust policy del rol). No hay que copiar valores a mano.

    **Conexión de Airflow a Snowflake: no hay nada que hacer a mano.** `make snowflake` crea el usuario `AIRFLOW_SVC` en Snowflake (genera su llave en `~/.snowflake/keys/airflow_svc_rsa_key.p8`), aplica la fase 2 de AWS y guarda la conexión en el secreto `bigdata/snowflake`, que usan el Airflow de dev y el de prod. Si Airflow ya estaba encendido, reinícialo: `make airflow-local-down && make airflow-local` (dev) y `make airflow-off && make airflow-on` (prod). Para repetir solo ese paso: `make snowflake-secreto`.

    Detalle: [infra/snowflake/README.md](infra/snowflake/README.md).

12. **Prepara los datos (una vez).** `make muestra`: Glue baja el año de FHVHV a `bronze/` (~5.4 GB) y genera la muestra en `muestra/` (~US$0.15, ~5 min). Si termina en `TIMEOUT`, repítelo: retoma desde lo que ya descargó.
13. **Desarrolla en local y dev.** `make run-local` (o `LIMITE=100` para una prueba rapidísima) y `make airflow-local` para el Airflow de dev: abre `https://<id-del-space>.studio.us-east-2.sagemaker.aws/codeeditor/default/ports/8080/` y lanza `pipeline_taxi`.
    - `<id-del-space>` es el subdominio de la URL del Code Editor que tienes abierta en el navegador: `https://<id-del-space>.studio.us-east-2.sagemaker.aws/codeeditor/default/...`. Copia esa parte y deja el final `/codeeditor/default/ports/8080/`.
    - El Airflow del Code Editor es siempre el entorno **dev** (no se elige al lanzar). Lo que eliges es el parámetro `computo`, que decide con qué recursos se calcula:
      - `spark_local`: Spark en el Code Editor sobre la muestra (gratis). Como mucho 10 000 filas por fuente. El resultado queda en `./lake` y no se carga en Snowflake.
      - `glue_small`, `glue_medium` o `glue_large`: Glue con 2, 4 o 6 workers. Escribe en `s3://<lake>/dev/` y carga en `BIGDATA.DEV` (`glue_small` cuesta centavos).
    - `mes`: vacío = todos los meses del entorno (en dev, solo `2024-01`), o un mes concreto en formato `YYYY-MM`.
    - `limite` (opcional): máximo de viajes a procesar; vacío = sin recorte.
    - Verifica el resultado en Snowsight con el rol `BIGDATA_DEV` y el warehouse `BIGDATA_WH`:
      ```sql
      SELECT COUNT(*), MIN(fecha), MAX(fecha) FROM BIGDATA.DEV.DAILY_ZONE_METRICS;
      ```
      La tabla la crea el propio DAG en `cargar_gold` la primera vez. Un run con `spark_local` no la modifica.
14. **Pasa a prod con un PR.** Al hacer merge a `main`, el Deploy publica código y DAGs y enciende la VM de prod si cambiaron `airflow/` o `src/`. Desde el Code Editor: `make airflow-tunel`, la misma URL, usuario `admin` y contraseña de `make airflow-password`. En prod el entorno también es fijo (`prod`, en la VM) y solo hay `computo=glue_medium` o `glue_large`, sin límite de filas: lanza `pipeline_taxi` con esos valores. La conexión de Snowflake ya está en el secreto `bigdata/snowflake` (la escribe `make snowflake`; ver [airflow/README.md](airflow/README.md)).

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
| `make snowflake-conexion` | Configura la conexión `[default]` de `snow` (llave en `~/.snowflake/keys`, `connections.toml`) y guía el `ALTER USER` en Snowsight |
| `make setup` | Verifica herramientas, crea `.venv`, valida la región de Snowflake, alinea `AWS_REGION` y crea la configuración de AWS en S3 si no existe |
| `make config` | Muestra la configuración de AWS guardada en S3 |
| `make secrets` | Carga `AWS_ROLE_ARN` y `TF_STATE_BUCKET` en tu fork desde el bootstrap (lo hace `make setup` si `gh` está autenticado) |
| `make doctor` | Diagnóstico: versiones, AWS, Snowflake, Terraform, OIDC |
| `make estado` | Estado de Airflow, últimos job runs de Glue, warehouse y costos |
| `make test` | `ruff check`, `ruff format --check`, `pytest` (y tests de DAGs si Airflow está instalado) |
| `make muestra` | Glue: bronze del año de prod + muestra para local (una vez por curso) |
| `make run-local` | Pipeline en local sobre la muestra (`STEP=silver\|gold\|all`, `MES=YYYY-MM`, `LIMITE=N`) |
| `make airflow-local` / `-down` / `-estado` | Airflow de dev dentro del Code Editor (entorno dev; `computo` se elige al lanzar el DAG) |
| `make deploy` | `terraform apply` de `infra/aws` (con la guardia de destrucción) y sincronización de código, DAGs y framework a S3 |
| `make snowflake` | `terraform init` y `apply` de `infra/snowflake` (crea `AIRFLOW_SVC`), guarda sus outputs en S3, aplica la fase 2 de AWS y escribe la conexión de Airflow (`SIN_DEPLOY=true` omite el deploy) |
| `make snowflake-secreto` | Escribe la conexión de `AIRFLOW_SVC` (llave privada incluida) en el secreto `bigdata/snowflake`; `make snowflake` ya lo hace |
| `make airflow-habilitar` / `make airflow-deshabilitar` | `enable_airflow` = true / false en S3 y `make deploy` |
| `make airflow-on` / `make airflow-off` | Enciende / apaga la VM de Airflow de prod |
| `make airflow-tunel` | Túnel SSM al Airflow de prod desde el Code Editor |
| `make airflow-password` | Usuario y contraseña de Airflow (Secrets Manager) |
| `make desbloquear` | Revierte la acción de Budgets (quita el Deny), con confirmación |
| `make snowflake-ampliar-cuota` | Sube la cuota del resource monitor (`CUOTA=N`) |
| `make destroy` | Vacía el lake y destruye Snowflake y AWS; opcionalmente el bootstrap y el state |

Solo instructor: `make publicar-bootstrap`, `make retirar-bootstrap` y `make limpieza-total`.

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
| `make setup` dice que no hay conexión de `snow` (`Connection default is not configured`) | Corre `make snowflake-conexion` (paso 7 del Quickstart) |
| `JWT token is invalid` en `make snowflake`, `make snowflake-conexion` o `snow` | La llave privada no coincide con la clave pública registrada en Snowflake. Ejecuta en Snowsight, como ACCOUNTADMIN, `ALTER USER <usuario> SET RSA_PUBLIC_KEY='<clave pública nueva>';` y comprueba con `DESC USER <usuario>` que `RSA_PUBLIC_KEY_FP` coincide con el fingerprint que imprimió el script de llaves |
| `AWS_ACCOUNT_ID=... no coincide con la cuenta real` en `make destroy` o `make deploy` | Tu terminal apunta a otra cuenta: exporta el perfil correcto (`export AWS_PROFILE=<perfil>`) o quita `AWS_ACCOUNT_ID` del entorno. En el Code Editor no hace falta |
| `ci.yml` o `deploy.yml` fallan pidiendo `AWS_ROLE_ARN` o `TF_STATE_BUCKET` | Corre `make secrets` en el Code Editor (con `gh auth login` hecho). En PRs desde forks el plan se omite a propósito |
| `Falta la configuración en S3. Corre 'make setup' en Code Editor.` | Corre `make setup` en el Code Editor; crea `config/aws.tfvars` |
| `El plan destruye recursos` en el deploy | Revisa la lista del plan. Si es intencional (p. ej. apagar Airflow), repite con `CONFIRMAR_DESTRUCCION=true` o el input `confirmar_destruccion` |
| `AccessDenied` al lanzar jobs Glue o encender la VM | Probablemente actuó el presupuesto: `make estado` y `make desbloquear` |
| Terraform: `AccessDenied` al crear un rol IAM | El rol debe llevar la boundary `<prefix>-boundary` (`permissions_boundary_arn`) |
| Un job Glue falla con `ModuleNotFoundError: pipeline` | Falta subir el código: `make deploy` (sube `pipeline.zip` con la carpeta `pipeline/`) |
| `make airflow-tunel` no abre el túnel | La VM debe estar encendida (`make airflow-on`); `session-manager-plugin` lo instala el Lifecycle Config |
| La UI de Airflow sale en blanco o "Unsupported URL path" | Usa exactamente `.../codeeditor/default/ports/8080/` (no `/proxy/` ni `/ports/8080/` sin `/codeeditor/default`) |
| "Invalid or Expired Auth Token" al abrir la UI | Venció la sesión de Studio: vuelve a abrir Studio desde la consola de AWS |
| `make run-local`: "No hay muestra ... falta LAKE_BUCKET" | Corre `make muestra` primero (una vez) |
| El DAG falla en `cargar_gold` | Falta la conexión de Airflow: corre `make snowflake-secreto` (o `make snowflake`) y reinicia Airflow: `make airflow-local-down && make airflow-local` (dev) o `make airflow-off && make airflow-on` (prod) ([airflow/README.md](airflow/README.md)) |
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
.github/workflows/  enlace-bootstrap, ci, deploy (enciende prod), airflow-on/off, debug-oidc
```
