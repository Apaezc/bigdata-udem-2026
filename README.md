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
5. **Code Editor.** En la consola de AWS: **Amazon SageMaker AI > Domains** > tu dominio > pestaña **User profiles** > `estudiante` > **Launch > Studio**. En Studio: **Code Editor** > Space `dev` > **Run space** (la primera vez tarda 3-5 min) > **Open**. Abre una terminal: menú **Terminal > New Terminal**.
   (No abras el enlace `StudioConsoleUrl` directamente: pide un token y da "Invalid or Expired Auth Token".)
6. **Clona tu fork** en la terminal del Code Editor, siempre en la carpeta `~/bigdata` (así todos los comandos de esta guía se copian y pegan tal cual, sin cambiar nada). Solo aquí reemplazas `<TU_USUARIO>` y `<TU_FORK>` por los tuyos:
   ```bash
   cd ~
   git clone https://github.com/<TU_USUARIO>/<TU_FORK>.git ~/bigdata
   cd ~/bigdata
   ```
   Ejemplo: `git clone https://github.com/jperez/bigdata-udem-2026.git ~/bigdata`. Todos los comandos `make` de aquí en adelante se ejecutan **dentro de `~/bigdata`**: el prompt debe terminar en `~/bigdata$`.
7. **Conexión de Snowflake.**
   1. **Averigua tus datos.** En Snowsight crea una hoja con el botón **+** (arriba a la izquierda) > **SQL Worksheet**, pega esto y pulsa **Run All** (flecha junto a ▶):
      ```sql
      USE ROLE ACCOUNTADMIN;
      SHOW USERS;
      SELECT CURRENT_ORGANIZATION_NAME() || '-' || CURRENT_ACCOUNT_NAME() AS account_identifier,
             "name" AS usuario, "login_name" AS login
      FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "name" = CURRENT_USER();
      ```
      Verás algo así (tus valores serán otros). `USUARIO` y `LOGIN` pueden ser distintos (por ejemplo, el login es tu correo): el script pide los dos.
      ```text
      ACCOUNT_IDENTIFIER | USUARIO | LOGIN
      ABCDEFG-XY12345    | jperez  | JPEREZ@GMAIL.COM
      ```
   2. **Ejecuta el script** en la terminal del Code Editor:
      ```bash
      cd ~/bigdata
      make snowflake-conexion
      ```
      Escribe los dos valores cuando te los pida:
      ```text
      Account identifier (ORGNAME-ACCOUNTNAME): ABCDEFG-XY12345
      USUARIO (columna USUARIO): jperez
      LOGIN (columna LOGIN): JPEREZ@GMAIL.COM
      ```
   3. **Copia las dos líneas** que imprime el script (`USE ROLE` y `ALTER USER`). Se ve así (la clave es mucho más larga):
      ```text
      Último paso: en Snowsight, en una hoja (+ > SQL Worksheet), pega estas dos líneas juntas y
      ejecútalas con 'Run All' (flecha junto a ▶):

      USE ROLE ACCOUNTADMIN;
      ALTER USER "jperez" SET RSA_PUBLIC_KEY='MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA...';

      Cuando la hayas ejecutado, pulsa Enter para probar la conexión...
      ```
   4. **Ejecútalas en Snowsight.** En la misma hoja borra lo que había, pega las dos líneas y pulsa **Run All** (flecha junto a ▶). Debe responder `Statement executed successfully.`
   5. **Vuelve a la terminal y pulsa Enter.** El script prueba la conexión. Si todo está bien, termina con `Conexión configurada. Siguiente paso: make setup`.
   6. **Comprueba** cuando quieras:
      ```bash
      cd ~/bigdata
      snow connection test
      ```
      Salida exitosa (con tus valores): `Status` debe ser `OK` y `User` tu LOGIN. Que `Database` y `Warehouse` digan `not set` es normal en este punto: se crean en el paso 11.
      ```text
      +----------------------------------------------------------+
      | key             | value                                  |
      |-----------------+----------------------------------------|
      | Connection name | default                                |
      | Status          | OK                                     |
      | Host            | abcdefg-xy12345.snowflakecomputing.com |
      | Account         | abcdefg-xy12345                        |
      | User            | JPEREZ@GMAIL.COM                       |
      | Role            | ACCOUNTADMIN                           |
      | Database        | not set                                |
      | Warehouse       | not set                                |
      +----------------------------------------------------------+
      ```

   **Errores comunes del paso 7 (y cómo evitarlos):**

   | Mensaje | Causa | Cómo evitarlo / resolverlo |
   |---|---|---|
   | `make: *** No rule to make target 'snowflake-conexion'` | Estás fuera de la carpeta del fork (el prompt muestra `~$`). | `cd ~/bigdata` y repite. El prompt debe terminar en `~/bigdata$`. |
   | `JWT token is invalid` | Pulsaste Enter **antes** de ejecutar el `ALTER USER`, o escribiste en LOGIN el valor de USUARIO (en cuentas trial el login suele ser tu correo). | Usa los valores exactos de la consulta del paso 1. Ejecuta el `ALTER USER`, espera `Statement executed successfully.` y solo entonces pulsa Enter. Para reintentar: `cd ~/bigdata && make snowflake-conexion`. |
   | `User '...' does not exist` al ejecutar el `ALTER USER` | El nombre entre comillas distingue mayúsculas y no coincide con USUARIO. | Copia USUARIO tal cual lo muestra la consulta (mismas mayúsculas/minúsculas). |
   | `Insufficient privileges` al ejecutar el `ALTER USER` | Faltó `USE ROLE ACCOUNTADMIN;`. | Pega las dos líneas juntas y usa **Run All**. |
   | `Could not use warehouse "BIGDATA_WH"` | Conexión creada con una versión vieja del script que fijaba un warehouse que aún no existe. | `cd ~/bigdata && git pull` y repite `make snowflake-conexion` (o borra la línea `warehouse = ...` de `~/.snowflake/connections.toml`). |

   No compartas ni subas la llave privada: queda en `~/.snowflake/keys/<usuario>_key.p8` y no sale del Code Editor. La sentencia `ALTER USER` solo lleva la llave pública.
