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

## Paso 12 · Muestra

<a id="p-timeout-muestra"></a>
### `make muestra` termina en TIMEOUT

- **Síntoma:** el paso termina en `TIMEOUT`.
<!-- AUTOR: el original no indica la causa del TIMEOUT -->
- **Qué hacer:** repítelo con `cd ~/bigdata && make muestra`. Retoma desde lo que ya descargó.
- [Volver al paso 12](guia.md#paso-12)

<a id="p-sin-muestra"></a>
### No hay muestra para correr en local

- **Síntoma:** `make run-local`: "No hay muestra ... falta LAKE_BUCKET"
- **Causa:** todavía no se generó la muestra.
- **Qué hacer:** corre `cd ~/bigdata && make muestra` primero (una vez).
- [Volver al paso 13.1](guia.md#paso-13-1)

## Pipeline local (Java)

<a id="p-java"></a>
### Java no es el correcto

- **Síntoma:** `make test` o `make run-local` fallan por Java.
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
