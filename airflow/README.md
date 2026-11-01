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
- Conexión Snowflake `snowflake_default`: la arma la VM en cada arranque a partir del secreto `${prefix}/snowflake`
  (Terraform solo crea el contenedor vacío). Guarda en él el JSON de conexión de Airflow (sin `'` dentro):

  ```bash
  aws secretsmanager put-secret-value --secret-id bigdata/snowflake --secret-string '{
    "conn_type": "snowflake", "login": "<USUARIO_SNOWFLAKE>",
    "extra": {"account": "<org>-<cuenta>", "warehouse": "BIGDATA_WH", "database": "BIGDATA",
              "role": "BIGDATA_DEV", "private_key_content": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"}}'
  ```

  El usuario debe tener el rol `BIGDATA_DEV` (variable `dev_users` de `infra/snowflake`) y una clave pública
  registrada (`bootstrap/snowflake/gen_key.sh <USUARIO>` imprime el `ALTER USER`). Después, reinicia la VM
  (`make airflow-off && make airflow-on`) o ejecuta en ella `sudo /usr/local/bin/airflow-refresh.sh && sudo systemctl restart airflow`.
- Los logs de Glue no se muestran en la UI de Airflow (`verbose=False`: el rol de la VM no lee CloudWatch Logs por contrato). El log de la tarea trae los enlaces a la consola de Glue y al Spark UI.

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
2. `make deploy` / `deploy.yml` suben a `s3://<lake>/`: `dags/` (DAGs), `code/airflow/framework/` y `code/airflow/docker-compose.yaml`.
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
`airflow standalone` en 8081, con los DAGs del repo. Mismo DAG, misma URL; el entorno por defecto es `local`
(Spark del `.venv` del repo sobre la muestra) y se puede elegir `dev` (Glue small). Se detiene con `make airflow-local-down`
y se cae si el Code Editor se apaga por inactividad.

Snowpark Connect ya no es parte del DAG: se compara contra Glue en el laboratorio de motores (sesión 7).

## Supuestos a verificar

- Nombres de variables de Airflow 3.3 (`AIRFLOW__API_AUTH__JWT_SECRET`, `AIRFLOW__CORE__SIMPLE_AUTH_MANAGER_*`) y formato del archivo de contraseñas.
- Ruta de salud `/api/v2/version` del api-server.
- Constraints de `https://raw.githubusercontent.com/apache/airflow/constraints-3.3.2/` disponibles para la versión de Python de la imagen.
- Los DAGs importan `framework` como paquete (`PYTHONPATH=/opt/airflow`). Validado en `airflow/tests` con Airflow 3.3.2 real; falta verlo dentro de los contenedores.
- `private_key_content` en la conexión Snowflake del provider 6.17 y el formato del JSON del secreto.
- `env_file` con `required: false` (Docker Compose >= 2.24) con el plugin que instale `dnf` en Amazon Linux 2023.
