# Airflow en la VM (Fase 3)

Airflow 3.3.2 en una sola EC2 (`m7i-flex.large`, 8 GB), con LocalExecutor y Postgres 16.
Sin Celery ni Redis. Los DAGs llegan desde `s3://<lake>/dags/` y el compose desde `s3://<lake>/code/airflow/`.

## Servicios

| Servicio      | Función                                  | Límite de memoria (default) |
|---------------|------------------------------------------|-----------------------------|
| postgres      | metadatos (Postgres 16)                  | 512m                        |
| init          | `airflow db migrate` (una vez)           | 1g                          |
| api-server    | UI y API en el puerto 8080               | 1g                          |
| scheduler     | planifica y ejecuta tareas (LocalExecutor) | 1536m                     |
| dag-processor | parsea DAGs                              | 768m                        |
| triggerer     | tareas diferidas                         | 512m                        |

Suma de límites ~4.3 GB, más 2 GB de swap que crea user-data. Los límites se ajustan con `MEM_*` en `.env`.
Con `c7i-flex.large` (4 GB) o `t3.small` (2 GB) no caben: bajar límites o no usar esas instancias.

## Imagen

`docker-compose.yaml` construye `bigdata/airflow-extended:3.3.2` desde `apache/airflow:3.3.2`
e instala `apache-airflow-providers-amazon` y `apache-airflow-providers-snowflake` con los constraints
oficiales de Airflow 3.3.2 (con ellas resuelven amazon 9.36.0 y snowflake 6.17.0, las mismas de `requirements.txt`).
El Dockerfile es inline en el compose; no hay archivo extra.

## Conexiones y credenciales

- `aws_default`: definida por variable de entorno (`AIRFLOW_CONN_AWS_DEFAULT`), sin claves. Usa el rol de instancia
  `bigdata-airflow-vm` a través de IMDSv2 (hop limit 2 para contenedores).
- Usuario de la UI: `admin`. La contraseña está en Secrets Manager (`${prefix}/airflow-admin`, campo `password`).
  User-data la escribe en `/opt/airflow/secrets/simple_auth_manager_passwords.json`.
  SimpleAuthManager no es apto para producción.
- Conexión Snowflake `snowflake_default`: la escribe `make snowflake` en el secreto `${prefix}/snowflake` (script
  `scripts/snowflake-secreto.sh`; Terraform solo crea el contenedor vacío). Es el JSON de conexión de Airflow, con el
  usuario `AIRFLOW_SVC`, `account`, `warehouse` `BIGDATA_WH`, `database` `BIGDATA`, `role` `BIGDATA_DEV` y la llave
  privada de `~/.snowflake/keys/airflow_svc_rsa_key.p8` en `private_key_content`. No hay que escribir el JSON a mano.
  Lo leen el Airflow de dev (`make airflow-local` lo carga al arrancar) y el de prod (la VM lo arma en cada arranque).
  - `AIRFLOW_SVC` lo crea Terraform con el rol `BIGDATA_DEV`, y su llave la genera el Makefile (`make airflow-key`).
  - Para reescribir el secreto sin tocar Snowflake: `make snowflake-secreto`.
  - Tras cambiar el secreto, reinicia Airflow: en dev, `make airflow-local-down && make airflow-local`; en prod,
    `make airflow-off && make airflow-on` (o, dentro de la VM, `sudo /usr/local/bin/airflow-refresh.sh && sudo systemctl restart airflow`).
- Logs de Glue: `verbose=True` copia en el log de la tarea los logs del job (CloudWatch `/aws-glue/jobs/...`) y los enlaces a la consola de Glue y al Spark UI.

## Los DAGs

| DAG | Dónde corre | Qué hace |
|---|---|---|
| `pipeline_taxi` | los dos Airflow | `correr_bronze` → `correr_silver` → `correr_gold` → `cargar_snowflake` (el pipeline) |
| `resetear_entorno` | los dos Airflow; cada uno resetea solo el suyo | vacía el entorno para repetir el pipeline desde cero |

## `pipeline_taxi`: entorno y perillas

Son dos cosas distintas:

- **Entorno** (dónde quedan los datos): lo fija cada Airflow con `PIPELINE_ENTORNO` y **no se elige al lanzar**.
  El Airflow del Code Editor es `dev` (`s3://<lake>/dev/`, `BIGDATA.DEV`, `BIGDATA.CONTROL_DEV`) y la VM es `prod`
  (`s3://<lake>/prod/`, `BIGDATA.PROD`, `BIGDATA.CONTROL_PROD`). No hay un parámetro de entorno: el entorno aparece en
  el `doc_md` del DAG y en el banner de cada tarea. Detalle en [docs/rutas_del_lake.md](../docs/rutas_del_lake.md).
- **Perillas** (el formulario de «Trigger DAG»): `computo`, `limite`, `mes` y `reprocesar`. Lo que pones en el
  formulario gana sobre `pipeline.yaml`.

