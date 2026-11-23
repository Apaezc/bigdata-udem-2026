# Referencia

Material de consulta. No hace falta leerlo para empezar: el recorrido está en la [guía](guia.md).

## Índice

- [Arquitectura](#arquitectura): diagrama y entornos (dev y prod).
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
 |  - tu código, tests, notebooks       |    |  dev/  bronze silver gold                |
 |  - Airflow de dev (make airflow-local)|-->|  prod/ bronze silver gold                |
 |  - make correr, siempre entorno dev  |    |  (dev y prod no comparten carpetas)      |
 |     computo=code_editor: Spark aquí  |    |  code/ dags/ logs/ tmp/: del lake        |
 |     computo=glue_small|medium|large  |    +----------+-------------------------------+
 +------------------+-------------------+               | COPY INTO
                    | PR -> merge a main                 v
                    v                          +----------------------------+
 GitHub Actions (OIDC): CI, Deploy             | Snowflake BIGDATA.DEV /    |
   Terraform + código y DAGs a S3              |   BIGDATA.PROD             |
   + enciende el Airflow de prod  ------+      |   tablas de cada equipo    |
                                        v      |   CONTROL_DEV / CONTROL_PROD
                          +---------------------------+  (tabla de control) |
                          | VM Airflow de prod (EC2)  |-------+-------------+
                          | prod (fijo): solo Glue,   |  Glue 5.0 jobs
                          | límite todos; apagado     |  bigdata-small|medium|large
                          | nocturno; túnel SSM       |
                          +---------------------------+

  Guardrails: Budget (gasto bruto) con bloqueo al 60 % + resource monitor de Snowflake
```

<a id="arquitectura-entornos"></a>
### Entornos

Hay dos entornos, **dev** y **prod**. Usan el mismo código; lo que cambia es dónde quedan los datos. **El entorno no se elige:** todo lo que corres desde el Code Editor (terminal, notebook, `make correr`, Airflow del Code Editor) es dev; prod lo fija solo el despliegue en la VM después de un pull request y del CI/CD, y el código se niega a correr prod fuera de ahí.

| Entorno | Airflow | Cómputo | Datos | Salida |
|---|---|---|---|---|
| **dev** | Code Editor (`make airflow-local`), o ninguno (`make correr`, notebook) | `code_editor` (Spark en tu máquina, límite 1 000 o 100 000), `glue_small`, `glue_medium` o `glue_large` | Lo que diga `limite` (1 000, 100 000 o todos) | `s3://<LAKE>/dev/`, `BIGDATA.DEV`, `BIGDATA.CONTROL_DEV` |
| **prod** | VM dedicada (se enciende con el Deploy) | Solo Glue (`glue_medium` por defecto) | Siempre todo (`limite = todos`) | `s3://<LAKE>/prod/`, `BIGDATA.PROD`, `BIGDATA.CONTROL_PROD` |

- **dev:** pruebas y desarrollo. El **cómputo** es independiente del entorno: puedes calcular con Spark del Code Editor o con Glue, y escribe siempre en `s3://<LAKE>/dev/` y carga en `BIGDATA.DEV`.
- **prod:** el pipeline de verdad, en la VM de Airflow de prod. Lee `main` (lo que desplegó el CI/CD), escribe en `s3://<LAKE>/prod/` y carga en `BIGDATA.PROD`.
- En Snowflake, el rol `BIGDATA_DEV` no puede escribir en `PROD` ni en `CONTROL_PROD`: esa es la barandilla real.

`<LAKE>` es el bucket `bigdata-lake-<CUENTA>-us-east-2` que el [Paso 10](guia.md#paso-10) imprime como `lake_bucket`.

<a id="rutas-del-lake"></a>
### Dónde queda cada dato

Un solo bucket, y **dev y prod no comparten ninguna carpeta**. La regla es una sola:

```text
s3://<LAKE>/<entorno>/<capa>/<tabla>/mes=AAAA-MM/      entorno = dev | prod
                                                       capa = bronze | silver | gold
```

- Un paso de dev solo lee y escribe bajo `dev/`; uno de prod, solo bajo `prod/`.
- `code/`, `dags/`, `logs/` y `tmp/` son del lake y no son de ningún entorno.
- El crudo se descarga una sola vez, la primera vez que corre bronze en cada entorno, a `<entorno>/bronze/_crudo/`. Ya no hay muestra ni entorno `local` sobre el disco.
- Las rutas se arman en un solo lugar (`ruta_lake` en `src/pipeline/herramientas/rutas.py`) y cada lectura o escritura de la casa imprime la ruta completa.
- Para ver la tabla de un entorno: `make rutas ENTORNO=dev`, o `donde_estoy("dev")` (de `pipeline.herramientas`) en un notebook.

Tabla completa, comandos para mover un bucket del diseño anterior y tablas de Athena: [rutas_del_lake.md](rutas_del_lake.md).

<a id="arquitectura-piezas"></a>
### Piezas del repositorio

| Pieza | Dónde | Qué hace |
|---|---|---|
| **Bootstrap** | `bootstrap/` | Plantilla de CloudFormation. Crea tu entorno de trabajo (SageMaker Code Editor), el acceso de GitHub Actions a AWS por OIDC (sin claves), el bucket de state de Terraform y un presupuesto con alertas. Incluye un script SQL para Snowflake. |
| **Infraestructura** | `infra/aws`, `infra/snowflake` | Terraform. AWS: lake S3, catálogo Glue y Athena, jobs Glue, VM de Airflow opcional y guardrails de costo. Snowflake: warehouse XS, base `BIGDATA` (BRONZE/SILVER/GOLD para SQL; DEV y PROD para las tablas del pipeline; CONTROL_DEV y CONTROL_PROD con la tabla de control `WATERMARK`; CONTROL es la historia de la práctica), roles `BIGDATA_DEV` y `BIGDATA_PROD` y stages externos sobre `dev/gold/` y `prod/gold/`. |
| **Pipeline** | `src/pipeline` | Cuatro pasos: bronze (descarga el archivo intacto y lo guarda en Parquet, un lote por ingesta) -> silver (espejo limpio de cada fuente, sin duplicados) -> gold (tablas de negocio) -> snowflake (crea y carga la tabla). Cada paso es una función (`correr_bronze`, `correr_silver`, `correr_gold`, `cargar_snowflake`) que corre con Spark del Code Editor o en Glue, cambiando solo `computo`. Las perillas están en `pipeline.yaml`; `config/dev.yaml` y `config/prod.yaml` solo traen los meses. La caja de herramientas es `pipeline.herramientas` ([herramientas.md](herramientas.md)). |
| **Orquestación** | `airflow/` | DAG `pipeline_taxi` (una tarea por paso, con el nombre de la función), DAG `resetear_entorno` (borra todo el entorno de ese Airflow). Snowpark Connect se compara aparte, en el laboratorio de motores. |
| **Automatización** | `Makefile`, `scripts/`, `.github/workflows/` | Comandos de `make`, sus scripts y los workflows de GitHub Actions. |

---

<a id="bronze"></a>
## Bronze: ingesta con metadatos

Bronze guarda los datos tal como llegan de la fuente, pero ahora los guarda **dos veces** y con un registro de cuándo y de dónde vinieron. Así puedes reconstruir cualquier ingesta, comparar dos ingestas del mismo mes y saber de qué archivo salió cada fila.

### Los dos pasos

1. **Crudo intacto.** El archivo se descarga y se guarda sin modificar ni un byte, en `<entorno>/bronze/_crudo/`. Si el archivo ya está ahí, no se descarga otra vez.
2. **Bronze en Parquet.** Spark lee el crudo y lo escribe en formato Parquet, con las columnas originales sin transformar más cinco columnas de metadatos. Cada ejecución crea una carpeta nueva, llamada **lote**, y nunca borra las anteriores.

```text
<entorno>/bronze/                                    (dev/bronze/ o prod/bronze/)
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

### Qué lotes lee silver

Silver lee, **para cada mes, todos los lotes completos** de bronze y los junta. Cuando bronze termina de escribir un lote, publica en su carpeta el archivo `_LOTE_COMPLETO`. Un lote que no lo tiene (porque la ingesta falló mientras lo escribía) se ignora. Se usa un marcador propio porque Glue no escribe `_SUCCESS` en S3.

Eso tiene una consecuencia que se enseña en la clase 7: **si un mes se ingesta dos veces (`reprocesar=true`), bronze tiene dos lotes del mismo mes y silver los lee los dos**. Si silver no deduplica, cada fila queda dos veces, y gold, que une viajes, zonas y clima, multiplica los viajes por ocho. La función `deduplicar` de `silver.py` (que escribe cada equipo, a partir de `_hash_fila`) es la que hace de silver el espejo limpio de la fuente: pase lo que pase en bronze, silver queda igual.

Reingestar un mes (`make correr PASO=bronze REPROCESAR=true`) crea un lote nuevo sin tocar los anteriores. Como el crudo ya existe, no se vuelve a descargar. Para volver a descargar un archivo hay que borrar su archivo de `_crudo/` (con `aws s3 rm`). Con `reprocesar=false`, la tabla de control salta el mes y no se crea ningún lote.

### Si ya tenías bronze de la versión anterior

Si tu bucket tiene `bronze/` y `muestra/` en la raíz (antes de que cada entorno tuviera su carpeta), corre `make migrar-clase07` (detalle en [curso/clase07/README.md](../curso/clase07/README.md)): mueve el crudo a `prod/` sin volver a descargarlo. Los comandos a mano están en [rutas_del_lake.md](rutas_del_lake.md). Más atrás, una versión guardaba el archivo descargado directamente en `<bronze>/<fuente>/mes=AAAA-MM/<archivo>`. Al ejecutar bronze por primera vez, el pipeline **mueve** ese archivo a `_crudo/` en lugar de descargarlo otra vez, así que los ~5.4 GB del año no se bajan de nuevo. Mover es copiar dentro de S3 y borrar el original solo cuando la copia terminó bien: no quedan dos copias y no se paga almacenamiento doble. Después de la migración, en `bronze/<fuente>/mes=.../` solo quedan carpetas `lote=`. No necesitas borrar nada a mano.

### La muestra y el modo local (retirados)

Hasta la clase 6 existía una muestra (`prod/muestra/`) y un modo local que trabajaba sobre el disco. **Se retiraron en la clase 7.** Ahora el Code Editor corre Spark (`computo = code_editor`) leyendo y escribiendo directamente en `s3://<LAKE>/dev/`, con un `limite` de 1 000 o 100 000 filas por fuente para que sea rápido. Ver [Entornos](#arquitectura-entornos).

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
| `make correr` | Corre el pipeline en dev (`PASO=bronze\|silver\|gold\|snowflake`, `COMPUTO=`, `LIMITE=`, `MES=`, `REPROCESAR=`; lo que no pongas sale de `pipeline.yaml`; sin `PASO` corre los cuatro). El entorno no se elige: siempre es dev | [Paso 13](guia.md#paso-13) |
| `make jars-s3a` | Baja una vez los dos jars que Spark necesita para leer y escribir en S3 (~280 MB, en `~/.spark-jars`) | [Paso 12](guia.md#paso-12) |
| `make migrar-clase07` | Pasa tu cuenta del diseño de las clases 1 a 6 al de la clase 7 (mueve el crudo a `prod/bronze/`, esquemas de Snowflake, jars, Airflow) | [Clase 7](../curso/clase07/README.md) |
| `make rutas` | Imprime en qué bucket y carpetas lee y escribe cada entorno (`ENTORNO=dev\|prod`; vacío = los dos; solo informativo) | [Dónde queda cada dato](#rutas-del-lake) |
| `make airflow-local` / `-down` / `-estado` | Airflow de dev dentro del Code Editor (siempre entorno dev; `computo`, `limite`, `mes` y `reprocesar` se eligen al lanzar el DAG `pipeline_taxi`) | [Paso 13](guia.md#paso-13) · [Apagar](cada-sesion.md#apagar) (`-down`) |
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
#### `make muestra` (retirado en la clase 7)

- Hasta la clase 6, Glue bajaba el año de **FHVHV** a `prod/bronze/` y generaba una muestra. **Ya no existe**: no hay muestra, ni bucket público de muestra, ni entorno `local`.
- Ahora el crudo de cada mes se descarga **una sola vez**, la primera vez que corre bronze (`make correr PASO=bronze`, el notebook o el DAG), directo a `s3://<tu-bucket>/dev/bronze/_crudo/`. Si ya lo tenías en el bucket (diseño anterior), `make migrar-clase07` lo mueve a `prod/bronze/_crudo/` sin volver a descargarlo.
- `make muestra`, `make muestra-solo` y `make run-local` ya no existen: `make` responde «No rule to make target». Usa `make correr`.

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