8. **`make setup`.**
   ```bash
   cd ~/bigdata
   make setup
   make doctor
   ```
   Te pide un correo para las alertas de presupuesto. Salida exitosa de `make setup` (la primera vez; tu cuenta y correo serán otros):
   ```text
   ==> Verificando herramientas
   ==> Entorno virtual y dependencias de desarrollo
   ==> Validando región de Snowflake (snow sql)
   ==> Región de Snowflake: AWS_US_EAST_2 -> us-east-2
   ==> Configuración guardada en .env (PREFIX=bigdata, AWS_REGION=us-east-2)
   ==> Configuración de AWS en S3 (s3://bigdata-tfstate-123456789012-us-east-2/config/aws.tfvars)
   Correo para las alertas de presupuesto (alert_email): jperez@gmail.com
   ==> Configuración creada en S3 (enable_glue=true, enable_airflow=false).
   AVISO: Falta autenticar gh para cargar los secrets del fork: 'gh auth login --web' y luego 'make secrets'.
   ==> Setup completado. Siguiente paso: make doctor
   ```
   El `AVISO` de `gh` es normal la primera vez: se resuelve en el paso 9. Si la región de Snowflake no es `AWS_US_EAST_2`, la cuenta de Snowflake está en otra nube o región: vuelve al paso 1.

   Verifica herramientas (Python 3.11+, Java 17, AWS CLI, Terraform, `snow`, jq, zip; las instala el Lifecycle Config al arrancar), crea `.venv`, valida que Snowflake esté en AWS, alinea `AWS_REGION` y crea en S3 la configuración de Terraform (te pide el correo de alertas).