| Perilla | Dev | Prod |
|---|---|---|
| `computo` | `code_editor`, `glue_small`, `glue_medium`, `glue_large`; valor inicial: el de `pipeline.yaml` | solo `glue_small`, `glue_medium`, `glue_large`; valor inicial `glue_medium` |
| `limite` | `1000`, `100000`, `todos` (texto); con `code_editor` solo 1000 o 100000 | solo `todos` |
| `mes` | `AAAA-MM`; vacío = los meses de `config/dev.yaml` | `AAAA-MM`; valor inicial `2024-01` durante el curso (vacío lanzaría los doce meses) |
| `reprocesar` | casilla | casilla |

Prod no lee `pipeline.yaml`. En dev, si `pipeline.yaml` trae un valor inválido (por ejemplo `limite: 12345` o
`computo: foo`) el DAG se parsea igual: el formulario arranca con el valor por defecto y el aviso queda en el
`doc_md` y en el log. Un cambio en `pipeline.yaml` tarda unos 30 segundos en llegar al formulario.

Si llega algo que el formulario no ofrece (por ejemplo con `airflow dags trigger --conf`), la tarea falla con un
mensaje claro **antes de tocar nada**: en prod, un `computo` que no sea `glue_*` o un `limite` distinto de `todos`;
en dev, `code_editor` con `todos`.

Cómo se lanza cada tarea (`framework/tasks.py`):

- `computo = code_editor`: el CLI `python -m pipeline.run --paso <paso> ...` con el Python del `.venv` del repo y
  `PIPELINE_ENTORNO=dev`; el banner sale en el log de la tarea. Con `mes` vacío corre cada mes de `config/dev.yaml`.
- `computo = glue_*`: la tarea llama directo a `correr_<paso>(...)` en el proceso de Airflow, que usa `lanzar_en_glue`
  (en dev sube el código de tu árbol de trabajo a `code/dev/`; en prod usa `code/pipeline.zip`). No hace falta Spark.
- `cargar_snowflake`: llama a `cargar_snowflake(..., conexion=...)` con la conexión `snowflake_default`, sin Spark ni
  Glue, y exige antes el rol del entorno (`BIGDATA_DEV` o `BIGDATA_PROD`).

Las cuatro tareas no reintentan solas (`retries=0`): una corrida mal hecha no se repite sin que alguien lo decida.
`max_active_runs=1` y `max_active_tasks=1`.

## `resetear_entorno`

El mismo archivo (`dags/resetear_entorno.py`) está en los dos Airflow y **cada uno borra solo su entorno**: el del
Code Editor, dev; la VM, con el rol de prod, prod. El parámetro `entorno` solo admite el de ese Airflow.

| Qué | Cómo | No toca |
|---|---|---|
| Capas de S3 | todos los objetos bajo `s3://<lake>/<entorno>/` (con `_crudo`; «Conservar el crudo» deja `bronze/_crudo/`) | el otro entorno, `code/`, `dags/`, `logs/`, `tmp/` |
| Tabla de control | `DELETE FROM BIGDATA.CONTROL_<ENTORNO>.WATERMARK` | `CONTROL_<otro>`, `CONTROL` (historia) |
| Snowflake | `DROP` de cada tabla y vista de `BIGDATA.<ENTORNO>` | el stage `LAKE_GOLD`, el formato `PARQUET_FF`, el otro esquema |
| Athena | nada: las tablas externas quedan apuntando a carpetas vacías | |

Tareas, en orden: `validar` → `contar` → `vaciar_control` → `borrar_snowflake` → `borrar_s3` → `resumen`. La tabla de
control va primero: si algo falla a medias queda «no procesado», nunca «procesado sin datos».

Salvaguardas:

1. El DAG nace pausado y sin calendario.
2. `solo_listar` viene marcada: la primera corrida cuenta y lista lo que se borraría y termina.
3. Para borrar hay que desmarcar `solo_listar` **y** escribir la confirmación: `borrar dev`; en prod,
   `borrar prod <ID de la cuenta AWS>` (el que da `aws sts get-caller-identity`). No hay un valor por defecto que borre.
4. Antes de borrar se exige el rol del entorno (`BIGDATA_DEV` o `BIGDATA_PROD`; `ACCOUNTADMIN` se rechaza). Si entre
   `contar` y cada paso de borrado cambia el recuento (registros, tablas u objetos), la tarea se detiene.
5. El prefijo de S3 sale de `ruta_lake` y se verifica que empiece por `<entorno>/`; el esquema es `BIGDATA.DEV` o
   `BIGDATA.PROD` y se valida con una expresión regular.

