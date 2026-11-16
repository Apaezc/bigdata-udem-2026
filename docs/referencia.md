# Referencia

Material de consulta. No hace falta leerlo para empezar: el recorrido está en la [guía](guia.md).

## Índice

- [Arquitectura](#arquitectura): diagrama y entornos (local, dev y prod).
- [Bronze: ingesta con metadatos](#bronze): dónde queda cada archivo, qué columnas se agregan y cómo se elige el lote.
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
 |  - tu código, tests                  |    |  bronze/  (crudo + lotes, compartido)    |
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
| **Infraestructura** | `infra/aws`, `infra/snowflake` | Terraform. AWS: lake S3, catálogo Glue y Athena, jobs Glue, VM de Airflow opcional y guardrails de costo. Snowflake: warehouse XS, base `BIGDATA` (BRONZE/SILVER/GOLD para SQL; DEV/PROD para el pipeline; CONTROL con la tabla `WATERMARK` de la ingesta), rol `BIGDATA_DEV` y stages externos sobre `gold/`, `dev/gold/` y `prod/gold/`. |
| **Pipeline** | `src/pipeline` | bronze (descarga el archivo intacto y lo convierte a Parquet con metadatos) -> silver (limpieza y enriquecimiento) -> gold (métricas diarias por zona y empresa), más el paso `muestra`. Corre con Spark local o en Glue. La configuración de cada entorno está en `src/pipeline/config/<entorno>.yaml`, donde `<entorno>` es local, dev o prod. |
| **Orquestación** | `airflow/` | DAG `pipeline_taxi` con un camino por entorno (local, dev, prod). Snowpark Connect se compara aparte, en el laboratorio de la sesión 7. |
| **Automatización** | `Makefile`, `scripts/`, `.github/workflows/` | Comandos de `make`, sus scripts y los workflows de GitHub Actions. |

---

<a id="bronze"></a>
## Bronze: ingesta con metadatos

Bronze guarda los datos tal como llegan de la fuente, pero ahora los guarda **dos veces** y con un registro de cuándo y de dónde vinieron. Así puedes reconstruir cualquier ingesta, comparar dos ingestas del mismo mes y saber de qué archivo salió cada fila.

### Los dos pasos

1. **Crudo intacto.** El archivo se descarga y se guarda sin modificar ni un byte, en `bronze/_crudo/`. Si el archivo ya está ahí, no se descarga otra vez.
2. **Bronze en Parquet.** Spark lee el crudo y lo escribe en formato Parquet, con las columnas originales sin transformar más cinco columnas de metadatos. Cada ejecución crea una carpeta nueva, llamada **lote**, y nunca borra las anteriores.

```text
bronze/
  _crudo/                                        paso 1: archivos tal como se descargaron
    fhvhv/mes=2024-01/fhvhv_tripdata_2024-01.parquet
    clima/mes=2024-01/open_meteo_2024-01.json
    taxi_zones/taxi_zone_lookup.csv
  fhvhv/mes=2024-01/lote=20260115T143005Z_a3f9c1/   paso 2: Parquet con metadatos
  clima/mes=2024-01/lote=20260115T143005Z_a3f9c1/   una fila por día
  taxi_zones/lote=20260115T143005Z_a3f9c1/
```

El clima llega como un JSON con listas por día. En bronze se convierte a una fila por día (`fecha`, `lluvia_mm`, `temperatura`) y no se cambia nada más.

### Las cinco columnas de metadatos

| Columna | Tipo | Qué contiene |
|---|---|---|
| `_fecha_ingesta` | timestamp (UTC) | El momento en que se ejecutó la ingesta. |
| `_id_lote` | texto | El identificador del lote, con formato `AAAAMMDDTHHMMSSZ_<6 hex>`, por ejemplo `20260115T143005Z_a3f9c1`. Es el mismo para todo lo que se ingesta en una ejecución. |
| `_hash_fila` | texto | La huella SHA-256 de la fila completa (ver abajo). |
| `_fuente` | texto | La URL de donde se descargó el archivo. |
| `_archivo_origen` | texto | El nombre del archivo, por ejemplo `fhvhv_tripdata_2024-01.parquet`. |

**Cómo se calcula `_hash_fila`.** Se toman todas las columnas originales (sin contar los metadatos), cada una se convierte a texto, el valor nulo se reemplaza por el texto `<nulo>` y los textos se unen con `||`. Del texto resultante se calcula el SHA-256 y se guarda en hexadecimal (64 caracteres). La misma fila siempre da el mismo hash, aunque se ingeste en otro lote; si cambia un solo valor, el hash cambia. El marcador `<nulo>` evita que un nulo se confunda con un texto vacío. Las fechas se convierten a texto en UTC, porque el pipeline fija la zona horaria de Spark en UTC.

### Qué lote lee silver

Silver y la muestra leen, **para cada mes, el lote más reciente**: el de mayor `lote=`. Como el identificador empieza con la fecha, el mayor es también el más nuevo. Cuando bronze termina de escribir un lote, publica en su carpeta el archivo `_LOTE_COMPLETO`. Un lote que no lo tiene (porque la ingesta falló mientras lo escribía) se ignora y se usa el anterior. Se usa un marcador propio porque Glue no escribe `_SUCCESS` en S3. Con los mismos datos, silver da el mismo resultado que antes de agregar los metadatos.

Reingestar un mes (`--step bronze --mes 2024-01`) crea un lote nuevo sin tocar los anteriores. Como el crudo ya existe, no se vuelve a descargar. Para volver a descargar un archivo hay que borrar su archivo de `_crudo/` (con `aws s3 rm`).

### Si ya tenías bronze de la versión anterior

La versión anterior guardaba el archivo descargado directamente en `bronze/<fuente>/mes=AAAA-MM/<archivo>`. Al ejecutar `--step bronze` por primera vez, el pipeline **mueve** ese archivo a `_crudo/` en lugar de descargarlo otra vez, así que los ~5.4 GB del año no se bajan de nuevo. Mover es copiar dentro de S3 y borrar el original solo cuando la copia terminó bien: no quedan dos copias y no se paga almacenamiento doble. Después de la migración, en `bronze/<fuente>/mes=.../` solo quedan carpetas `lote=`. No necesitas borrar nada a mano.

### En local

El modo local no tiene bronze: lee la **muestra**. No necesitas generarla: `make run-local` la descarga sola la primera vez. La busca primero en tu bucket (`s3://<LAKE>/muestra`, que genera `make muestra`) y, si ahí no hay una muestra con lotes completos (`_LOTE_COMPLETO`), la baja del bucket público del curso, con acceso anónimo y sin credenciales. La ubicación pública está en `muestra.publica` de `src/pipeline/config/local.yaml`, y el log dice de cuál bucket salió. La muestra tiene la misma estructura que bronze (carpetas `lote=`, con el mismo identificador del lote del que salió) y conserva las cinco columnas de metadatos; no incluye `_crudo/`. Si en tu Code Editor quedó una muestra de la versión anterior, `make run-local` la detecta, la borra y descarga la nueva (de tu bucket si ya la tiene en el formato nuevo, y si no del bucket público).

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
| `make setup` | Verifica herramientas, crea `.venv` con Python 3.12, valida la región de Snowflake, alinea `AWS_REGION` y crea la configuración de AWS en S3 si no existe | [Paso 8](guia.md#paso-8) |
| `make config` | Muestra la configuración de AWS guardada en S3 | — |
| `make secrets` | Carga `AWS_ROLE_ARN` y `TF_STATE_BUCKET` en tu fork desde el bootstrap (lo hace `make setup` si `gh` está autenticado) | [Paso 9](guia.md#paso-9) |
| `make reparar-entorno` | Recrea `.venv` con Python 3.12, reinstala dependencias, registra el kernel y repara `snow`; úsalo si el Code Editor se actualizó y ves `No module named 'snowflake'` | — |
| `make doctor` | Diagnóstico: versiones, entorno de Python (`.venv` con 3.12), AWS, Snowflake, Terraform, OIDC | [Paso 9](guia.md#paso-9) |
| `make estado` | Estado de Airflow, últimos job runs de Glue, warehouse y costos | [Apagar](cada-sesion.md#apagar) |
| `make test` | `ruff check`, `ruff format --check`, `pytest` (y tests de DAGs si Airflow está instalado) | — |
| `make muestra` | Glue: bronze del año de prod + muestra en tu bucket (una vez por curso). El modo local ya no la necesita | [Paso 12](guia.md#paso-12) |
| `make muestra-solo` | Glue: lanza solo el paso `muestra` (job `bigdata-medium`, entorno prod) y espera a que termine. Para quien cerró la terminal de `make muestra` con el bronze del año ya terminado | [Paso 12](guia.md#paso-12) |
| `make run-local` | Pipeline en local sobre la muestra, que descarga sola la primera vez (`STEP=silver\|gold\|all`, `MES=YYYY-MM`, `LIMITE=N`). Sin `LIMITE` procesa toda la muestra | [Paso 13](guia.md#paso-13) |
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

Verifica las herramientas (Python 3.11+, Java 17, AWS CLI, Terraform, `snow`, jq y zip; el **Lifecycle Config** de SageMaker las instala al arrancar), crea `.venv` con Python 3.12 (con `uv`; si el `.venv` existente usa otra versión o está roto, lo recrea), instala `requirements-dev.txt`, registra el kernel **Python (bigdata)**, valida que Snowflake esté en AWS, alinea `AWS_REGION` y crea en S3 la configuración de Terraform.

<a id="make-reparar-entorno"></a>
#### `make reparar-entorno`

Úsalo cuando SageMaker actualice la imagen del Code Editor y cambie la versión de Python del sistema (síntomas: `No module named 'snowflake'` en `.venv` o `No module named 'snowflake.cli'` al usar `snow`). Borra `.venv` y lo crea de nuevo con Python 3.12, reinstala `requirements-dev.txt`, registra el kernel **Python (bigdata)** y comprueba `snow`: si `snow --version` falla, reinstala `snowflake-cli` con el Python de conda (`pip install --user`). Termina con `Entorno reparado: Python 3.12.x, snow OK`.

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
- El script aplica `infra/snowflake` (warehouse `BIGDATA_WH`, base `BIGDATA` con el esquema `CONTROL` y su tabla `WATERMARK`, roles, **stages** —lugares desde donde Snowflake lee archivos— y el usuario `AIRFLOW_SVC`).
- El script aplica la fase 2 de AWS, con la **trust policy** de Snowflake (la regla de AWS que dice quién puede usar el rol), y guarda la conexión de Airflow en el secreto `bigdata/snowflake`.

Conexión de Airflow a Snowflake: no hay nada que hacer a mano. `make snowflake` crea el usuario `AIRFLOW_SVC` en Snowflake (genera su llave en `~/.snowflake/keys/airflow_svc_rsa_key.p8`), aplica la fase 2 de AWS y guarda la conexión en el secreto `bigdata/snowflake`, que usan el Airflow de dev y el de prod.

<a id="make-muestra"></a>
#### `make muestra` ([Paso 12](guia.md#paso-12))

- Glue baja el año de **FHVHV** (los viajes de Uber/Lyft de NYC publicados por la NYC TLC) a `bronze/_crudo/` (~5.4 GB). Si ya los tenías en la ruta anterior de `bronze/`, los mueve en lugar de descargarlos otra vez.
- **Bronze** guarda cada archivo tal como llegó y además lo convierte a Parquet con metadatos (hash de cada fila, fecha de ingesta, lote). Detalle: [Bronze: ingesta con metadatos](#bronze).
- Genera la **muestra** en `muestra/` de tu bucket: un subconjunto pequeño de los datos, con la misma estructura de bronze. Para trabajar en local no hace falta: sin ella, `make run-local` usa la del bucket público del curso.
- Si cerraste la terminal a mitad de camino, `make muestra-solo` lanza únicamente este último paso, sin repetir el bronze del año. Ver [Cerré la terminal mientras corría `make muestra`](problemas.md#p-cerre-terminal-muestra).

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