9. **Secrets del fork: automáticos.** `make setup` los carga (`AWS_ROLE_ARN` y `TF_STATE_BUCKET`). Si te dice que GitHub no está autenticado, hazlo una vez y repite:
   ```bash
   cd ~/bigdata
   gh auth login --hostname github.com --git-protocol https --web
   make secrets
   ```
   Así se ve `gh auth login` (tu código será otro):
   ```text
   ? Authenticate Git with your GitHub credentials? Yes        <- responde Yes (Enter)
   ! Failed to copy one-time code to clipboard                 <- normal en Code Editor, ignóralo
   ! First copy your one-time code: 1234-ABCD                  <- copia este código
   Press Enter to open https://github.com/login/device in your browser...
   ✓ Authentication complete.
   ✓ Configured git protocol
   ! Authentication credentials saved in plain text            <- normal, quedan solo en tu Code Editor
   ✓ Logged in as <TU_USUARIO>
   ```
   Al pulsar Enter el navegador no se abre solo: abre tú `https://github.com/login/device` en otra pestaña, pega el código y pulsa **Authorize**. Vuelve a la terminal y espera `✓ Logged in as <TU_USUARIO>`.

   Salida exitosa de `make secrets` y `make doctor` (versiones, cuenta y usuario serán los tuyos):
   ```text
   ==> Cargando secrets en <TU_USUARIO>/<TU_FORK>
   ✓ Set Actions secret AWS_ROLE_ARN for <TU_USUARIO>/<TU_FORK>
   ✓ Set Actions secret TF_STATE_BUCKET for <TU_USUARIO>/<TU_FORK>
   ==> Secrets listos: AWS_ROLE_ARN y TF_STATE_BUCKET (2 en total).

   ==> Herramientas y versiones
   [OK]     python3: Python 3.12.x
   [OK]     java: openjdk version "17.0.x"
   [OK]     aws: aws-cli/2.x
   [OK]     terraform: Terraform v1.17.0
   [OK]     snow: Snowflake CLI version: 3.x
   [OK]     jq / zip / session-manager-plugin
   ==> AWS
   [OK]     aws sts get-caller-identity: cuenta 123456789012
   [OK]     Bucket de estado de Terraform accesible
   ==> Snowflake
   [OK]     snow connection test
   ==> Estado OIDC para GitHub Actions
   [INFO]   No se puede listar el proveedor OIDC con este rol (normal en Code Editor)
   [OK]     Rol bigdata-github-actions existe

   ==> Diagnóstico sin fallos
   ```
   Lo importante es la última línea: `Diagnóstico sin fallos`. Las líneas `[INFO]` son informativas; cualquier `[FALLO]` dice qué revisar.

10. **`make deploy`.**
    ```bash
    cd ~/bigdata
    make deploy
    ```
    Aplica `infra/aws` (lake, Glue, Athena, guardrails y, si lo activas, Airflow) y sube a S3 el código del pipeline (`pipeline.zip`, `run_glue.py`), los DAGs y el framework de Airflow. La VM de prod solo existe si activas Airflow con `make airflow-habilitar` (cambia `enable_airflow` y despliega); el Airflow de dev corre en el Code Editor y no lo necesita. También se ejecuta solo en cada push a `main`.

    Salida exitosa (el final; la cuenta será la tuya). La primera vez Terraform crea unos 23 recursos:
    ```text
    Apply complete! Resources: 23 added, 0 changed, 0 destroyed.

    Outputs:

    glue_jobs = tomap({
      "large" = "bigdata-large"
      "medium" = "bigdata-medium"
      "small" = "bigdata-small"
    })
    lake_bucket = "bigdata-lake-123456789012-us-east-2"
    snowflake_s3_role_arn = "arn:aws:iam::123456789012:role/bigdata-snowflake-s3"
    ==> Empaquetando src/pipeline
    ==> Subiendo código, DAGs y framework a s3://bigdata-lake-123456789012-us-east-2/
    upload: build/pipeline.zip to s3://.../code/pipeline.zip
    ...
    ==> Deploy completado
    ```
    Guarda `lake_bucket` y `snowflake_s3_role_arn`: los usas en el paso 11.

