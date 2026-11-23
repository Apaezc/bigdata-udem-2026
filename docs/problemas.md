# Problemas frecuentes

Busca tu mensaje con **Ctrl+F**. Cada entrada muestra el mensaje exacto, su causa y qué hacer. Vuelve a la [guía](guia.md) o a [Apagar y encender](cada-sesion.md) cuando lo resuelvas.

## Paso 2 · Cuenta nueva y cuotas

<a id="p-cloudshell-verificacion"></a>
### CloudShell no abre: cuenta en verificación

- **Síntoma:** CloudShell responde *"Your account verification is in progress"*.
- **Causa:** AWS todavía está verificando tu cuenta nueva.
- **Qué hacer:** espera el correo de AWS. Hasta que termine no podrás usar CloudShell ni lanzar el bootstrap, y las cuotas pueden seguir en 0.
- [Volver al paso 2.2](guia.md#paso-2-2)

<a id="p-bootstrap-limpiar"></a>
### El bootstrap ya había fallado por una cuota

- **Síntoma:** el bootstrap ya había fallado por una cuota (stack `bigdata-bootstrap`).
- **Causa:** una cuota de AWS no llegó al mínimo (ver el [paso 2](guia.md#paso-2)).
- **Qué hacer:** antes de relanzarlo, borra el stack `bigdata-bootstrap` (**CloudFormation** > **Delete**) y el bucket `bigdata-tfstate-<CUENTA>-us-east-2` (**S3** > **Empty** y **Delete**). `<CUENTA>` es tu número de cuenta de AWS.
- [Volver al paso 2.3](guia.md#paso-2-3)

## Paso 4 · Bootstrap de AWS

<a id="p-entityalreadyexists"></a>
### El stack falla por el proveedor de GitHub (OIDC)

- **Síntoma:** el stack falla con `EntityAlreadyExists` (OIDC).
- **Causa:** la cuenta ya tiene el proveedor de GitHub.
- **Qué hacer:** relanza el stack con `ExistingGitHubOidcProviderArn` ([docs/bootstrap.md](bootstrap.md)).
- [Volver al paso 4.2](guia.md#paso-4-2)

<a id="p-paso-7"></a>
## Paso 7 · Conexión de Snowflake

<a id="p-make-no-rule"></a>
### Comando `make` fuera de la carpeta del fork

- **Síntoma:** `make: *** No rule to make target 'snowflake-conexion'`
- **Causa:** estás fuera de la carpeta del fork (el prompt muestra `~$`).
- **Qué hacer:** `cd ~/bigdata` y repite `make snowflake-conexion`. El prompt debe terminar en `~/bigdata$`.
- [Volver al paso 7.2](guia.md#paso-7-2)

<a id="p-jwt-conexion"></a>
### Enter antes de tiempo o LOGIN incorrecto

- **Síntoma:** `JWT token is invalid`
- **Causa:** pulsaste Enter **antes** de ejecutar el `ALTER USER`, o escribiste en LOGIN el valor de USUARIO (en cuentas trial el login suele ser tu correo).
- **Qué hacer:** usa los valores exactos de la consulta de [7.1](guia.md#paso-7-1). Ejecuta el `ALTER USER`, espera `Statement executed successfully.` y solo entonces pulsa Enter. Para reintentar: `cd ~/bigdata && make snowflake-conexion`.
- [Volver al paso 7.5](guia.md#paso-7-5)

<a id="p-user-no-existe"></a>
### Usuario con mayúsculas distintas

- **Síntoma:** `User '...' does not exist` al ejecutar el `ALTER USER`
- **Causa:** el nombre entre comillas distingue mayúsculas y no coincide con USUARIO.
- **Qué hacer:** copia USUARIO tal cual lo muestra la consulta (mismas mayúsculas y minúsculas).
- [Volver al paso 7.4](guia.md#paso-7-4)

<a id="p-insufficient-privileges"></a>
### Falta el rol ACCOUNTADMIN

- **Síntoma:** `Insufficient privileges` al ejecutar el `ALTER USER`
- **Causa:** faltó `USE ROLE ACCOUNTADMIN;`.
- **Qué hacer:** pega las dos líneas juntas y usa **Run All**.
- [Volver al paso 7.4](guia.md#paso-7-4)

<a id="p-warehouse-bigdata-wh"></a>
### Conexión creada con un script viejo

- **Síntoma:** `Could not use warehouse "BIGDATA_WH"`
- **Causa:** la conexión se creó con una versión vieja del script, que fijaba un warehouse que aún no existe.
- **Qué hacer:** `cd ~/bigdata && git pull` y repite `make snowflake-conexion`, o borra la línea `warehouse = ...` de `~/.snowflake/connections.toml`. <!-- AUTOR: indicar cómo editar `~/.snowflake/connections.toml` (duda 14 de la propuesta) -->
- [Volver al paso 7.6](guia.md#paso-7-6)

<a id="p-jwt-llave"></a>
### La llave privada no coincide con Snowflake

- **Síntoma:** `JWT token is invalid` en `make snowflake`, `make snowflake-conexion` o `snow`
- **Causa:** la llave privada no coincide con la clave pública registrada en Snowflake.
- **Qué hacer:** en Snowsight, como ACCOUNTADMIN, ejecuta `ALTER USER <usuario> SET RSA_PUBLIC_KEY='<clave pública nueva>';` y comprueba con `DESC USER <usuario>` que `RSA_PUBLIC_KEY_FP` coincide con el fingerprint que imprimió el script de llaves. `<usuario>` es tu USUARIO del [paso 7.1](guia.md#paso-7-1). <!-- AUTOR: indicar de dónde se copia `<clave pública nueva>` y qué script de llaves imprime el fingerprint -->
- [Volver al paso 11](guia.md#paso-11)

## Paso 8 · make setup

<a id="p-sin-region-aws"></a>
### Snowflake no está en AWS o en otra región

- **Síntoma:** `make setup` dice que Snowflake no está en AWS.
- **Causa:** la cuenta de Snowflake está en otra nube o región.
- **Qué hacer:** crea otra cuenta trial eligiendo AWS y `us-east-2`. Vuelve al [paso 1](guia.md#paso-1).
- [Volver al paso 8](guia.md#paso-8)

<a id="p-gh-sin-autenticar"></a>
### Aviso de `gh` al terminar `make setup`

- **Síntoma:** `AVISO: Falta autenticar gh para cargar los secrets del fork: 'gh auth login --web' y luego 'make secrets'.`
- **Causa:** falta autenticar `gh` para cargar los secrets del fork.
- **Qué hacer:** es normal la primera vez. Se resuelve en el [paso 9](guia.md#paso-9).
- [Volver al paso 9](guia.md#paso-9)

<a id="p-snow-sin-conexion"></a>
### No hay conexión de `snow`

- **Síntoma:** `make setup` dice que no hay conexión de `snow` (`Connection default is not configured`).
- **Causa:** no existe la conexión `default` de `snow`.
- **Qué hacer:** `cd ~/bigdata && make snowflake-conexion` (el [paso 7](guia.md#paso-7)).
- [Volver al paso 8](guia.md#paso-8)

## Entorno de Python (después de actualizar el Code Editor)

<a id="p-venv-roto"></a>
### `No module named 'snowflake'` o `No module named 'pip'` en `.venv` tras reiniciar el Code Editor

- **Síntoma:** al reiniciar el Code Editor, el notebook o la terminal dicen `ModuleNotFoundError: No module named 'snowflake'` (o `'pandas'`, `'pyspark'`), o `.venv/bin/python -m pip` responde `No module named pip`. `make doctor` marca `.venv` en `[FALLO]`.
- **Causa:** SageMaker actualiza la imagen del Code Editor y cambia la versión de Python del sistema (`/opt/conda/bin/python3` pasó de 3.12 a 3.13). Tu `.venv` era solo un enlace a ese Python, así que ahora apunta a otra versión y deja de ver las librerías que instalaste. Con Python 3.13 tampoco sirve reinstalar a ciegas: `numpy 1.26.4` se compila desde el código fuente y PySpark 3.5 no es compatible.
- **Qué hacer:** `cd ~/bigdata && make reparar-entorno`. El comando borra `.venv`, lo crea de nuevo con Python 3.12 (con `uv`), reinstala `requirements-dev.txt`, registra el kernel **Python (bigdata)** y revisa `snow`. Termina con `Entorno reparado: Python 3.12.x, snow OK`. Después elige de nuevo el kernel en tu notebook y reinícialo.
- [Volver al paso 8](guia.md#paso-8)

<a id="p-snow-cli"></a>
### `No module named 'snowflake.cli'` al usar `snow`

- **Síntoma:** cualquier comando `snow` (`snow --version`, `snow sql`, `make snowflake`) termina con `ModuleNotFoundError: No module named 'snowflake.cli'`.
- **Causa:** `snow` se instaló con `pip install --user` sobre el Python de conda de la imagen anterior (3.12). Al actualizarse la imagen, ese Python cambió a 3.13 y las librerías del usuario de 3.12 ya no se ven.
- **Qué hacer:** `cd ~/bigdata && make reparar-entorno` también comprueba `snow` y lo reinstala si falla. Si prefieres hacerlo a mano: `/opt/conda/bin/python3 -m pip install --user snowflake-cli` y luego `snow --version`.
- [Volver al paso 8](guia.md#paso-8)

## Paso 9 · Secrets del fork

<a id="p-ci-secrets"></a>
### Faltan secrets en el fork

- **Síntoma:** `ci.yml` o `deploy.yml` fallan pidiendo `AWS_ROLE_ARN` o `TF_STATE_BUCKET`.
- **Causa:** faltan los secrets en tu fork.
- **Qué hacer:** `cd ~/bigdata && make secrets` en el Code Editor, con `gh auth login` hecho. En PRs desde forks el plan se omite a propósito.
- [Volver al paso 9](guia.md#paso-9)

## Paso 10 · make deploy

<a id="p-falta-config-s3"></a>
### Falta la configuración de AWS en S3

- **Síntoma:** `Falta la configuración en S3. Corre 'make setup' en Code Editor.`
- **Causa:** no existe `config/aws.tfvars` en S3.
- **Qué hacer:** `cd ~/bigdata && make setup` en el Code Editor. Crea `config/aws.tfvars`.
- [Volver al paso 10](guia.md#paso-10)

<a id="p-falta-config-s3-region"></a>
### Falta la configuración en S3 aunque ya corriste `make setup`

- **Síntoma:** `Falta la configuración en S3` aunque ya corriste `make setup`.
- **Causa:** tu terminal tiene otro `AWS_REGION`.
- **Qué hacer:** `cd ~/bigdata && export AWS_REGION=us-east-2`.
- [Volver al paso 10](guia.md#paso-10)

<a id="p-modulenotfound"></a>
### Un job de Glue no encuentra el módulo `pipeline`

- **Síntoma:** un job Glue falla con `ModuleNotFoundError: pipeline`.
- **Causa:** falta subir el código.
- **Qué hacer:** `cd ~/bigdata && make deploy`. Sube `pipeline.zip` con la carpeta `pipeline/`.
- [Volver al paso 12](guia.md#paso-12)

## Paso 12 · Muestra (retirada en la clase 7)

<a id="p-timeout-muestra"></a>
<a id="p-cerre-terminal-muestra"></a>
<a id="p-sin-muestra"></a>
### `make muestra`, `make muestra-solo` o `make run-local` dicen «No rule to make target»

- **Síntoma:** el comando imprime `make: *** No rule to make target 'muestra'` (o `muestra-solo`, o `run-local`) y sale con error.
- **Causa:** esos comandos se retiraron en la clase 7: ya no hay muestra ni modo local sobre el disco. Todo corre contra S3: dev en `s3://<LAKE>/dev/` y prod en `s3://<LAKE>/prod/`.
- **Qué hacer:** usa `cd ~/bigdata && make correr PASO=bronze`. El crudo se descarga solo la primera vez. Si Spark se queja de los jars, corre antes `cd ~/bigdata && make jars-s3a`.
- [Volver al paso 12](guia.md#paso-12) · [Volver al paso 13.1](guia.md#paso-13-1)

<a id="p-sin-lote-en-dev"></a>
### `No hay ningún lote completo en s3://.../dev/bronze/...`

- **Síntoma:** un paso `silver` (o `muestra`) falla con `No hay ningún lote completo en s3://<LAKE>/dev/bronze/fhvhv/mes=2024-01`.
- **Causa:** dev y prod no comparten carpetas. El crudo que ya tenías está en `prod/bronze/`, y dev solo lee `dev/bronze/`, que está vacío hasta que dev corra su propio paso `bronze`.
- **Qué hacer:** corre primero el paso bronze en dev: `cd ~/bigdata && make correr PASO=bronze` (o la tarea `correr_bronze` del DAG `pipeline_taxi`). Descarga enero a `dev/bronze/_crudo/` y escribe el lote.
- **Qué no hacer:** copiar a mano `prod/bronze/` hacia `dev/`: para eso está la tarea `bronze`. Si quieres ahorrar la descarga, los comandos están en [rutas_del_lake.md](rutas_del_lake.md#copiar-crudo-a-dev).
- [Volver al paso 13.2](guia.md#paso-13-2)

<a id="p-carpetas-antiguas"></a>
### `Quedan carpetas del diseño anterior` (`make doctor`, `make estado` o `make deploy`)

- **Síntoma:** el aviso lista `s3://<LAKE>/bronze/`, `muestra/`, `silver/` o `gold/` en la raíz del bucket.
- **Causa:** tu bucket se llenó antes de que cada entorno tuviera su propia carpeta. Ya nadie lee esas carpetas: el pipeline lee y escribe solo bajo `dev/` o `prod/`.
- **Qué hacer:** muévelas o bórralas con los comandos de [rutas_del_lake.md](rutas_del_lake.md#migrar). No es un error: solo ocupan espacio.

## Pipeline local (Java)

<a id="p-java"></a>
### Java no es el correcto

- **Síntoma:** `make test` o `make correr` fallan por Java.
- **Causa:** Java no está instalado o no es la versión validada (Java 17).
- **Qué hacer:** instala Java 17 (versión con la que se validó PySpark 3.5) y revisa `cd ~/bigdata && java -version` y `JAVA_HOME`.
- [Volver al paso 13.1](guia.md#paso-13-1)

## Paso 13 · Airflow de dev y DAG

<a id="p-cargar-gold"></a>
### El DAG falla en `cargar_gold`

- **Síntoma:** el DAG falla en `cargar_gold`.
- **Causa:** falta la conexión de Airflow.
- **Qué hacer:** `cd ~/bigdata && make snowflake-secreto` (o `make snowflake`) y reinicia Airflow: `cd ~/bigdata && make airflow-local-down && make airflow-local` (dev), o `cd ~/bigdata && make airflow-off && make airflow-on` (prod). Consulta [airflow/README.md](../airflow/README.md).
- [Volver al paso 13.2](guia.md#paso-13-2)

<a id="p-airflow-ui-blanco"></a>
### La UI de Airflow sale en blanco

- **Síntoma:** la UI de Airflow sale en blanco o "Unsupported URL path".
- **Causa:** la URL no tiene el formato exacto.
- **Qué hacer:** usa exactamente `.../codeeditor/default/ports/8080/` (no `/proxy/` ni `/ports/8080/` sin `/codeeditor/default`).
- [Volver al paso 13.1](guia.md#paso-13-1)

<a id="p-auth-token"></a>
### Sesión de Studio vencida

- **Síntoma:** "Invalid or Expired Auth Token" al abrir la UI.
- **Causa:** venció la sesión de Studio.
- **Qué hacer:** vuelve a abrir Studio desde la consola de AWS.
- [Volver al paso 13.1](guia.md#paso-13-1)

<a id="p-id-del-space"></a>
### La URL muestra `<id-del-space>`

- **Síntoma:** en vez de la URL ves `<id-del-space>`.
- **Causa:** falta el subdominio de tu Code Editor en esa línea.
- **Qué hacer:** reemplázalo por el subdominio de la URL del Code Editor que tienes abierta en el navegador (`https://<id-del-space>.studio.us-east-2.sagemaker.aws/...`).
- [Volver al paso 13.1](guia.md#paso-13-1)

## Encender y apagar

<a id="p-explorador-sin-carpeta"></a>
### El explorador dice `No folder opened`

- **Síntoma:** el explorador de la izquierda dice `No folder opened`.
- **Causa:** la carpeta no está abierta; tus archivos siguen ahí.
- **Qué hacer:** Menú ☰ > **File > Open Folder…** > `/home/sagemaker-user/bigdata/` > **OK**. Para comprobarlo en la terminal: `cd ~/bigdata && ls` (debe listar `Makefile`, `README.md`, `src`…).
- [Volver a Encender 1](cada-sesion.md#encender-1)

<a id="p-puerto-8080"></a>
### El puerto 8080 está ocupado

- **Síntoma:** `El puerto 8080 está ocupado (¿Airflow de dev encendido?)`
- **Causa:** el Airflow de dev sigue arriba.
- **Qué hacer:** `cd ~/bigdata && make airflow-local-down` y repite `make airflow-tunel`.
- [Volver al paso 14.4](guia.md#paso-14-4)

<a id="p-tunel"></a>
### El túnel a Airflow de prod no abre

- **Síntoma:** `make airflow-tunel` no abre el túnel.
- **Causa:** la VM no está encendida.
- **Qué hacer:** `cd ~/bigdata && make airflow-on`. El Lifecycle Config instala `session-manager-plugin`.
- [Volver al paso 14.4](guia.md#paso-14-4)

<a id="p-vm-stopped"></a>
### La VM de prod está apagada

- **Síntoma:** `La instancia está 'stopped'. Ejecuta 'make airflow-on' primero.`
- **Causa:** la VM de prod está apagada.
- **Qué hacer:** `cd ~/bigdata && make airflow-on`, espera 2 min y repite `make airflow-tunel`.
- [Volver al paso 14.4](guia.md#paso-14-4)

<a id="p-vm-inexistente"></a>
### Nunca habilitaste prod

- **Síntoma:** `No existe la instancia bigdata-airflow`
- **Causa:** nunca habilitaste prod.
- **Qué hacer:** `cd ~/bigdata && make airflow-habilitar` (el [paso 14](guia.md#paso-14)).
- [Volver al paso 14.4](guia.md#paso-14-4)

<a id="p-accessdenied-presupuesto"></a>
### AccessDenied: actuó el presupuesto

- **Síntoma:** `AccessDenied` al encender la VM o lanzar jobs de Glue.
- **Causa:** probablemente actuó el presupuesto (60 %).
- **Qué hacer:** `cd ~/bigdata && make estado` y, si corresponde, `make desbloquear`.
- [Volver al paso 12](guia.md#paso-12)

<a id="p-airflow-pagina-error"></a>
### La página de Airflow da error al abrirla

- **Síntoma:** la página da error al abrir la URL que imprime `make airflow-tunel`.
- **Causa:** Airflow tarda ~2 min en responder.
- **Qué hacer:** recarga la página al minuto.
- [Volver a Encender 4](cada-sesion.md#encender-4)

<a id="p-warehouse-started"></a>
### El warehouse sigue encendido

- **Síntoma:** `BIGDATA_WH: estado=STARTED` en `make estado`.
- **Causa:** todavía no se ha suspendido: se suspende solo a los 60 s sin consultas.
- **Qué hacer:** espera un minuto.

<a id="p-control-watermark"></a>
### No se encontró la tabla BIGDATA.CONTROL.WATERMARK

- **Síntoma:** al consultar o registrar en la tabla de control (`consultar_watermark`, `registrar_watermark`, o una prueba del lab de la clase 5) sale `No se encontró la tabla BIGDATA.CONTROL.WATERMARK, o el rol ACCOUNTADMIN no tiene permiso sobre ella`. Si usas una versión anterior del repositorio, puede salir `Insufficient privileges to operate on database 'BIGDATA'`.
- **Causa:** la base `BIGDATA` es del rol `TERRAFORM_ROLE`, y `ACCOUNTADMIN` no puede crear esquemas dentro de ella. Por eso el esquema `CONTROL`, la tabla y los permisos de `ACCOUNTADMIN` y `BIGDATA_DEV` los crea Terraform, y todavía no los has aplicado.
- **Qué hacer:** `cd ~/bigdata && git pull && make snowflake` y escribe `yes` cuando pida confirmar el plan. Solo agrega recursos nuevos; después repite la celda.
- [Volver al paso 11](guia.md#paso-11)

<a id="avanzado"></a>
## Avanzado

Para el instructor o para quien ya conoce el proyecto. Si sigues el curso, no lo necesitas.
- [Volver a Apagar 3](cada-sesion.md#apagar-3)

<a id="p-oidc-assumerole"></a>
### GitHub Actions no puede asumir el rol

- **Síntoma:** GitHub Actions: `Not authorized to perform sts:AssumeRoleWithWebIdentity`
<!-- AUTOR: causa no indicada en el original -->
- **Qué hacer:** revisa `AWS_ROLE_ARN` y los IDs numéricos del bootstrap. Ejecuta el workflow **Debug OIDC** y compara el claim `sub`.

<a id="p-aws-account-id"></a>
### La terminal apunta a otra cuenta de AWS

- **Síntoma:** `AWS_ACCOUNT_ID=... no coincide con la cuenta real` en `make destroy` o `make deploy`.
- **Causa:** tu terminal apunta a otra cuenta.
- **Qué hacer:** exporta el perfil correcto con `cd ~/bigdata && export AWS_PROFILE=<perfil>` (`<perfil>` es el perfil de AWS de tu cuenta), o quita `AWS_ACCOUNT_ID` del entorno. En el Code Editor no hace falta.

<a id="p-plan-destruye"></a>
### El plan destruye recursos

- **Síntoma:** `El plan destruye recursos` en el deploy.
- **Causa:** el plan incluye eliminar o reemplazar recursos.
- **Qué hacer:** revisa la lista del plan. Si es intencional (p. ej. apagar Airflow), repite con `CONFIRMAR_DESTRUCCION=true` o el input `confirmar_destruccion`.
- [Volver al paso 10](guia.md#paso-10)

<a id="p-boundary"></a>
### Terraform: AccessDenied al crear un rol IAM

- **Síntoma:** Terraform: `AccessDenied` al crear un rol IAM.
- **Causa:** el rol no lleva la boundary `<prefix>-boundary`.
- **Qué hacer:** el rol debe llevar la boundary `<prefix>-boundary` (`permissions_boundary_arn`). `<prefix>` es el valor de `prefix` en la [configuración](referencia.md#configuracion).

<a id="p-state-lock"></a>
### Terraform: state bloqueado

- **Síntoma:** Terraform: `Error acquiring the state lock`
- **Causa:** otro apply está corriendo. Si no, el lock quedó de un apply interrumpido.
- **Qué hacer:** `terraform force-unlock <ID>` en la carpeta de Terraform. <!-- AUTOR: indicar la carpeta exacta de Terraform y de dónde sale `<ID>` -->
- [Volver al paso 11](guia.md#paso-11)

<a id="p-deploy-colgado"></a>
### `make deploy` se queda colgado o pierde el lock

- **Síntoma:** `make deploy` se queda colgado o pierde el lock.
<!-- AUTOR: causa no indicada en el original -->
- **Qué hacer:** córrelo con `cd ~/bigdata && make deploy` en una terminal normal, no desde herramientas con tiempo límite.
- [Volver al paso 10](guia.md#paso-10)