Son barandillas contra errores, no un control contra el dueño de la cuenta: el control real es Snowflake (el rol de
dev no escribe en `PROD` ni `CONTROL_PROD`) más el rol de la VM (solo ve `prod/`). La lógica que borra está en
`src/pipeline/herramientas/reseteo.py`; sus pruebas, en `tests/test_reseteo.py` y `airflow/tests/`.

## Ejecución local (prueba)

```bash
cd airflow
cp .env.example .env        # reemplazar POSTGRES_PASSWORD, AIRFLOW_FERNET_KEY y AIRFLOW_JWT_SECRET
mkdir -p dags logs plugins secrets framework
docker compose up -d --build --wait
```

Para la UI local hace falta un `secrets/simple_auth_manager_passwords.json` con `{"admin": "<clave>"}`;
si no existe, Airflow genera una clave aleatoria en ese archivo.
Validación sin levantar nada: `docker compose -f airflow/docker-compose.yaml --env-file airflow/.env.example config -q`.

## Despliegue en la VM

1. Terraform (`infra/aws/modules/airflow_vm`, con `enable_airflow = true`) crea la instancia (tag `Name=<prefix>-airflow`),
   el SG `<prefix>-airflow-sg` (sin ingress), los secretos y el apagado a las 23:00 (America/Bogota). Sin IP fija.
2. `deploy.yml` (CI/CD, merge a `main`) sube a `s3://<lake>/`: `dags/` (los DAGs), `code/airflow/framework/` y `code/airflow/docker-compose.yaml`.
3. User-data instala `/usr/local/bin/airflow-refresh.sh`, que copia esos objetos a `/opt/airflow/` y arma `snowflake.env`.
   Corre al crear la VM y antes de cada arranque de `airflow.service` (que levanta el compose); por cron, cada minuto, se
   sincronizan `dags/` y `framework/`. El `docker-compose.yaml` nuevo se aplica en el siguiente arranque.
4. La UI se abre solo por túnel SSM desde el Code Editor: `make airflow-tunel` y la URL
   `https://<id-del-space>.studio.<region>.sagemaker.aws/codeeditor/default/ports/8080/` (nginx `proxy-studio` vuelve a poner
   el prefijo que quita el proxy de Studio). Esta VM es el Airflow de **prod** (`PIPELINE_ENTORNO=prod`); la enciende el Deploy.

Los DAGs importan `framework` con `sys.path.insert(<carpeta padre de dags/>)` y `PYTHONPATH=/opt/airflow` en el compose;
en la VM quedan `/opt/airflow/dags` y `/opt/airflow/framework`, y en el repo `airflow/dags` y `airflow/framework`.

## Airflow de dev (Code Editor)

`make airflow-local` instala Airflow 3.3.2 con pip en `~/.airflow-local` (solo la primera vez), levanta nginx en 8080 y
`airflow standalone` en 8081, con los DAGs del repo. Mismo DAG, misma URL. El entorno es siempre `dev`
(`PIPELINE_ENTORNO=dev`) y el cómputo se elige con `computo` (por defecto el de `pipeline.yaml`; `code_editor` es Spark del `.venv` leyendo y escribiendo en `s3://<lake>/dev/`).
Al arrancar lee el secreto `${prefix}/snowflake`; si cambia, reinicia con `make airflow-local-down && make airflow-local`.
Se detiene con `make airflow-local-down` y se cae si el Code Editor se apaga por inactividad.

Este Airflow tiene los mismos dos DAGs que el de prod: `pipeline_taxi` y `resetear_entorno`.

## Supuestos a verificar

- Nombres de variables de Airflow 3.3 (`AIRFLOW__API_AUTH__JWT_SECRET`, `AIRFLOW__CORE__SIMPLE_AUTH_MANAGER_*`) y formato del archivo de contraseñas.
- Ruta de salud `/api/v2/version` del api-server.
- Constraints de `https://raw.githubusercontent.com/apache/airflow/constraints-3.3.2/` disponibles para la versión de Python de la imagen.
- Los DAGs importan `framework` como paquete (`PYTHONPATH=/opt/airflow`). Validado en `airflow/tests` con Airflow 3.3.2 real; falta verlo dentro de los contenedores.
- `private_key_content` en la conexión Snowflake del provider 6.17 y el formato del JSON del secreto.
- `env_file` con `required: false` (Docker Compose >= 2.24) con el plugin que instale `dnf` en Amazon Linux 2023.

## Pruebas de los DAGs

```bash
cd ~/bigdata
python -m pytest airflow/tests tests/test_reseteo.py -q     # con Airflow instalado (CI, o el venv de make airflow-local)
```

`airflow/tests/test_dag_integrity.py` (carga, tareas y orden; el DAG se parsea sin pyspark), `test_params.py`
(formulario, `pipeline.yaml` inválido, enums y barandillas de prod) y `test_reseteo_dag.py` (confirmaciones, `solo_listar`,
orden control → Snowflake → S3). Sin Airflow instalado, `make test` las omite y corren en CI.