11. **Snowflake (después de AWS).** Un solo comando:
    ```bash
    cd ~/bigdata
    make snowflake
    ```
    Usa tu conexión de `snow` (paso 7) y los outputs del paso 10, así que no hay que copiar valores ni editar archivos. Hace, en orden:
    1. Genera la llave de `TERRAFORM_SVC` en `~/.snowflake/keys/` y ejecuta `bootstrap/snowflake/01_admin.sql` (resource monitor `BIGDATA_RM`, `TERRAFORM_ROLE`, usuario `TERRAFORM_SVC`).
    2. Escribe `infra/snowflake/terraform.tfvars` y `backend.hcl` (si no existen) con tu cuenta, el lake y tu usuario en `dev_users`.
    3. Aplica `infra/snowflake` (warehouse `BIGDATA_WH`, base `BIGDATA`, roles, stages y el usuario `AIRFLOW_SVC`). **Te pide confirmar el plan: escribe `yes`.**
    4. Aplica la fase 2 de AWS (trust policy de Snowflake) y guarda la conexión de Airflow en el secreto `bigdata/snowflake`.

    Salida exitosa (fragmentos; es larga y la mayoría es Terraform). Busca estas líneas, en este orden:
    ```text
    ==> Ejecutando bootstrap/snowflake/01_admin.sql (resource monitor, TERRAFORM_ROLE, TERRAFORM_SVC)
    ==> Snowflake listo para Terraform:
    ...
    Do you want to perform these actions?  Enter a value: yes      <- escribe yes
    Apply complete! Resources: 39 added, 0 changed, 0 destroyed.  <- Snowflake creado
    ==> Fase 2 de AWS: deploy.sh con la trust policy de Snowflake
    Plan: 0 to add, 1 to change, 0 to destroy.                   <- solo cambia el rol bigdata-snowflake-s3
    Apply complete! Resources: 0 added, 1 changed, 0 destroyed.
    ==> Deploy completado
    ==> Conexión de AIRFLOW_SVC guardada en el secreto bigdata/snowflake.
    ```
    Si la última línea aparece, el paso terminó bien. El plan de la fase 2 **no debe** eliminar recursos (`0 to destroy`); si lo hiciera, el script se detiene solo.

    **Conexión de Airflow a Snowflake: no hay nada que hacer a mano.** `make snowflake` crea el usuario `AIRFLOW_SVC` en Snowflake (genera su llave en `~/.snowflake/keys/airflow_svc_rsa_key.p8`), aplica la fase 2 de AWS y guarda la conexión en el secreto `bigdata/snowflake`, que usan el Airflow de dev y el de prod. Si Airflow ya estaba encendido, reinícialo: `make airflow-local-down && make airflow-local` (dev) y `make airflow-off && make airflow-on` (prod). Para repetir solo ese paso: `make snowflake-secreto`.

    Detalle: [infra/snowflake/README.md](infra/snowflake/README.md).

12. **Prepara los datos (una vez).**
    ```bash
    cd ~/bigdata
    make muestra
    ```
    Glue baja el año de FHVHV a `bronze/` (~5.4 GB) y genera la muestra en `muestra/` (~US$0.15, ~5 min). Si termina en `TIMEOUT`, repítelo: retoma desde lo que ya descargó.
    Salida exitosa (los ids de run serán otros):
    ```text
    ==> Glue bigdata-small --step bronze (run jr_...)
    ==> bronze OK
    ==> Glue bigdata-medium --step muestra (run jr_...)
    ==> muestra OK
    ==> Muestra lista en s3://bigdata-lake-123456789012-us-east-2/muestra. En local: make run-local (la descarga la primera vez).
    ```
    La terminal se queda quieta varios minutos entre líneas mientras Glue trabaja: es normal, no la cierres.

