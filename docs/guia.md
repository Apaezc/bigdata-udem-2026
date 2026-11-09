# Guía paso a paso

Recorrido de 14 pasos, en orden, para desplegar el pipeline en tu propia cuenta. Si ya hiciste la guía y solo vuelves a trabajar, ve a [Cada sesión](cada-sesion.md); si algo falla, a [Problemas frecuentes](problemas.md).

<a id="indice"></a>
## Índice

- [Antes de empezar](#antes-de-empezar)
- [Parte 1 · Cuentas](#parte-1)
  - [Paso 1 · Crea tu cuenta de Snowflake](#paso-1)
  - [Paso 2 · Crea tu cuenta de AWS y revisa las cuotas](#paso-2)
  - [Paso 3 · Haz un fork y activa GitHub Actions](#paso-3)
- [Parte 2 · Entorno de trabajo](#parte-2)
  - [Paso 4 · Lanza el bootstrap de AWS](#paso-4)
  - [Paso 5 · Abre tu Code Editor](#paso-5)
  - [Paso 6 · Clona tu fork](#paso-6)
  - [Paso 7 · Conecta Snowflake](#paso-7)
  - [Paso 8 · Ejecuta `make setup`](#paso-8)
  - [Paso 9 · Autentica GitHub, carga los secrets y comprueba el entorno](#paso-9)
- [Parte 3 · Infraestructura y datos](#parte-3)
  - [Paso 10 · Despliega AWS y sube el código del pipeline](#paso-10)
  - [Paso 11 · Crea los recursos de Snowflake](#paso-11)
  - [Paso 12 · Prepara los datos (una vez)](#paso-12)
- [Parte 4 · Desarrollar y publicar](#parte-4)
  - [Paso 13 · Desarrolla en local y dev](#paso-13)
  - [Paso 14 · Pasa a prod con un PR](#paso-14)
- [Listo](#listo)
- [Glosario](#glosario)

<a id="antes-de-empezar"></a>
## Antes de empezar

Necesitas tres cuentas:

- **Snowflake**, cuenta de prueba (*trial*): [Paso 1](#paso-1).
- **AWS**, con plan gratuito: [Paso 2](#paso-2).
- **GitHub**: [Paso 3](#paso-3). <!-- AUTOR: prerrequisitos no dichos en el original: ¿hace falta tarjeta de crédito para AWS o Snowflake? ¿la cuenta de GitHub debe existir antes del Paso 3? (duda 6) -->

Haz los pasos en este orden.

### Dos palabras clave

- **terminal**: ventana donde escribes comandos de texto y ves su respuesta.
- **consola de AWS**: web de Amazon donde creas y administras tus recursos en la nube.

### Tus ventanas

Cada paso o sub-paso indica en qué ventana estás con uno de estos marcadores:

| Marcador | Qué es |
|---|---|
| 🌐 **GitHub** | El sitio de GitHub, donde está tu copia del código. |
| ☁️ **Consola AWS** | La consola de AWS, incluida la pestaña **Studio**. |
| ❄️ **Snowsight** | La interfaz web de Snowflake, donde ejecutas consultas SQL (el lenguaje para consultar tablas). |
| 💻 **Terminal del Code Editor** | La terminal dentro de tu **Code Editor** (editor de código en el navegador, tipo VS Code). |
| 🧭 **Navegador** | Cualquier otra web: snowflake.com, `github.com/login/device` o la interfaz web de **Airflow** (programa que ejecuta tareas de datos en orden). |

### Tiempo y costo

<!-- AUTOR: tiempo total estimado de los pasos 1 a 14; el original no lo indica (duda 12) -->
Cifras aproximadas:

- **Encendido:** el Code Editor cuesta ~US$0.10/h y se apaga solo tras 60 minutos de inactividad. La **VM** (computadora virtual en la nube) de Airflow de prod también cuesta mientras está encendida. <!-- AUTOR: ¿cuánto cuesta esa VM encendida? El original no lo dice. --> Apagada, solo paga el disco (~US$2.4/mes).
- **Datos:** la muestra cuesta ~US$0.15 ([Paso 12](#paso-12)). Con **Glue** (servicio de AWS para trabajos de datos), 1 mes en `small` cuesta ~US$0.02 y el año en `large` ~US$0.12. Glue y Snowflake solo cobran mientras corre un job o una consulta.
- **Presupuesto** (AWS Budgets): se crea `bigdata-mensual` con 50 USD por defecto y alertas al 40 y 80 %. Al 60 %, AWS impide iniciar jobs de Glue y máquinas virtuales, y detiene la VM de Airflow de prod (`make desbloquear` lo revierte).

> [!NOTE]
> Estimaciones aproximadas; verifica precios vigentes en la consola de AWS y de Snowflake. Detalle en [Costos](referencia.md#costos).

<a id="parte-1"></a>
## Parte 1 · Cuentas

<a id="paso-1"></a>
### Paso 1 de 14 · Crea tu cuenta de Snowflake

**Para qué:** tener una cuenta de prueba (*trial*) de **Snowflake** (plataforma de datos en la nube donde se publican las tablas) en AWS, en la **región** (lugar geográfico donde AWS tiene sus servidores) `us-east-2`.

🧭 **Navegador**

1. Crea la cuenta de prueba en snowflake.com.
2. Elige la nube **AWS**.
3. Elige la región **US East (Ohio)** (`us-east-2`).

**❌ Si falla:** si la cuenta queda en Azure/GCP u otra región de AWS, tendrás que crear otra cuenta: [detalle y qué hacer](problemas.md#p-sin-region-aws). `make setup` te lo avisará en el [Paso 8](#paso-8).

<!-- AUTOR: ✅ del Paso 1: ¿qué debe ver el estudiante al terminar? El original no lo dice. -->

**Siguiente:** [Paso 2](#paso-2)

<a id="paso-2"></a>
### Paso 2 de 14 · Crea tu cuenta de AWS y revisa las cuotas

**Para qué:** tener tu cuenta de AWS lista en `us-east-2`, con las **cuotas** (límite de recursos que AWS permite en tu cuenta) suficientes para el curso.

**Antes:** haber terminado el [Paso 1](#paso-1).

> [!IMPORTANT]
> Trabaja siempre en `us-east-2`.

<a id="paso-2-1"></a>
#### 2.1 · Crea tu cuenta de AWS

☁️ **Consola AWS**

1. Crea tu cuenta de AWS (plan gratuito).
2. Entra con el usuario raíz (**root**: el correo y la contraseña con los que creaste la cuenta de AWS), solo para lanzar el **bootstrap** (la configuración inicial que crea los recursos base de tu cuenta). Te recomendamos activar MFA (verificación en dos pasos) en ese usuario.

<a id="paso-2-2"></a>
#### 2.2 · Revisa las cuotas

☁️ **Consola AWS**

Revisa estas cuatro cuotas (región `us-east-2`) antes del [Paso 4](#paso-4) y pide las que falten.

> [!NOTE]
> En cuentas nuevas AWS suele dejar algunas cuotas en `0` aunque su valor por defecto sea mayor, y entonces el bootstrap o el Code Editor fallan.
>
> **Service Quotas** es la página de AWS donde ves y pides cuotas. **SageMaker** es el servicio donde se crea tu Code Editor. **EC2** son servidores virtuales de AWS (aquí, la VM de Airflow de prod).
>
> **Glue** y **EC2** normalmente ya alcanzan en una cuenta nueva (Glue: 2000 ejecuciones simultáneas y 1000 DPU por cuenta, el valor por defecto; el curso usa como máximo 6 workers): no hace falta pedir nada de Glue.

| Servicio | Cuota (nombre exacto en Service Quotas) | Código | Mínimo necesario | Si está por debajo, falla… | En una cuenta nueva |
|---|---|---|---|---|---|
| Amazon SageMaker | Maximum number of Studio user profiles allowed per account | — | 1 | el bootstrap (`StudentUserProfile`: `ServiceLimitExceeded`) | Pídela |
| Amazon SageMaker | Studio CodeEditor Apps running on ml.t3.large instances | `L-656A17FA` | 1 | el **Run space** del Code Editor | Pídela |
| Amazon SageMaker | Total domains | — | 1 | el bootstrap (`SageMakerDomain`) | Pídela |
| Amazon EC2 | Running On-Demand Standard (A, C, D, H, I, M, R, T, Z) instances | `L-1216C47A` | 2 (vCPU) | `make airflow-habilitar` (VM de prod) | Normalmente ya alcanza (8 vCPU); solo revísala |

**Cómo revisarlas.** Opción rápida:

1. Abre **CloudShell** (terminal dentro de la consola de AWS; icono `>_` arriba a la derecha, región `us-east-2`).
2. Pega esto y pulsa Enter:

```bash
for q in "sagemaker:Studio user profiles" "sagemaker:CodeEditor Apps running on ml.t3.large" \
         "sagemaker:Total domains" "ec2:Running On-Demand Standard"; do
  aws service-quotas list-service-quotas --service-code "${q%%:*}" --region us-east-2 \
    --query "Quotas[?contains(QuotaName,'${q#*:}')].[QuotaName,Value]" --output text
done
```

**✅ Debes ver:** (todas con valor **≥ el mínimo** de la tabla; los valores de abajo son de ejemplo y pueden variar):

```text
Maximum number of Studio user profiles allowed per account	2.0
Studio CodeEditor Apps running on ml.t3.large instances	6.0
Total domains	2.0
Running On-Demand Standard (A, C, D, H, I, M, R, T, Z) instances	8.0
```

**Opción manual:**

1. Abre **Service Quotas > AWS services** y elige *el servicio* (para la cuota de EC2, entra al servicio **EC2**).
2. Busca *el nombre de la cuota* y mira la columna **Applied account-level quota value**.

**❌ Si falla:** [`Your account verification is in progress`](problemas.md#p-cloudshell-verificacion). Si CloudShell responde eso, AWS todavía está verificando tu cuenta nueva. Hasta que termine (te llega un correo) no podrás usar CloudShell ni lanzar el bootstrap, y las cuotas pueden seguir en `0`.

<a id="paso-2-3"></a>
#### 2.3 · Pide las cuotas que falten (solo si alguna está por debajo)

☁️ **Consola AWS**

1. Abre **Service Quotas > AWS services** > *el servicio* > *el nombre de la cuota* > **Request increase at account-level**.
2. Escribe el valor por defecto de la cuota. El formulario no acepta menos (por ejemplo, para Code Editor `ml.t3.large` exige `6` aunque solo uses 1).
3. Envía la solicitud.
4. Sigue el estado en **Service Quotas > Quota request history**. Algunas se aprueban en minutos; otras se convierten en un caso de soporte (**Support > Your support cases**).
5. **Si es un caso**, responde en él con tu caso de uso, por ejemplo:

> Use case: university Big Data course. I will run one SageMaker Studio Code Editor app on ml.t3.large in us-east-2 for development, stopped when not in use. Budgets and cost alerts are configured.

6. Cuando el valor aplicado sea ≥ el mínimo, sigue con el [Paso 4](#paso-4).
7. **Solo si** el bootstrap ya había fallado por una cuota, antes de relanzarlo borra el stack `bigdata-bootstrap` (**CloudFormation** > **Delete**; CloudFormation es el servicio de AWS que crea recursos desde una plantilla) y el bucket `bigdata-tfstate-<CUENTA>-us-east-2` (**S3** > **Empty** y **Delete**; S3 es el servicio de AWS para guardar archivos y el bucket su carpeta de nivel superior; reemplaza `<CUENTA>` por el ID de tu cuenta de AWS).

> [!NOTE]
> Pedir un aumento no cuesta nada: la cuota es un límite, y AWS solo cobra lo que de verdad corre.

**Siguiente:** [Paso 3](#paso-3)

<a id="paso-3"></a>
### Paso 3 de 14 · Haz un fork y activa GitHub Actions

**Para qué:** tener tu propia copia del **repositorio** (carpeta de código con su historial de cambios, guardada en GitHub) con sus automatizaciones activadas.

**Antes:** haber terminado el [Paso 2](#paso-2).

🌐 **GitHub**

1. Haz un **fork** (copia personal, en tu cuenta de GitHub, de un repositorio ajeno) de este repositorio.
2. Abre la pestaña **Actions** de tu fork (**GitHub Actions** es el sistema de GitHub que ejecuta tareas automáticas: *workflows*).
3. Habilita los workflows: pulsa **"I understand my workflows, go ahead and enable them"**.

<!-- AUTOR: ✅ del Paso 3: propuesta (F04) «la URL del repositorio lleva tu usuario». El original no lo dice; confirmar. -->

**Siguiente:** [Paso 4](#paso-4)

<a id="parte-2"></a>
## Parte 2 · Entorno de trabajo

Aquí preparas tu entorno: recursos en AWS, tu Code Editor, el proyecto y la conexión a Snowflake.

<a id="paso-4"></a>
### Paso 4 de 14 · Lanza el bootstrap de AWS

**Para qué:** crear de una vez los recursos base de tu cuenta AWS con el **bootstrap**, el primer paso de configuración.

**Tiempo:** ~3-4 min

> [!NOTE]
> **CloudFormation** es el servicio de AWS que crea recursos desde una plantilla. El **stack** es el conjunto de recursos que crea.

<a id="paso-4-1"></a>
#### 4.1 · Lanza el workflow de bootstrap

🌐 **GitHub**

1. En tu fork, abre la pestaña **Actions**.
2. Abre el workflow **"Enlace de bootstrap"**.
3. Pulsa **Run workflow**.
4. Abre el run (la ejecución) que lanzaste.
5. En el resumen del run, pulsa el enlace **Launch Stack**. Se abre la consola de AWS.

<a id="paso-4-2"></a>
#### 4.2 · Crea el stack

☁️ **Consola AWS**

Tus datos de GitHub ya vienen completados: no los cambies.

1. En **VpcId**, elige la VPC que dice *default*.
2. En **SubnetIds**, marca todas las subnets de esa VPC.
3. En **AlertEmail**, escribe tu correo.
4. Marca la casilla *I acknowledge that AWS CloudFormation might create IAM resources with custom names*.
5. Pulsa **Create stack**.
6. Espera unos 3-4 min a que el stack llegue a `CREATE_COMPLETE`.

> [!NOTE]
> La **VPC** es la red privada virtual de tu cuenta de AWS; sus **subnets** son sus subredes. **IAM** son los permisos de AWS.

**✅ Debes ver:** en **CloudFormation > bigdata-bootstrap**, el estado `CREATE_COMPLETE`.

**❌ Si falla:** [`EntityAlreadyExists`](problemas.md#p-entityalreadyexists) · [el bootstrap falló por una cuota](problemas.md#p-bootstrap-limpiar) (borra el stack y el bucket antes de relanzarlo)

Referencia (no necesaria para empezar): [docs/bootstrap.md](bootstrap.md).

**Siguiente:** [Paso 5](#paso-5)

<a id="paso-5"></a>
### Paso 5 de 14 · Abre tu Code Editor

**Para qué:** abrir tu **Code Editor** (editor de código en el navegador, tipo VS Code) desde **SageMaker Studio** (interfaz web de AWS desde la que lo abres).

> [!TIP]
> Atajo: el output `StudioConsoleUrl` del stack (**CloudFormation > `bigdata-bootstrap` > Outputs**) abre directo la página del perfil `estudiante`. Con el atajo, sigue desde el punto 4 de [5.1](#paso-5-1).

<a id="paso-5-1"></a>
#### 5.1 · Entra al perfil estudiante

☁️ **Consola AWS**

1. Abre **Amazon SageMaker AI > Domains**.
2. Abre tu dominio.
3. Abre la pestaña **User profiles** y entra al perfil `estudiante`.
4. Pulsa **Launch > Studio**.

> [!NOTE]
> Un **dominio** de SageMaker agrupa los perfiles de usuario de tu cuenta.

<a id="paso-5-2"></a>
#### 5.2 · Abre el Code Editor

☁️ **Consola AWS** (pestaña **Studio**)

1. Entra a **Code Editor**.
2. Abre el **Space** `dev` (espacio de trabajo de Studio que se enciende y apaga).
3. Pulsa **Run space**. La primera vez tarda 3-5 min.
4. Pulsa **Open**.

<a id="paso-5-3"></a>
#### 5.3 · Abre una terminal

💻 **Terminal del Code Editor**

1. Abre el menú **Terminal > New Terminal**.

**✅ Debes ver:** una terminal abierta en el Code Editor.

Para apagar y encender el entorno día a día: [Cada sesión](cada-sesion.md).

**Siguiente:** [Paso 6](#paso-6)

<a id="paso-6"></a>
### Paso 6 de 14 · Clona tu fork

💻 **Terminal del Code Editor**

1. Ejecuta (reemplaza `<TU_USUARIO>` por tu usuario de GitHub y `<TU_FORK>` por el nombre de tu fork; esta es la única vez que reemplazas esos valores):
   ```bash
   cd ~
   git clone https://github.com/<TU_USUARIO>/<TU_FORK>.git ~/bigdata
   cd ~/bigdata
   ```

> [!NOTE]
> **Clonar** es copiar un repositorio de GitHub a tu Code Editor. **make** es el comando que ejecuta tareas predefinidas del proyecto.
>
> Ejemplo: `git clone https://github.com/jperez/bigdata-udem-2026.git ~/bigdata`. Todos los comandos `make` de aquí en adelante se ejecutan **dentro de `~/bigdata`**.

**✅ Debes ver:** el **prompt** (el texto que aparece antes del cursor) termina en `~/bigdata$`.

**Siguiente:** [Paso 7](#paso-7)

<a id="paso-7"></a>
### Paso 7 de 14 · Conecta Snowflake

**Para qué:** crear la conexión que usan los demás comandos para entrar a tu cuenta de Snowflake, con una llave en lugar de contraseña.

**Ventanas:** vas a ir y volver entre ❄️ **Snowsight** (interfaz web de Snowflake para escribir SQL, el lenguaje de consultas) y 💻 **Terminal del Code Editor**. Ten las dos abiertas.

<a id="paso-7-1"></a>
#### 7.1 · Averigua tus datos

❄️ **Snowsight**

1. Abre una hoja con **+ > SQL Worksheet** (el botón **+** está arriba a la izquierda).
2. Pega este bloque (**ACCOUNTADMIN** es el rol de administrador de tu cuenta de prueba):
   ```sql
   USE ROLE ACCOUNTADMIN;
   SHOW USERS;
   SELECT CURRENT_ORGANIZATION_NAME() || '-' || CURRENT_ACCOUNT_NAME() AS account_identifier,
          "name" AS usuario, "login_name" AS login
   FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "name" = CURRENT_USER();
   ```
3. Pulsa **Run All** (la flecha junto a ▶).
4. Apunta los tres valores de la fila de tu usuario: `ACCOUNT_IDENTIFIER`, `USUARIO` y `LOGIN`.

> [!NOTE]
> `USUARIO` y `LOGIN` pueden ser distintos (por ejemplo, el login es tu correo): el script pide los dos. **Account identifier** es el código que identifica tu cuenta de Snowflake, con formato `ORGNAME-ACCOUNTNAME`.

**✅ Debes ver:** una tabla como esta (tus valores serán otros):
```text
ACCOUNT_IDENTIFIER | USUARIO | LOGIN
ABCDEFG-XY12345    | jperez  | JPEREZ@GMAIL.COM
```

<a id="paso-7-2"></a>
#### 7.2 · Ejecuta el script

💻 **Terminal del Code Editor**

1. Ejecuta el script:
   ```bash
   cd ~/bigdata
   make snowflake-conexion
   ```
2. Escribe los tres valores de 7.1 (Account identifier, USUARIO y LOGIN) cuando te los pida. Los de abajo son de ejemplo:
   ```text
   Account identifier (ORGNAME-ACCOUNTNAME): ABCDEFG-XY12345
   USUARIO (columna USUARIO): jperez
   LOGIN (columna LOGIN): JPEREZ@GMAIL.COM
   ```

> [!NOTE]
> Tienes un par de **llaves**: la **llave pública** va a Snowflake con el `ALTER USER`; la **llave privada** queda en `~/.snowflake/keys/<USUARIO>_key.p8` y no sale de tu Code Editor. No compartas ni subas la llave privada.

**❌ Si falla:** [`make: *** No rule to make target 'snowflake-conexion'`](problemas.md#p-make-no-rule)

<a id="paso-7-3"></a>
#### 7.3 · Copia las dos líneas

💻 **Terminal del Code Editor**

> [!IMPORTANT]
> La terminal se queda esperando. No pulses Enter hasta ver `Statement executed successfully.` en Snowsight (7.4).

1. Selecciona y copia las dos líneas SQL que imprime el script (`USE ROLE` y `ALTER USER`).

> [!NOTE]
> En la terminal del Code Editor funcionan **Ctrl+C** / **Ctrl+V** (**Cmd** en Mac). También puedes hacer clic derecho > **Paste**.

**✅ Debes ver:** algo así (la clave es mucho más larga):
```text
Último paso: en Snowsight, en una hoja (+ > SQL Worksheet), pega estas dos líneas juntas y
ejecútalas con 'Run All' (flecha junto a ▶):

USE ROLE ACCOUNTADMIN;
ALTER USER "jperez" SET RSA_PUBLIC_KEY='MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA...';

Cuando la hayas ejecutado, pulsa Enter para probar la conexión...
```

<a id="paso-7-4"></a>
#### 7.4 · Ejecútalas en Snowsight

❄️ **Snowsight**

1. Vuelve a la hoja de 7.1.
2. Borra lo que había.
3. Pega las dos líneas.
4. Pulsa **Run All** (la flecha junto a ▶).

**✅ Debes ver:** `Statement executed successfully.`

**❌ Si falla:** [`User '...' does not exist`](problemas.md#p-user-no-existe) · [`Insufficient privileges`](problemas.md#p-insufficient-privileges)

<a id="paso-7-5"></a>
#### 7.5 · Prueba la conexión

💻 **Terminal del Code Editor**

1. Pulsa Enter en la terminal. El script prueba la conexión.

**✅ Debes ver:** `Conexión configurada. Siguiente paso: make setup`

**❌ Si falla:** [`JWT token is invalid`](problemas.md#p-jwt-conexion)

<a id="paso-7-6"></a>
#### 7.6 · (Opcional) Comprueba la conexión

💻 **Terminal del Code Editor**

1. Comprueba cuando quieras:
   ```bash
   cd ~/bigdata
   snow connection test
   ```

> [!NOTE]
> En la salida de abajo, `Database` y `Warehouse` dicen `not set`: es normal en este punto, porque se crean en el [Paso 11](#paso-11). Un **warehouse** es el motor de cálculo de Snowflake; se cobra mientras trabaja.

**✅ Debes ver:** (con tus valores) `Status` debe ser `OK` y `User` tu LOGIN:
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

**❌ Si falla:** [`Could not use warehouse "BIGDATA_WH"`](problemas.md#p-warehouse-bigdata-wh)

**Siguiente:** [Paso 8](#paso-8)

<a id="paso-8"></a>
### Paso 8 de 14 · Ejecuta `make setup`

💻 **Terminal del Code Editor**

**Tiempo:** unos 21 s medidos en una cuenta ya configurada (con el correo y la configuración nuevas, la primera vez puede tardar más).

1. Ejecuta `make setup`:
   ```bash
   cd ~/bigdata
   make setup
   ```
2. Escribe tu correo cuando te pida el de las alertas de presupuesto.

> [!NOTE]
> **Terraform** es la herramienta que crea recursos en la nube desde archivos de configuración. La configuración se guarda en un **bucket**: la carpeta de nivel superior de S3, el servicio de AWS para guardar archivos. Qué hace `make setup`: [detalle](referencia.md#make-setup).

En la salida puede aparecer una línea `AVISO` sobre `gh`: es normal la primera vez y se resuelve en el [Paso 9](#paso-9). Si `gh` ya está autenticado en tu Code Editor, no hay `AVISO`: `make setup` carga los secrets del fork en este mismo paso.

**✅ Debes ver:** una salida como esta (la primera vez; tu cuenta y tu correo serán otros):
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

Si `gh` ya estaba autenticado, la salida cambia al final: en lugar del `AVISO`, `make setup` ejecuta `make secrets` y muestra esto antes de `Setup completado` (el número depende de cuántos secrets de Actions tenga tu fork; ver la nota del [Paso 9](#paso-9-3)):
```text
==> Cargando secrets en <TU_USUARIO>/<TU_FORK>
✓ Set Actions secret AWS_ROLE_ARN for <TU_USUARIO>/<TU_FORK>
✓ Set Actions secret TF_STATE_BUCKET for <TU_USUARIO>/<TU_FORK>
==> Secrets listos: AWS_ROLE_ARN y TF_STATE_BUCKET (3 en total).
==> Setup completado. Siguiente paso: make doctor
```

**❌ Si falla:** [`make setup` dice que Snowflake no está en AWS](problemas.md#p-sin-region-aws) (si la región no es `AWS_US_EAST_2`, vuelve al [Paso 1](#paso-1)) · [`make setup` dice que no hay conexión de `snow`](problemas.md#p-snow-sin-conexion) <!-- AUTOR: qué de los pasos 7 y 8 se rehace si la cuenta de Snowflake cambia -->

**Siguiente:** [Paso 9](#paso-9)

<a id="paso-9"></a>
### Paso 9 de 14 · Autentica GitHub, carga los secrets y comprueba el entorno

**Para qué:** cargar en tu fork los **secrets** (valores cifrados que los workflows usan) y comprobar el entorno con `make doctor`. `make setup` ya carga `AWS_ROLE_ARN` y `TF_STATE_BUCKET`.

**Orden:** `make setup` > `gh auth login` > `make secrets` > `make doctor`.

<a id="paso-9-1"></a>
#### 9.1 · Inicia sesión en GitHub

💻 **Terminal del Code Editor**

1. **Solo si** `make setup` mostró el AVISO de `gh`, ejecuta el bloque (`gh` es la herramienta de GitHub para la terminal):
   ```bash
   cd ~/bigdata
   gh auth login --hostname github.com --git-protocol https --web
   make secrets
   ```
2. Responde `Yes` a la pregunta *Authenticate Git with your GitHub credentials?* y pulsa Enter.
3. Copia a mano el código de un solo uso que aparece (selecciónalo y cópialo tú: la copia automática falla en el Code Editor).
4. Pulsa Enter. El navegador no se abre solo: sigue en 9.2.

Así se ve `gh auth login` (tu código será otro; los comentarios `<-` explican cada línea): <!-- AUTOR: el bloque muestra solo algunas preguntas de `gh auth login`; confirmar si hay más y cuándo caduca el código -->
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

<a id="paso-9-2"></a>
#### 9.2 · Autoriza en GitHub

🧭 **Navegador** (`github.com/login/device`)

1. Abre `https://github.com/login/device` en otra pestaña.
2. Pega el código de un solo uso.
3. Pulsa **Authorize**.

<a id="paso-9-3"></a>
#### 9.3 · Verifica el resultado

💻 **Terminal del Code Editor**

1. Si hiciste 9.1 y 9.2, vuelve a la terminal y espera `✓ Logged in as <TU_USUARIO>`. Después, `make secrets` carga los secrets.
2. Ejecuta `make doctor`:
   ```bash
   cd ~/bigdata
   make doctor
   ```

> [!NOTE]
> Las líneas `[INFO]` son informativas. Lo importante es la última línea. El número entre paréntesis de `Secrets listos` es el total de secrets de Actions que tiene tu fork (`gh secret list`), no solo los dos que carga el script: con otros secrets previos verás 3 o más.

**✅ Debes ver:** la salida de `make secrets` (si lo ejecutaste) y de `make doctor`; la última línea es `==> Diagnóstico sin fallos` (versiones, cuenta y usuario serán los tuyos):
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
[INFO]   Verifica también el secret AWS_ROLE_ARN del fork (Settings -> Secrets and variables -> Actions).
[INFO]   Si OIDC falla en CI, ejecuta el workflow 'Debug OIDC' para ver el claim sub real.

==> Diagnóstico sin fallos
```

**❌ Si falla:** una línea `[FALLO]` dice qué revisar. Si `ci.yml` o `deploy.yml` fallan pidiendo `AWS_ROLE_ARN` o `TF_STATE_BUCKET`, ve a [esta fila](problemas.md#p-ci-secrets).

**Siguiente:** [Paso 10](#paso-10)

<a id="parte-3"></a>
## Parte 3 · Infraestructura y datos

<a id="paso-10"></a>
### Paso 10 de 14 · Despliega AWS y sube el código del pipeline

💻 **Terminal del Code Editor** <!-- AUTOR: validar tiempo del paso 10; el original no lo indica -->

1. Ejecuta:
   ```bash
   cd ~/bigdata
   make deploy
   ```

> [!NOTE]
> Qué hace `make deploy`: [detalle](referencia.md#make-deploy).
> - También se ejecuta solo en cada **push** (subir cambios a GitHub) a **main** (la rama principal, la versión oficial del código).
> - La **VM** de prod (máquina virtual de AWS) solo existe si Airflow está habilitado: `make airflow-habilitar` cambia `enable_airflow` y despliega. El Airflow de dev corre en el Code Editor y no lo necesita.

**✅ Debes ver:** el final de esta salida (la cuenta será la tuya). La primera vez, Terraform crea 23 recursos. Las líneas `...` marcan salida que no se muestra aquí.
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

**❌ Si falla:** [`El plan destruye recursos`](problemas.md#p-plan-destruye) (avanzado) · [`make deploy` se queda colgado](problemas.md#p-deploy-colgado) (avanzado)

**(Opcional)** Para tener la **VM** de prod, ejecuta `make airflow-habilitar`. Ver [Paso 14](#paso-14).

**Siguiente:** [Paso 11](#paso-11)

<a id="paso-11"></a>
### Paso 11 de 14 · Crea los recursos de Snowflake

💻 **Terminal del Code Editor** <!-- AUTOR: validar tiempo del paso 11; el original no lo indica -->

1. Ejecuta:
   ```bash
   cd ~/bigdata
   make snowflake
   ```

> [!NOTE]
> Usa tu conexión de `snow` ([Paso 7](#paso-7)) y los outputs del [Paso 10](#paso-10), así que no hay que copiar valores ni editar archivos. Qué hace, en orden: [detalle](referencia.md#make-snowflake).

> [!IMPORTANT]
> El script te pide confirmar el **plan** (la lista de cambios que Terraform va a hacer, antes de hacerlos). Cuando veas `Enter a value:`, escribe `yes`.

**✅ Debes ver:** estas líneas, en este orden (la salida es larga y la mayoría es Terraform). Si la última línea aparece, el paso terminó bien:
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

> [!NOTE]
> El plan de la fase 2 no debe eliminar recursos (`0 to destroy`). Si lo hiciera, el script se detiene solo.
>
> **Conexión de Airflow a Snowflake: no hay nada que hacer a mano.** `make snowflake` la crea y la guarda en el secreto `bigdata/snowflake`, que usan el Airflow de dev y el de prod ([detalle](referencia.md#make-snowflake)).

- **Solo si** Airflow de dev ya estaba encendido, reinícialo: `make airflow-local-down && make airflow-local`.
- **Solo si** Airflow de prod ya estaba encendido, reinícialo: `make airflow-off && make airflow-on`.
- **(Opcional)** Para repetir solo la conexión de Airflow: `make snowflake-secreto`.

**Referencia (no necesaria para empezar):** [infra/snowflake/README.md](../infra/snowflake/README.md)

**❌ Si falla:** [`JWT token is invalid`](problemas.md#p-jwt-llave) · [`El plan destruye recursos`](problemas.md#p-plan-destruye) (avanzado) · [`Error acquiring the state lock`](problemas.md#p-state-lock) (avanzado)

**Siguiente:** [Paso 12](#paso-12)

<a id="paso-12"></a>
### Paso 12 de 14 · Prepara los datos (una vez)

**Para qué:** bajar los datos del año y generar la muestra con la que trabajarás en local.

**Tiempo:** ~5 min · **Costo:** ~US$0.15

> [!IMPORTANT]
> La terminal se queda quieta varios minutos entre líneas mientras Glue trabaja. Es normal: no la cierres.

💻 **Terminal del Code Editor**

1. Ejecuta:
   ```bash
   cd ~/bigdata
   make muestra
   ```

> [!NOTE]
> **FHVHV** son los viajes de Uber/Lyft de NYC publicados por la NYC TLC. **Bronze** son los datos crudos tal como llegan. La **muestra** es un subconjunto pequeño de los datos para trabajar en local. Qué hace `make muestra`: [detalle](referencia.md#make-muestra).

**✅ Debes ver:** estas líneas (los ids de **run**, una ejecución de Glue, serán otros):
```text
==> Glue bigdata-small --step bronze (run jr_...)
==> bronze OK
==> Glue bigdata-medium --step muestra (run jr_...)
==> muestra OK
==> Muestra lista en s3://bigdata-lake-123456789012-us-east-2/muestra. En local: make run-local (la descarga la primera vez).
```

**❌ Si falla:** [`TIMEOUT`](problemas.md#p-timeout-muestra) (repite `make muestra`; retoma desde lo que ya descargó) · [`ModuleNotFoundError: pipeline`](problemas.md#p-modulenotfound) · [`AccessDenied` al lanzar jobs Glue](problemas.md#p-accessdenied-presupuesto)

**Siguiente:** [Paso 13](#paso-13)

<a id="parte-4"></a>
## Parte 4 · Desarrollar y publicar

<a id="paso-13"></a>
### Paso 13 de 14 · Desarrolla en local y dev

**Para qué:** correr el pipeline sobre la muestra (gratis) y luego en la nube, con el Airflow de dev.

**Tiempo:** `make run-local LIMITE=100` ~30 s · un run con `glue_small` 10-15 min.

**Costo:** `glue_small` cuesta centavos.

**Antes:** haber terminado el [Paso 12](#paso-12) (la muestra ya está en S3).

**Ventanas:** 💻 **Terminal del Code Editor** · 🧭 **Navegador** (UI de Airflow) · ❄️ **Snowsight** (solo en 13.2)

<a id="paso-13-1"></a>
#### 13.1 · Corre el pipeline en local

Son dos comandos distintos: `make run-local` termina solo; `make airflow-local` queda corriendo y deja libre la terminal.

<a id="paso-13-1-local"></a>
##### A · `make run-local` (termina solo)

💻 **Terminal del Code Editor**

1. Corre la prueba rápida con `LIMITE=100`:
   ```bash
   cd ~/bigdata
   make run-local LIMITE=100
   ```

> [!NOTE]
> Los avisos `WARN` de **Spark** (motor que procesa los datos en tu Code Editor) son normales.

**✅ Debes ver:** el final de `make run-local LIMITE=100` (tarda ~30 s):
```text
INFO Muestra descargada de s3://.../muestra a /home/sagemaker-user/bigdata/lake/muestra (25 archivos)   <- solo la primera vez
INFO Paso=silver env=local engine=local meses=2024-01
INFO Calidad OK [silver]: 100 filas
INFO Paso=gold env=local engine=local meses=2024-01
INFO Calidad OK [gold]: 79 filas
```

**❌ Si falla:** [`No hay muestra ... falta LAKE_BUCKET`](problemas.md#p-sin-muestra) · [`make test` o `make run-local` fallan por Java](problemas.md#p-java)

<a id="paso-13-1-airflow"></a>
##### B · `make airflow-local` (queda corriendo; la terminal sigue libre)

💻 **Terminal del Code Editor**

1. Enciende el Airflow de dev:
   ```bash
   cd ~/bigdata
   make airflow-local    # Airflow de dev
   ```

Tarda ~1 min; la instalación solo ocurre la primera vez y tarda unos minutos.

**✅ Debes ver:** al final, la URL de tu Airflow (`UI: https://...studio.us-east-2.sagemaker.aws/codeeditor/default/ports/8080/`, lista para abrir) y la contraseña.

**❌ Si falla:** en vez de la URL ves `<id-del-space>`. Reemplaza `<id-del-space>` por el subdominio de la URL del Code Editor que tienes abierta en el navegador ([detalle](problemas.md#p-id-del-space)).

🧭 **Navegador** (UI de Airflow)

2. Abre la URL de `make airflow-local` en una pestaña nueva.
3. Entra con usuario `admin` y la contraseña que imprimió `make airflow-local`.
4. Abre **Dags**.
5. Activa el interruptor de `pipeline_taxi`. Los DAGs nuevos aparecen **pausados** (la página Home dice `Active Dags 0`).
6. Entra al **DAG** (lista de tareas de Airflow con orden fijo) `pipeline_taxi`.
7. Pulsa **Trigger** (▶). Se abre el formulario de parámetros (`computo`, `mes`, `limite`).
8. Elige `computo = spark_local` (tabla de abajo).
9. Deja `mes` y `limite` vacíos. <!-- AUTOR: confirmar `mes` y `limite` en la prueba local -->
10. Pulsa el segundo botón **Trigger** para lanzar el run.

> [!NOTE]
> El Airflow del Code Editor es siempre el entorno **dev** (no se elige al lanzar). Lo que eliges es el parámetro `computo`, que decide con qué recursos se calcula:

| Parámetro | Qué decide | Valores |
|---|---|---|
| `computo` | Con qué recursos se calcula. | `spark_local`: Spark en el Code Editor sobre la muestra (gratis). Como mucho 10 000 filas por fuente. El resultado queda en `./lake` (la carpeta `lake` dentro de `~/bigdata`) y no se carga en Snowflake. · `glue_small`, `glue_medium` o `glue_large`: **workers** (trabajadores de cómputo de Glue): 2, 4 o 6. Escribe en `s3://<LAKE>/dev/` (`<LAKE>` es el bucket `bigdata-lake-<CUENTA>-us-east-2` que el [Paso 10](#paso-10) imprime como `lake_bucket`) y carga en `BIGDATA.DEV`. |
| `mes` | Qué mes procesar. | Vacío = todos los meses del entorno (en dev, solo `2024-01`), o un mes concreto en formato `YYYY-MM`. |
| `limite` (opcional) | Máximo de viajes a procesar. | Vacío = sin recorte. |

**✅ Debes ver:** el run en el DAG. Con `spark_local` ocurre lo contrario que con `glue_small` (13.2): las tareas de la rama de Glue quedan en `skipped` y `cargar_gold` no carga datos en Snowflake.

**❌ Si falla:** [la UI sale en blanco o "Unsupported URL path"](problemas.md#p-airflow-ui-blanco) · ["Invalid or Expired Auth Token"](problemas.md#p-auth-token)

<a id="paso-13-2"></a>
#### 13.2 · Corre el pipeline en dev con `glue_small`

🧭 **Navegador** (UI de Airflow)

1. Vuelve a la pestaña de Airflow y entra al DAG `pipeline_taxi`.
2. Pulsa **Trigger** (▶). Se abre el formulario de parámetros (`computo`, `mes`, `limite`).
3. Elige `computo = glue_small` (con `spark_local` no se modifica la tabla que verificas al final de este paso).
4. Deja `mes` y `limite` vacíos (qué significa cada uno: [tabla de 13.1](#paso-13-1)).
5. Pulsa el segundo botón **Trigger** para lanzar el run.

**✅ Debes ver:** en un run exitoso con `glue_small` (10-15 min): `preparar_entorno`, `elegir_computo`, `bronze`, `silver`, `gold` y `cargar_gold` en verde (`success`); `silver_spark_local` y `gold_spark_local` en rosa (`skipped`), porque son la rama de `spark_local`.

**❌ Si falla:** [el DAG falla en `cargar_gold`](problemas.md#p-cargar-gold)

❄️ **Snowsight**

1. Abre una hoja con **+ > SQL Worksheet**.
2. Pega este bloque (usa el rol `BIGDATA_DEV` y el warehouse `BIGDATA_WH`):
   ```sql
   USE ROLE BIGDATA_DEV;
   USE WAREHOUSE BIGDATA_WH;
   SELECT COUNT(*), MIN(fecha), MAX(fecha) FROM BIGDATA.DEV.DAILY_ZONE_METRICS;
   ```
3. Pulsa **Run All** (la flecha junto a ▶).

**✅ Debes ver:** con `glue_small` (todo enero de 2024):
```text
COUNT(*) | MIN(FECHA) | MAX(FECHA)
15909    | 2024-01-01 | 2024-01-31
```

> [!NOTE]
> La tabla la crea el propio DAG en `cargar_gold` la primera vez.

**Siguiente:** [Paso 14](#paso-14)

<a id="paso-14"></a>
### Paso 14 de 14 · Pasa a prod con un PR

**Para qué:** publicar tu cambio en `main` con un PR y lanzar el pipeline en el Airflow de prod.

**Tiempo:** el run de prod con `glue_medium` y `mes=2024-01` tarda ~5 min. <!-- AUTOR: tiempo de los pasos del PR y del Deploy -->

**Antes:** haber terminado el [Paso 13](#paso-13).

**Ventanas:** 💻 **Terminal del Code Editor** · 🌐 **GitHub** (PR y **Actions**) · 🧭 **Navegador** (UI de Airflow de prod).

<a id="paso-14-1"></a>
#### 14.1 · Habilita la VM de prod (solo la primera vez)

💻 **Terminal del Code Editor**

La primera vez, crea la VM de Airflow de prod: no existe hasta que la habilitas.

1. Ejecuta:
   ```bash
   cd ~/bigdata
   make airflow-habilitar
   ```

<!-- AUTOR: ✅ de `make airflow-habilitar`: la fuente no muestra su salida -->

<a id="paso-14-2"></a>
#### 14.2 · Prepara un cambio en tu rama

💻 **Terminal del Code Editor**

1. Crea una rama nueva a partir de `main` actualizado: <!-- AUTOR: validar en V10 -->
   ```bash
   cd ~/bigdata
   git switch main
   git pull
   git switch -c mi-primer-cambio
   ```
2. Haz un cambio pequeño dentro de `airflow/` o `src/`, para que el Deploy encienda la VM de prod. Por ejemplo, añade un comentario en `airflow/dags/pipeline_taxi.py`. <!-- AUTOR: validar en V10: ¿cómo se edita el archivo en el Code Editor? -->
3. Guarda el archivo. <!-- AUTOR: validar en V10 -->
4. Sube el cambio: <!-- AUTOR: validar en V10 -->
   ```bash
   git add -A
   git commit -m "Mi primer cambio"
   git push -u origin mi-primer-cambio
   ```
   <!-- AUTOR: validar en V10: ¿hace falta configurar tu usuario de git (`user.name`, `user.email`) en el Code Editor? -->

<!-- AUTOR: validar en V10: ✅ de `git push`; la fuente no muestra la salida -->

<a id="paso-14-3"></a>
#### 14.3 · Abre el PR, mézclalo y espera el Deploy

🌐 **GitHub**

Abres un **pull request (PR)**: una solicitud para revisar tus cambios antes de incorporarlos a `main`. Al hacer **merge**, los cambios entran a `main`. <!-- AUTOR: validar en V10 -->

1. Pulsa **Compare & pull request** en la página de tu repositorio. <!-- AUTOR: validar en V10 -->
2. Pulsa **Create pull request**. Comprueba que el destino sea tu repositorio. <!-- AUTOR: validar en V10: en un fork, GitHub puede proponer el repositorio original como destino -->
3. Espera a que terminen las verificaciones automáticas (**checks**). <!-- AUTOR: validar en V10 -->
4. Pulsa **Merge pull request** y después **Confirm merge**. <!-- AUTOR: validar en V10 -->
5. Abre la pestaña **Actions** y espera a que el workflow **Deploy** termine en verde. <!-- AUTOR: validar en V10 -->

> [!NOTE]
> El workflow **Deploy** publica código y DAGs, y enciende la VM de prod si cambiaron `airflow/` o `src/`. <!-- AUTOR: ¿esperar ~2 min tras el Deploy antes del túnel? En Encender la fuente dice ~2 min tras `make airflow-on` -->

**✅ Debes ver:** el workflow **Deploy** en verde. <!-- AUTOR: validar en V10 -->

<!-- AUTOR: ❌ de 14.3: qué hacer si los checks o el Deploy fallan; no hay fila en problemas.md -->

<a id="paso-14-4"></a>
#### 14.4 · Apaga el Airflow de dev y abre el túnel

💻 **Terminal del Code Editor**

> [!IMPORTANT]
> El túnel ocupa esta terminal y debe quedar abierta mientras uses el Airflow de prod. Para seguir trabajando, abre otra terminal con **Terminal > New Terminal**.

> [!NOTE]
> El Airflow de dev y el de prod usan el mismo puerto 8080; por eso primero apagas el de dev.

1. Apaga el Airflow de dev y abre el túnel. Deja esa terminal abierta:
   ```bash
   cd ~/bigdata
   make airflow-local-down
   make airflow-tunel
   ```

**✅ Debes ver:** la URL que imprime `make airflow-tunel`, la misma que en dev. <!-- AUTOR: validar en V10: la fuente no muestra la salida de `make airflow-tunel` -->

**❌ Si falla:** [`El puerto 8080 está ocupado (¿Airflow de dev encendido?)`](problemas.md#p-puerto-8080) · [`La instancia está 'stopped'. Ejecuta 'make airflow-on' primero.`](problemas.md#p-vm-stopped) · [`No existe la instancia bigdata-airflow`](problemas.md#p-vm-inexistente) · [`make airflow-tunel` no abre el túnel](problemas.md#p-tunel)

<a id="paso-14-5"></a>
#### 14.5 · Lanza el DAG en prod

🧭 **Navegador** (UI de Airflow de prod)

1. Abre la URL que imprime `make airflow-tunel` (la misma que en dev) en una pestaña nueva.

💻 **Terminal del Code Editor** (otra terminal, porque el túnel ocupa la primera)

2. Abre otra terminal con **Terminal > New Terminal**.
3. Ejecuta:
   ```bash
   cd ~/bigdata
   make airflow-password
   ```
   Imprime el usuario y la contraseña:
   ```text
   Usuario:    admin
   Contraseña: <...>
   ```

🧭 **Navegador** (UI de Airflow de prod)

4. Entra a Airflow con ese usuario y esa contraseña.
5. Abre **Dags**.
6. Entra al **DAG** `pipeline_taxi`.
7. Pulsa **Trigger** (▶). <!-- AUTOR: ¿el DAG de prod aparece pausado, como en 13.1? confirmar -->
8. Se abre el formulario de parámetros (`computo`, `mes`, `limite`): elige `computo = glue_medium` (o `glue_large`) y, por ejemplo, `mes = 2024-01`.
9. Pulsa el segundo botón **Trigger** para lanzar el run.

> [!NOTE]
> En prod el entorno es fijo (`prod`, en la VM), solo hay `computo = glue_medium` o `glue_large`, y no hay límite de filas. El DAG no tiene rama local.
>
> La conexión de Snowflake ya está en el secreto `bigdata/snowflake`, escrito por `make snowflake` (ver [airflow/README.md](../airflow/README.md)).

**✅ Debes ver:** en un run exitoso solo seis tareas, todas en `success`: `preparar_entorno`, `elegir_computo`, `bronze`, `silver`, `gold` y `cargar_gold`. Con `glue_medium` y `mes=2024-01` tarda ~5 min y `BIGDATA.PROD` queda con 15909 filas.

**❌ Si falla:** [el DAG falla en `cargar_gold`](problemas.md#p-cargar-gold) · ["Invalid or Expired Auth Token"](problemas.md#p-auth-token) · [la UI sale en blanco](problemas.md#p-airflow-ui-blanco)

**Siguiente:** [Listo](#listo)

<a id="listo"></a>
## Listo

Terminaste el recorrido. **Siguiente:** [Cada sesión](cada-sesion.md), para apagar y encender el día a día.

<a id="glosario"></a>
## Glosario

Cada término se explica en línea donde aparece por primera vez; esta tabla los reúne y te dice dónde.

| Término | Qué es | Se define en |
|---|---|---|
| **terminal** | Ventana donde escribes comandos de texto y ves su respuesta. | [Antes de empezar](#antes-de-empezar) |
| **consola de AWS** | Página web de Amazon donde creas y administras tus recursos en la nube. | [Antes de empezar](#antes-de-empezar) |
| **región** | Ubicación geográfica de los servidores de la nube; todo el curso usa `us-east-2` (Ohio). | [Paso 1](#paso-1) |
| **cuota** | Límite de recursos que AWS permite en tu cuenta; en cuentas nuevas a veces viene en 0. | [Paso 2](#paso-2) |
| **repositorio** | Carpeta de código con su historial de cambios, guardada en GitHub. | [Paso 3](#paso-3) |
| **fork** | Copia personal, en tu cuenta de GitHub, de un repositorio ajeno. | [Paso 3](#paso-3) |
| **GitHub Actions (workflow)** | Sistema de GitHub que ejecuta tareas automáticas; cada tarea es un *workflow*. | [Paso 3](#paso-3) |
| **CloudFormation (stack)** | Servicio de AWS que crea recursos desde una plantilla; el *stack* es el conjunto creado. | [Paso 4](#paso-4) |
| **bootstrap** | Primer paso de configuración que crea de una vez los recursos base de tu cuenta AWS. | [Paso 2.1](#paso-2-1) y [Paso 4](#paso-4) |
| **SageMaker Studio** | Interfaz web de AWS desde la que abres tu Code Editor. | [Paso 5](#paso-5) |
| **Code Editor** | Editor de código en el navegador (tipo VS Code) donde corre todo tu trabajo del curso. | [Antes de empezar](#antes-de-empezar) y [Paso 5](#paso-5) |
| **Space** | Espacio de trabajo dentro de Studio que se enciende y apaga; el tuyo se llama `dev`. | [Paso 5.2](#paso-5-2) |
| **clonar** | Copiar un repositorio de GitHub a tu Code Editor. | [Paso 6](#paso-6) |
| **prompt** | Texto que aparece en la terminal antes del cursor; aquí debe terminar en `~/bigdata$`. | [Paso 6](#paso-6) |
| **make** | Comando de terminal que ejecuta tareas predefinidas del proyecto (`make setup`, `make deploy`…). | [Paso 6](#paso-6) |
| **Snowsight** | Interfaz web de Snowflake donde escribes y ejecutas SQL en *hojas* (SQL Worksheet). | [Paso 7](#paso-7) |
| **account identifier** | Código que identifica tu cuenta de Snowflake, con formato `ORG-CUENTA`. | [Paso 7.1](#paso-7-1) |
| **llave pública / privada** | Par de llaves: la pública se registra en Snowflake, la privada nunca sale de tu Code Editor. | [Paso 7.2](#paso-7-2) |
| **warehouse** | Motor de cálculo de Snowflake que se enciende para consultar y cobra solo mientras trabaja. | [Paso 7.6](#paso-7-6) |
| **Terraform** | Herramienta que crea recursos en la nube a partir de archivos de configuración. | [Paso 8](#paso-8) |
| **bucket** | Carpeta de nivel superior en S3, el servicio de AWS para guardar archivos. | [Paso 2.3](#paso-2-3) y [Paso 8](#paso-8) |
| **secret** | Valor guardado de forma cifrada en tu fork para que los workflows lo usen. | [Paso 9](#paso-9) |
| **main** | Rama principal del repositorio: la versión oficial del código. | [Paso 10](#paso-10) |
| **Airflow** | Programa que lanza los pasos del pipeline en orden; en el curso corre en dev y en prod. | [Antes de empezar](#antes-de-empezar) |
| **Glue** | Servicio de AWS que ejecuta trabajos de datos (jobs) y cobra por segundo de uso. | [Antes de empezar](#antes-de-empezar) |
| **DAG** | Lista de tareas de Airflow con orden fijo; el nuestro se llama `pipeline_taxi`. | [Paso 13.1](#paso-13-1) |
| **pull request (PR)** | Solicitud para revisar tus cambios antes de incorporarlos a `main`. | [Paso 14.3](#paso-14-3) |
| **merge** | Incorporar los cambios de una rama o PR a `main`. | [Paso 14.3](#paso-14-3) |
| **entorno (local, dev, prod)** | Dónde corre el código: tu Code Editor (local), pruebas en AWS (dev) o producción (prod). | [README](../README.md#que-vas-a-construir) |
| **pipeline** | Serie de pasos que toma datos crudos, los limpia y los deja listos para analizar. | [README](../README.md#que-vas-a-construir) |
