# Referencia

Material de consulta. No hace falta leerlo para empezar: el recorrido está en la [guía](guia.md).

## Índice

- [Arquitectura](#arquitectura): diagrama y entornos (local, dev y prod).
- [Configuración por estudiante](#configuracion): el archivo de configuración de AWS.
- [Comandos de `make`](#make): qué hace cada comando y en qué paso se usa.
- [Costos (referencia)](#costos): presupuesto, cobros y apagado.
- [Estructura del repositorio](#estructura): qué hay en cada carpeta.
- [Para el instructor](#instructor): solo para el instructor.

---

<a id="arquitectura"></a>
## Arquitectura

> [!NOTE]
> No necesario para empezar. Es el detalle del diseño del proyecto.

<a id="arquitectura-diagrama"></a>
### Diagrama

```text
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

<a id="arquitectura-entornos"></a>
### Entornos

Hay tres entornos. Usan el mismo código con distinta configuración.

| Entorno | Airflow | Spark | Datos | Salida |
|---|---|---|---|---|
| **local** | Code Editor (`make airflow-local`) | En el Code Editor | Muestra (~100 k filas) | `./lake` |
| **dev** | Code Editor | Glue `small` | 1 mes completo | `s3://<LAKE>/dev/`, `BIGDATA.DEV` |
| **prod** | VM dedicada (se enciende con el Deploy) | Glue `medium`/`large` | 12 meses | `s3://<LAKE>/prod/`, `BIGDATA.PROD` |

- **local:** pruebas gratis en tu Code Editor, sobre la muestra. Escribe en `./lake`, la carpeta `lake` dentro de `~/bigdata`.
- **dev:** pruebas en AWS sobre un mes completo. Escribe en `s3://<LAKE>/dev/` y carga en `BIGDATA.DEV`.
- **prod:** el año completo, en la VM de Airflow de prod. Escribe en `s3://<LAKE>/prod/` y carga en `BIGDATA.PROD`.

`<LAKE>` es el bucket `bigdata-lake-<CUENTA>-us-east-2` que el [Paso 10](guia.md#paso-10) imprime como `lake_bucket`.

<a id="arquitectura-piezas"></a>
### Piezas del repositorio

| Pieza | Dónde | Qué hace |
|---|---|---|
| **Bootstrap** | `bootstrap/` | Plantilla de CloudFormation. Crea tu entorno de trabajo (SageMaker Code Editor), el acceso de GitHub Actions a AWS por OIDC (sin claves), el bucket de state de Terraform y un presupuesto con alertas. Incluye un script SQL para Snowflake. |
| **Infraestructura** | `infra/aws`, `infra/snowflake` | Terraform. AWS: lake S3, catálogo Glue y Athena, jobs Glue, VM de Airflow opcional y guardrails de costo. Snowflake: warehouse XS, base `BIGDATA` (BRONZE/SILVER/GOLD para SQL; DEV/PROD para el pipeline), rol `BIGDATA_DEV` y stages externos sobre `gold/`, `dev/gold/` y `prod/gold/`. |
| **Pipeline** | `src/pipeline` | bronze (descarga sin transformar) -> silver (limpieza y enriquecimiento) -> gold (métricas diarias por zona y empresa), más el paso `muestra`. Corre con Spark local o en Glue. La configuración de cada entorno está en `src/pipeline/config/<entorno>.yaml`, donde `<entorno>` es local, dev o prod. |
| **Orquestación** | `airflow/` | DAG `pipeline_taxi` con un camino por entorno (local, dev, prod). Snowpark Connect se compara aparte, en el laboratorio de la sesión 7. |
| **Automatización** | `Makefile`, `scripts/`, `.github/workflows/` | Comandos de `make`, sus scripts y los workflows de GitHub Actions. |

---

<a id="configuracion"></a>
## Configuración por estudiante

Una sola fuente de verdad para Terraform de `infra/aws`: `s3://<TF_STATE_BUCKET>/config/aws.tfvars`.

- Es un archivo HCL, en el bucket de state de Terraform, con versionado.
- `make deploy` (local) lo usa.
- `deploy.yml` y `ci.yml` (GitHub Actions) lo descargan y lo pasan con `-var-file`.
- No hay variables de Terraform en `.env` ni en el fork.

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
- `make airflow-habilitar` / `make airflow-deshabilitar`: cambian `enable_airflow` y despliegan.
  - Apagar Airflow destruye la VM.
  - El deploy lo exige con `CONFIRMAR_DESTRUCCION=true make airflow-deshabilitar`.
- `make snowflake`: copia los outputs de Snowflake.
  - Con `SIN_DEPLOY=true` solo actualiza el archivo.
- Guardia de destrucción: `make deploy` y `deploy.yml` muestran el plan y abortan si elimina o reemplaza recursos, salvo que lo confirmes.
  - Para confirmar: `CONFIRMAR_DESTRUCCION=true` o el input `confirmar_destruccion` en el workflow manual.
  - `make destroy` no usa esta guardia.
- Si el archivo no existe, `make deploy` falla con "Falta la configuración en S3. Corre 'make setup' en Code Editor."

---

<a id="make"></a>
## Comandos de `make`

Ejecuta `make help` para ver la lista actualizada. La columna **Paso** dice dónde se usa cada comando en la [guía](guia.md). Un guion (—) significa que el comando no aparece en la guía.

| Target | Qué hace | Paso |
|---|---|---|
| `make snowflake-conexion` | Configura la conexión `[default]` de `snow` (llave en `~/.snowflake/keys`, `connections.toml`) y guía el `ALTER USER` en Snowsight | [Paso 7](guia.md#paso-7) |
| `make setup` | Verifica herramientas, crea `.venv`, valida la región de Snowflake, alinea `AWS_REGION` y crea la configuración de AWS en S3 si no existe | [Paso 8](guia.md#paso-8) |
| `make config` | Muestra la configuración de AWS guardada en S3 | — |
| `make secrets` | Carga `AWS_ROLE_ARN` y `TF_STATE_BUCKET` en tu fork desde el bootstrap (lo hace `make setup` si `gh` está autenticado) | [Paso 9](guia.md#paso-9) |
| `make doctor` | Diagnóstico: versiones, AWS, Snowflake, Terraform, OIDC | [Paso 9](guia.md#paso-9) |
| `make estado` | Estado de Airflow, últimos job runs de Glue, warehouse y costos | [Apagar](cada-sesion.md#apagar) |
| `make test` | `ruff check`, `ruff format --check`, `pytest` (y tests de DAGs si Airflow está instalado) | — |
| `make muestra` | Glue: bronze del año de prod + muestra para local (una vez por curso) | [Paso 12](guia.md#paso-12) |
| `make run-local` | Pipeline en local sobre la muestra (`STEP=silver\|gold\|all`, `MES=YYYY-MM`, `LIMITE=N`). Sin `LIMITE` procesa toda la muestra | [Paso 13](guia.md#paso-13) |
| `make airflow-local` / `-down` / `-estado` | Airflow de dev dentro del Code Editor (entorno dev; `computo` se elige al lanzar el DAG) | [Paso 13](guia.md#paso-13) · [Apagar](cada-sesion.md#apagar) (`-down`) |
| `make deploy` | `terraform apply` de `infra/aws` (con la guardia de destrucción) y sincronización de código, DAGs y framework a S3 | [Paso 10](guia.md#paso-10) |
| `make snowflake` | `terraform init` y `apply` de `infra/snowflake` (crea `AIRFLOW_SVC`), guarda sus outputs en S3, aplica la fase 2 de AWS y escribe la conexión de Airflow (`SIN_DEPLOY=true` omite el deploy) | [Paso 11](guia.md#paso-11) |
| `make snowflake-secreto` | Escribe la conexión de `AIRFLOW_SVC` (llave privada incluida) en el secreto `bigdata/snowflake`; `make snowflake` ya lo hace | [Problemas](problemas.md#p-cargar-gold) |
| `make airflow-habilitar` / `make airflow-deshabilitar` | `enable_airflow` = true / false en S3 y `make deploy` | [Paso 14](guia.md#paso-14) (habilitar) |
| `make airflow-on` / `make airflow-off` | Enciende / apaga la VM de Airflow de prod | [Encender](cada-sesion.md#encender) · [Apagar](cada-sesion.md#apagar) |
| `make airflow-tunel` | Túnel SSM al Airflow de prod desde el Code Editor | [Paso 14](guia.md#paso-14) |
| `make airflow-password` | Usuario y contraseña de Airflow (Secrets Manager) | [Paso 14](guia.md#paso-14) |
| `make desbloquear` | Revierte la acción de Budgets (quita el Deny), con confirmación | [Problemas](problemas.md#p-accessdenied-presupuesto) |
| `make snowflake-ampliar-cuota` | Sube la cuota del resource monitor (`CUOTA=N`) | — |
| `make destroy` | Vacía el lake y destruye Snowflake y AWS; opcionalmente el bootstrap y el state | [Al terminar el curso](#costos) |

<a id="make-detalle"></a>
### Detalle de los comandos de la guía

Qué hace por dentro cada comando largo de los pasos 8, 10, 11 y 12.

<a id="make-setup"></a>
#### `make setup` ([Paso 8](guia.md#paso-8))

Verifica las herramientas (Python 3.11+, Java 17, AWS CLI, Terraform, `snow`, jq y zip; el **Lifecycle Config** de SageMaker las instala al arrancar), crea `.venv`, valida que Snowflake esté en AWS, alinea `AWS_REGION` y crea en S3 la configuración de Terraform.

<a id="make-deploy"></a>
#### `make deploy` ([Paso 10](guia.md#paso-10))

- Aplica `infra/aws`, que incluye el **lake** (el bucket de datos del curso), **Glue** (ejecuta trabajos de datos y cobra por segundo de uso), **Athena** (consulta archivos con SQL), los **guardrails** (límites de costo: el presupuesto que bloquea Glue y la VM al 60 %) y, si lo activas, **Airflow** (lanza los pasos del pipeline en orden).
- Sube a **S3** (servicio de AWS para guardar archivos) el código: `pipeline.zip`, `run_glue.py`, los **DAGs** (lista de tareas de Airflow en orden fijo) y el framework de Airflow.
- También se ejecuta solo en cada **push** (subir cambios a GitHub) a **main** (la rama principal, la versión oficial del código).
- La **VM** de prod (máquina virtual de AWS) solo existe si Airflow está habilitado: `make airflow-habilitar` cambia `enable_airflow` y despliega. El Airflow de dev corre en el Code Editor y no lo necesita.

<a id="make-snowflake"></a>
#### `make snowflake` ([Paso 11](guia.md#paso-11))

Usa tu conexión de `snow` y los outputs del Paso 10, así que no hay que copiar valores ni editar archivos. Hace, en orden:

- El script genera la llave de `TERRAFORM_SVC` en `~/.snowflake/keys/` y ejecuta `bootstrap/snowflake/01_admin.sql` (**resource monitor** `BIGDATA_RM`, límite de consumo de Snowflake; `TERRAFORM_ROLE`, un **rol** o conjunto de permisos; usuario `TERRAFORM_SVC`).
- El script escribe `infra/snowflake/terraform.tfvars` y `backend.hcl` (si no existen) con tu cuenta, el lake y tu usuario en `dev_users`.
- El script aplica `infra/snowflake` (warehouse `BIGDATA_WH`, base `BIGDATA`, roles, **stages** —lugares desde donde Snowflake lee archivos— y el usuario `AIRFLOW_SVC`).
- El script aplica la fase 2 de AWS, con la **trust policy** de Snowflake (la regla de AWS que dice quién puede usar el rol), y guarda la conexión de Airflow en el secreto `bigdata/snowflake`.

Conexión de Airflow a Snowflake: no hay nada que hacer a mano. `make snowflake` crea el usuario `AIRFLOW_SVC` en Snowflake (genera su llave en `~/.snowflake/keys/airflow_svc_rsa_key.p8`), aplica la fase 2 de AWS y guarda la conexión en el secreto `bigdata/snowflake`, que usan el Airflow de dev y el de prod.

<a id="make-muestra"></a>
#### `make muestra` ([Paso 12](guia.md#paso-12))

- Glue baja el año de **FHVHV** (los viajes de Uber/Lyft de NYC publicados por la NYC TLC) a `bronze/` (~5.4 GB).
- **Bronze** son los datos crudos tal como llegan.
- Genera la **muestra** en `muestra/`: un subconjunto pequeño de los datos para trabajar en local.

---

<a id="costos"></a>
## Costos (referencia)

> [!NOTE]
> Estimaciones aproximadas. Verifica precios vigentes en la consola de AWS y de Snowflake.

- **Presupuesto**: se mide el gasto bruto (sin descontar créditos del free plan).
  - Terraform crea `bigdata-mensual` (50 USD por defecto), con alertas al 40 y 80 %.
  - Al 60 %, AWS Budgets adjunta una política Deny (`bigdata-bloqueo-presupuesto`).
  - Esa política impide iniciar jobs Glue e instancias EC2 (CI, Code Editor y VM) y detiene la VM de Airflow.
  - El bootstrap crea `bigdata-total`. Solo alerta al 100 %, como red de seguridad.
  - Budgets actualiza el gasto como mucho una vez al día. No es un tope en tiempo real.
  - Para revertirlo: `make desbloquear`.
- **Glue**: se paga por segundo de cómputo de los workers.
  - Los jobs tienen 2, 4 o 6 workers G.1X, tiempos límite de 10, 20 y 30 minutos y un job a la vez por perfil.
  - Los jobs siguientes esperan en cola. El tiempo en cola no cuenta para el límite.
  - Referencia medida: 1 mes de FHVHV en `small` ≈ US$0.02; el año en `large` ≈ US$0.12.
- **Athena**: cada consulta se cancela al pasar de 1 GB escaneado.
- **VM de Airflow de prod**: `m7i-flex.large`, elegible en el plan gratuito.
  - El Deploy la enciende.
  - Se apaga sola a las 23:00 (hora de Bogotá) o con `make airflow-off`.
  - Apagada solo paga el disco (~US$2.4/mes). No tiene IP fija.
- **SageMaker Code Editor** (`ml.t3.large`, 8 GB, ~US$0.10/h): se apaga solo tras 60 minutos de inactividad.
  - Eso también detiene el Airflow de dev. `make airflow-local` lo vuelve a levantar.
- **Snowflake**: warehouse XS con `auto_suspend` de 60 s.
  - El resource monitor `BIGDATA_RM` (60 créditos al mes) avisa al 50 y 75 % y suspende al 90 y 100 %. Pero actúa con retraso.
  - El freno inmediato es el `auto_suspend`.
  - Para ampliarlo: `make snowflake-ampliar-cuota CUOTA=<n>`.
- **Al terminar el curso**: `make destroy`. Borra el lake, Snowflake y AWS.
  - Si confirmas, borra también el bootstrap y el bucket de state.
  - Las cuentas de AWS y Snowflake siguen siendo tuyas.

---

<a id="estructura"></a>
## Estructura del repositorio

Carpetas del repositorio y para qué sirven:

```text
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

---

<a id="instructor"></a>
## Para el instructor

> [!IMPORTANT]
> Esta sección es solo para el instructor.

### Comandos del instructor

- `make publicar-bootstrap`
- `make retirar-bootstrap`
- `make limpieza-total`

<!-- AUTOR: describir cada comando: qué hace, cuándo se usa y si borra recursos. El original solo los nombra (l. 411). -->

### Documentos del instructor

- [`bootstrap.md`, sección 4 (Para el instructor)](bootstrap.md).
- [`airflow/README.md`, sección "Supuestos a verificar"](../airflow/README.md). <!-- AUTOR: confirmar que es de instructor; hoy se ve desde un enlace del README -->
- [`INTEGRACION.md`](INTEGRACION.md): registro histórico.

### Avanzado

Los errores de instructor y avanzado están en [Problemas frecuentes > Avanzado](problemas.md#avanzado).