13. **Desarrolla en local y dev.**
    ```bash
    cd ~/bigdata
    make run-local        # o: make run-local LIMITE=100 (prueba rapidísima)
    make airflow-local    # Airflow de dev
    ```
    Salida exitosa de `make run-local LIMITE=100` (final; tardará ~30 s). Los avisos `WARN` de Spark son normales:
    ```text
    INFO Muestra descargada de s3://.../muestra a /home/sagemaker-user/bigdata/lake/muestra (25 archivos)   <- solo la primera vez
    INFO Paso=silver env=local engine=local meses=2024-01
    INFO Calidad OK [silver]: 100 filas
    INFO Paso=gold env=local engine=local meses=2024-01
    INFO Calidad OK [gold]: 79 filas
    ```
    `make airflow-local` imprime al final la URL de tu Airflow, lista para abrir (`UI: https://...studio.us-east-2.sagemaker.aws/codeeditor/default/ports/8080/`). Ábrela y lanza `pipeline_taxi`.
    - Entra con usuario `admin` y la contraseña que imprime `make airflow-local`. Los DAGs nuevos aparecen **pausados** (la página Home dice `Active Dags 0`): en **Dags** activa el interruptor de `pipeline_taxi`, entra al DAG y pulsa **Trigger**.
    - Run exitoso con `glue_small` (10-15 min): `preparar_entorno`, `elegir_computo`, `bronze`, `silver`, `gold` y `cargar_gold` en verde (`success`); `silver_spark_local` y `gold_spark_local` en rosa (`skipped`), porque son la rama de `spark_local`.
    - Si en vez de la URL ves `<id-del-space>`, reemplázalo por el subdominio de la URL del Code Editor que tienes abierta en el navegador (`https://<id-del-space>.studio.us-east-2.sagemaker.aws/...`).
    - El Airflow del Code Editor es siempre el entorno **dev** (no se elige al lanzar). Lo que eliges es el parámetro `computo`, que decide con qué recursos se calcula:
      - `spark_local`: Spark en el Code Editor sobre la muestra (gratis). Como mucho 10 000 filas por fuente. El resultado queda en `./lake` y no se carga en Snowflake.
      - `glue_small`, `glue_medium` o `glue_large`: Glue con 2, 4 o 6 workers. Escribe en `s3://<lake>/dev/` y carga en `BIGDATA.DEV` (`glue_small` cuesta centavos).
    - `mes`: vacío = todos los meses del entorno (en dev, solo `2024-01`), o un mes concreto en formato `YYYY-MM`.
    - `limite` (opcional): máximo de viajes a procesar; vacío = sin recorte.
    - Verifica el resultado en Snowsight con el rol `BIGDATA_DEV` y el warehouse `BIGDATA_WH`:
      ```sql
      USE ROLE BIGDATA_DEV;
      USE WAREHOUSE BIGDATA_WH;
      SELECT COUNT(*), MIN(fecha), MAX(fecha) FROM BIGDATA.DEV.DAILY_ZONE_METRICS;
      ```
      Resultado esperado con `glue_small` (todo enero de 2024):
      ```text
      COUNT(*) | MIN(FECHA) | MAX(FECHA)
      15909    | 2024-01-01 | 2024-01-31
      ```
      La tabla la crea el propio DAG en `cargar_gold` la primera vez. Un run con `spark_local` no la modifica.
14. **Pasa a prod con un PR.** La primera vez, crea la VM de Airflow de prod (no existe hasta que la habilitas):
    ```bash
    cd ~/bigdata
    make airflow-habilitar
    ```
    Después, al hacer merge a `main`, el Deploy publica código y DAGs y enciende la VM de prod si cambiaron `airflow/` o `src/`. Desde el Code Editor, primero apaga el Airflow de dev (usan el mismo puerto 8080) y abre el túnel; deja esa terminal abierta:
    ```bash
    cd ~/bigdata
    make airflow-local-down
    make airflow-tunel
    ```
    Abre la URL que imprime `make airflow-tunel` (la misma que en dev), usuario `admin` y contraseña de `make airflow-password`. En prod el entorno también es fijo (`prod`, en la VM) y solo hay `computo=glue_medium` o `glue_large`, sin límite de filas: lanza `pipeline_taxi` con esos valores. En prod el DAG no tiene rama local: un run exitoso muestra solo seis tareas, todas en `success` (`preparar_entorno`, `elegir_computo`, `bronze`, `silver`, `gold`, `cargar_gold`); con `glue_medium` y `mes=2024-01` tarda ~5 min. La conexión de Snowflake ya está en el secreto `bigdata/snowflake` (la escribe `make snowflake`; ver [airflow/README.md](airflow/README.md)).

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

## Apagar y encender (día a día)

Lo que cuesta mientras está encendido es el **Code Editor** (~US$0.10/h) y la **VM de Airflow de prod**. Glue y Snowflake solo cobran mientras corren un job o una consulta y se detienen solos. Al terminar cada sesión apaga en este orden:

### Apagar

1. **Airflow de prod (VM).** Si tienes el túnel abierto, ciérralo con **Ctrl+C** en esa terminal. Luego:
   ```bash
   cd ~/bigdata
   make airflow-off
   ```
   Salida exitosa:
   ```text
   ==> Apagando instancia i-0123456789abcdef0 (estado actual: running)
   ==> Instancia apagada.
   ```
   (Si ya estaba apagada: `==> La instancia ... ya está apagada.`) Aunque lo olvides, se apaga sola a las 23:00 (hora de Bogotá).
2. **Airflow de dev.**
   ```bash
   cd ~/bigdata
   make airflow-local-down
   ```
   Salida exitosa: `==> Airflow local y nginx detenidos.`
3. **Comprueba** que no quede nada corriendo:
   ```bash
   cd ~/bigdata
   make estado
   ```
   En la sección `Airflow` la instancia debe aparecer `stopped`, y en `Últimos 3 job runs de Glue` ninguno en `RUNNING`.
4. **Code Editor (lo último, porque cierra tu terminal).** En la pestaña de **SageMaker Studio** (no la del Code Editor): menú izquierdo **Code Editor** > en la lista de Spaces, fila `dev` > **Stop**. El estado pasa a `Stopping` y luego a `Stopped` (~1 min). Si lo olvidas, se apaga solo tras 60 minutos de inactividad.

   Tus archivos (`~/bigdata`, `~/.snowflake`, `.env`) se conservan: viven en el disco del Space, no en la instancia.

### Encender

1. **Code Editor.** Consola de AWS > **Amazon SageMaker AI > Domains** > tu dominio > **User profiles** > `estudiante` > **Launch > Studio**. En Studio: **Code Editor** > Space `dev` > **Run space** (~2 min) > **Open**. Abre una terminal: **Terminal > New Terminal**.
2. **Trae los últimos cambios del repo:**
   ```bash
   cd ~/bigdata
   git pull
   ```
3. **Airflow de dev** (cuando lo necesites):
   ```bash
   cd ~/bigdata
   make airflow-local
   ```
   Al final imprime `UI: https://...studio.us-east-2.sagemaker.aws/codeeditor/default/ports/8080/`, usuario `admin` y la contraseña. Tarda ~1 min (la instalación solo ocurre la primera vez).
4. **Airflow de prod** (cuando lo necesites; no puede estar encendido a la vez que el de dev, usan el puerto 8080):
   ```bash
   cd ~/bigdata
   make airflow-local-down
   make airflow-on
   make airflow-password
   make airflow-tunel
   ```
   `make airflow-on` termina con `==> Airflow de prod encendido (Airflow tarda ~2 min en responder).` Espera esos 2 minutos antes de abrir la URL que imprime `make airflow-tunel`, y deja esa terminal abierta. Si la página da error, recárgala al minuto.

   Un merge a `main` que cambie `airflow/` o `src/` también enciende la VM de prod (Deploy).

| Mensaje | Causa | Qué hacer |
|---|---|---|
| `El puerto 8080 está ocupado (¿Airflow de dev encendido?)` | El Airflow de dev sigue arriba. | `cd ~/bigdata && make airflow-local-down` y repite `make airflow-tunel`. |
| `La instancia está 'stopped'. Ejecuta 'make airflow-on' primero.` | La VM de prod está apagada. | `cd ~/bigdata && make airflow-on`, espera 2 min y repite `make airflow-tunel`. |
| `No existe la instancia bigdata-airflow` | Nunca habilitaste prod. | `cd ~/bigdata && make airflow-habilitar` (paso 14). |
| `AccessDenied` al encender la VM o lanzar Glue | Actuó el presupuesto (60 %). | `cd ~/bigdata && make estado` y, si corresponde, `make desbloquear`. |

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
