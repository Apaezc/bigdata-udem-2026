# Clase 7 · Un pipeline completo de punta a punta, en dev, y cómo dejarlo listo para prod

Big Data e Ingeniería de Datos (UdeM) · lunes 23 de noviembre de 2026

**La pregunta de la clase:** ¿cómo construyo y pruebo en dev un pipeline de datos, sin duplicar nada y sabiendo cuánto cómputo necesito, para llevarlo a producción en la clase 8?

Esta carpeta tiene todo lo que usas hoy. Este archivo explica dos cosas: **qué hay** y **cómo dejar tu cuenta lista antes de la clase** (el lake cambió de forma y tu cuenta todavía tiene la forma de las clases 1 a 6). Hazlo en orden y no te saltes la sección «Antes de seguir».

- [Qué hay en esta carpeta](#que-hay)
- [Antes de la clase: deja tu cuenta lista](#migrar)
  - [Paso 1 · Que no tengas cambios sin guardar](#paso-1)
  - [Paso 2 · Traer el código nuevo a tu fork](#paso-2)
  - [Paso 3 · Migrar tu cuenta con make](#paso-3)
  - [Antes de seguir](#antes-de-seguir)
  - [Errores comunes](#errores)
- [Antes y ahora](#antes-ahora)
- [Dónde se cambia cada cosa](#donde)
- [Cómo se abren los notebooks](#notebooks)
- [Lo que no vale después de migrar](#no-vale)
- [Cómo es la clase](#clase)

<a id="que-hay"></a>
## Qué hay en esta carpeta

| Archivo | Para qué sirve |
|---|---|
| `01_construir_paso_a_paso.ipynb` | El notebook de la clase y **tu banco de trabajo** (también en el Taller 2). El instructor construye la lógica de cada función con 1 000 viajes: la puerta de la tabla de control, bronze, silver, gold y la tabla de Snowflake. Tú lo sigues celda por celda; al final compara cada función con la del `.py` (`igual` o `DISTINTO`) y corre las pruebas del equipo. |
| `athena/01_tablas.sql` | Declara en Athena las siete tablas del lake de un entorno (`dev_...` o `prod_...`): bronze por lotes, silver y gold. |
| `athena/02_duplicados_y_conciliacion.sql` | Las consultas de cada punto de control (después de bronze, silver y gold, y después de reprocesar) para ver lotes, filas, duplicados y la conciliación. |
| `deck/` | Las slides de la clase (`index.html`) y el guion del orador (`guion.md`). |
| `deck_corto/` | Versión de 40 slides de la misma clase (240 min con el descanso de 20 min), con su guion. |
| `prueba_ensayo.md` | Guía de ensayo del instructor. No es para estudiantes. |

<a id="migrar"></a>
## Antes de la clase: deja tu cuenta lista

### Qué cambió y por qué hay que migrar

Hasta la clase 6, los datos de tu bucket vivían en carpetas compartidas (`bronze/`, `muestra/`). Una corrida de prueba podía crear un lote que prod leía sin que nadie lo hubiera decidido. Desde hoy, **dev y prod no comparten ninguna carpeta**: dev escribe en `s3://<tu-bucket>/dev/` y prod en `s3://<tu-bucket>/prod/`. En Snowflake pasa lo mismo: una base `BIGDATA` con cuatro esquemas, `DEV`, `PROD`, `CONTROL_DEV` y `CONTROL_PROD`.

Migrar es mover el crudo que ya descargaste (para no volver a bajar 5.4 GB), crear los esquemas nuevos y dejar el Code Editor listo para escribir en S3. Un solo comando lo hace, pero antes necesitas el código nuevo.

**Cuánto tarda:** entre 15 y 40 minutos, casi todo moviendo archivos dentro de S3. Hazlo antes de la clase, con tiempo.

<a id="paso-1"></a>
### Paso 1 · Que no tengas cambios sin guardar

Abre una terminal en el Code Editor (menú **Terminal > New Terminal**) y escribe:

```bash
cd ~/bigdata
git status
```

`cd ~/bigdata` entra a la carpeta del repositorio. `git status` lista lo que cambiaste desde la última vez que guardaste.

**Debes ver:** `nothing to commit, working tree clean`, o una lista de archivos que modificaste a propósito (por ejemplo, `silver.py` o `gold.py` del Taller 2). Si ves archivos que no reconoces, avisa al instructor antes de seguir.

Si tienes cambios tuyos sin guardar, guárdalos primero:

```bash
cd ~/bigdata
git add src/pipeline/silver.py tests/test_silver.py
git commit -m "Mi avance antes de la clase 7"
```

Cambia los nombres de archivo por los tuyos. Escríbelos uno por uno en lugar de usar `git add -A`: así no subes archivos que no querías.

<a id="paso-2"></a>
### Paso 2 · Traer el código nuevo a tu fork

Los equipos tienen un fork con su propio `main`, y varios ya editaron `silver.py` o `gold.py`. Por eso este paso se hace **una sola vez por equipo, el anfitrión primero**; los demás integrantes hacen después un `git pull`.

**2.1 · Guarda una copia de seguridad de tu `main`:**

```bash
cd ~/bigdata
git checkout -b respaldo-antes-de-clase07
git push -u origin respaldo-antes-de-clase07
git checkout main
```

`git checkout -b` crea una rama nueva con lo que tienes hoy; el `push` la sube a GitHub (es opcional, pero te salva si algo sale mal); `git checkout main` te devuelve a la rama principal.

**Debes ver:** `Switched to a new branch 'respaldo-antes-de-clase07'` y, al final, `Switched to branch 'main'`.

**2.2 · Conecta tu fork con el repositorio del instructor (solo la primera vez):**

```bash
cd ~/bigdata
git remote add upstream https://github.com/<REPOSITORIO_DEL_INSTRUCTOR>.git
git fetch upstream
```

El instructor da la dirección en clase: reemplaza `<REPOSITORIO_DEL_INSTRUCTOR>` por la que dé. `git remote add upstream` anota esa dirección con el nombre `upstream`; `git fetch upstream` descarga lo nuevo sin tocar tus archivos. Si responde `error: remote upstream already exists`, ya lo hiciste: salta el `add` y haz solo el `fetch`.

**2.3 · Une lo nuevo con lo tuyo:**

```bash
cd ~/bigdata
git merge upstream/main
```

- Si responde `Already up to date.` o termina sin conflictos, pasa al paso 3.
- Si responde `CONFLICT (content): Merge conflict in ...`, es lo esperado cuando tu equipo editó un archivo que la casa también cambió. No te asustes: el merge queda a medias y la tabla de abajo dice qué hacer con cada archivo.

En un merge, `--ours` es **tu fork** y `--theirs` es **la casa** (el repositorio del instructor).

| Archivo en conflicto | Por qué | Qué hacer |
|---|---|---|
| `src/pipeline/silver.py` | La casa agregó `deduplicar`, `limpiar_taxi_zones` y un `main` nuevo; tu equipo editó `limpiar_viajes` o `enriquecer` | `git checkout --theirs src/pipeline/silver.py` y vuelve a poner tu cambio (abajo) |
| `src/pipeline/gold.py` | La casa agregó `tarifa_por_milla_por_barrio` y un `main` nuevo; tu equipo editó `metricas_diarias_zona` o `COLUMNAS` | Igual: `--theirs`; esas dos funciones de la clase 6 ya no están en la casa (tu tabla de gold va en `TABLAS_GOLD`) |
| `tests/test_silver.py` y `tests/test_gold.py` | Las pruebas cambiaron | `--theirs` y vuelve a agregar las tuyas al final |
| `src/pipeline/bronze.py` | Pasó a ser el esqueleto con las funciones del equipo | `--theirs` |
| Cualquier otro de `src/`, `airflow/`, `Makefile`, `scripts/`, `infra/` o `tests/` | Cambios de la casa | `--theirs`; no se editan a mano |
| Algo dentro de `taller2/` | No debería chocar | Avisa al instructor |

Cómo volver a poner tu cambio en `silver.py` o `gold.py`: las funciones `limpiar_viajes`, `clima_diario` y `enriquecer` (en silver) **conservan nombre y firma**, así que tu cambio cabe en el mismo lugar. En gold, `metricas_diarias_zona` y `COLUMNAS` eran de la clase 6 y ya no están: si tu equipo las tenía, copia tu función a `gold.py` y súmala a `TABLAS_GOLD` y `LLAVES_DE_GOLD`.

```bash
cd ~/bigdata
git checkout --theirs src/pipeline/silver.py
git show respaldo-antes-de-clase07:src/pipeline/silver.py > ~/silver_mio.py
diff ~/silver_mio.py src/pipeline/silver.py
```

`git show <rama>:<archivo>` imprime el archivo como estaba en tu copia de seguridad, y lo guardamos en `~/silver_mio.py`. `diff` muestra línea por línea qué cambió: copia tu cambio a `src/pipeline/silver.py`. Repite con `gold.py` si te tocó.

Cuando termines con todos los conflictos, guarda el resultado:

```bash
cd ~/bigdata
git add -A
git commit -m "Trae la clase 7 de la casa"
make test
git push origin main
```

**Debes ver en `make test`:** las pruebas pasan y algunas salen con `SKIPPED ... PENDIENTE: ...`. Es **lo esperado**: son las pruebas de las funciones que tu equipo todavía no ha escrito (los metadatos de bronze y `deduplicar` de silver). No es un error.

**Si prefieres no usar la terminal** y tu fork no tiene conflictos: en GitHub, en la página de tu fork, haz clic en **Sync fork** y luego en **Update branch**. Después, en el Code Editor, `cd ~/bigdata && git pull`.

**Los demás integrantes del equipo** solo hacen:

```bash
cd ~/bigdata
git pull
```

<a id="paso-3"></a>
### Paso 3 · Migrar tu cuenta con make

```bash
cd ~/bigdata
make migrar-clase07
```

El comando es **idempotente**: si se corta o falla, lo repites y sigue donde quedó. Antes de empezar imprime lo que va a hacer y te pide que escribas el número de tu cuenta de AWS para confirmar.

Qué hace, en seis pasos:

| Paso | Qué hace |
|---|---|
| 0 · Revisión | Comprueba tu cuenta y tu bucket. Se detiene si dejaste un merge de git a medias |
| 1 · S3 | Mueve el **crudo** de `bronze/` a `prod/bronze/` (los lotes viejos se quedan sin usar), borra `muestra/`, y borra los restos de `silver/` y `gold/` de la raíz si solo tienen marcadores |
| 2 · Snowflake, tabla vieja | Borra `BIGDATA.PROD.DAILY_ZONE_METRICS`, una prueba del 20 de noviembre. Si el script dice que no pudo borrarla, es normal (nunca existió en tu cuenta) y no hace daño: sigue |
| 3 · Infraestructura | Corre `make snowflake`: crea los esquemas `DEV`, `PROD`, `CONTROL_DEV` y `CONTROL_PROD`, los roles `BIGDATA_DEV` y `BIGDATA_PROD` y las tablas de control |
| 4 · Spark | Corre `make jars-s3a`: baja una vez los dos archivos que Spark necesita para escribir en S3 (unos 280 MB) |
| 5 · Airflow | Reinicia el Airflow del Code Editor |
| 6 · Comprobación | Corre `make doctor` y `make rutas` y lista la raíz del bucket |

**Dos momentos en los que debes hacer algo:**

1. **El número de cuenta.** Escribe tu número de cuenta de 12 dígitos y presiona Enter. Es el mismo que imprime `aws sts get-caller-identity --query Account --output text`.
2. **El plan de Terraform (paso 3).** Terraform muestra un plan y pide `yes`. **Antes de escribir `yes`, mira la línea del resumen:** `Plan: N to add, N to change, 0 to destroy.` Si dice **cualquier número distinto de 0 en `destroy`**, escribe `no` y avisa al instructor: no lo juzgues tú. Si dice `0 to destroy`, escribe `yes`.

**Debes ver, al final:**

```text
==> Paso 6 de 6: comprobación
...
Raíz del bucket (debe verse code/ dags/ logs/ prod/; dev/ y tmp/ aparecen cuando corras algo):
                           PRE code/
                           PRE dags/
                           PRE logs/
                           PRE prod/

==> Migración terminada.
Siguiente:  sigue con la clase: resetear_entorno dev
```

(El `PRE bronze/` y `PRE muestra/` ya no deben aparecer. Si aparece `bronze/` con carpetas `lote=...` adentro, es normal: son los lotes viejos, que nadie lee.)

<a id="antes-de-seguir"></a>
### Antes de seguir

No sigas hasta que cada comprobación dé el resultado indicado. Todas empiezan con `cd ~/bigdata`.

**1. Spark sabe escribir en S3.**

```bash
cd ~/bigdata
ls ~/.spark-jars
```

Debe listar `aws-java-sdk-bundle-1.12.262.jar` y `hadoop-aws-3.3.4.jar`. Si no, corre `cd ~/bigdata && make jars-s3a`.

**2. El diagnóstico no marca fallos.**

```bash
cd ~/bigdata
make doctor
```

Debe terminar sin ninguna línea de fallo. Mira en particular estas: `PIPELINE_ENTORNO=dev (desde el Code Editor siempre es dev)` y que no se queje de los jars. Si dice `PIPELINE_ENTORNO=prod en esta terminal`, corre `unset PIPELINE_ENTORNO`.

**3. Las rutas son las nuevas.**

```bash
cd ~/bigdata
make rutas ENTORNO=dev
```

Debe imprimir una tabla donde cada ruta empieza con `s3://bigdata-lake-<tu-cuenta>-us-east-2/dev/`. Es solo informativo: no cambia con qué entorno corres.

**4. El crudo llegó a prod.**

```bash
cd ~/bigdata
LAKE="bigdata-lake-$(aws sts get-caller-identity --query Account --output text)-us-east-2"
aws s3 ls "s3://$LAKE/prod/bronze/_crudo/" --recursive | tail -3
```

Debe listar archivos de `fhvhv`, `clima` o `taxi_zones` (si ya los tenías de la clase 4; si no, no pasa nada: se descargan hoy).

**5. Las pruebas pasan, con los `PENDIENTE` esperados.**

```bash
cd ~/bigdata
make test
```

Al final debe haber una línea `... passed, ... skipped` y **ninguna** línea `FAILED`. Las líneas `SKIPPED ... PENDIENTE: ...` son lo esperado.

**6. Puedes consultar Snowflake con el rol de dev.** En Snowsight, abre una hoja de SQL y ejecuta, una sentencia a la vez:

```sql
USE ROLE BIGDATA_DEV;
USE WAREHOUSE BIGDATA_WH;
USE DATABASE BIGDATA;
SHOW SCHEMAS IN DATABASE BIGDATA;
```

Debe listar `DEV`, `PROD`, `CONTROL_DEV` y `CONTROL_PROD` (además de otros esquemas de clases anteriores).

Si las seis comprobaciones dieron lo esperado, tu cuenta está lista.

<a id="errores"></a>
### Errores comunes

| Lo que ves | Qué pasó | Qué hacer |
|---|---|---|
| `Tienes un merge de git a medias` al correr `make migrar-clase07` | Quedó un `git merge` sin terminar | `cd ~/bigdata`, `git status`, resuelve los archivos con conflicto (tabla del paso 2.3), `git add -A`, `git commit -m "Trae la clase 7 de la casa"` y repite |
| `No existe .venv` | Tu entorno de Python no está | `cd ~/bigdata && make reparar-entorno` y repite |
| Terraform dice `N to destroy` con N mayor que 0 | El plan quiere borrar algo | Escribe `no` y avisa al instructor. No lo juzgues tú |
| `No pude bajar hadoop-aws-3.3.4.jar` | Falló la descarga (red) | `cd ~/bigdata && make jars-s3a` otra vez; es seguro repetirlo |
| `Cancelado: no se escribió '...'` | No escribiste exactamente el número de cuenta | Repite `make migrar-clase07` y escríbelo completo, sin espacios |
| `AccessDenied` al mover archivos | Credenciales vencidas o rol equivocado | Cierra la terminal, ábrela de nuevo y repite |
| `make test` falla con `FAILED` (no `SKIPPED`) | Un conflicto mal resuelto, casi siempre en `silver.py` o `gold.py` | Compara con la casa: `cd ~/bigdata && git diff upstream/main -- src/pipeline/silver.py` |
| La migración terminó pero `aws s3 ls` todavía muestra `bronze/` | Quedan los lotes viejos (`lote=...`) | Es normal. Nadie los lee; se pueden borrar después del curso |
| `PIPELINE_ENTORNO=prod en esta terminal` | Una variable de entorno de otro curso | `unset PIPELINE_ENTORNO` y quítala de `~/.bashrc` si está |

<a id="antes-ahora"></a>
## Antes y ahora

Las clases 1 a 6 no se reescriben: lo que dijimos entonces sigue siendo cierto de esas clases. Esta tabla dice cómo se llama hoy cada cosa.

| Antes (clases 1 a 6) | Ahora |
|---|---|
| `bronze/` y `muestra/` en la raíz del bucket | `prod/bronze/...` y `dev/bronze/...`; ya no hay muestra |
| Silver `fhvhv_trips/pickup_date=...` | Silver `fhvhv/mes=...`: espejo de bronze, una tabla por fuente (`fhvhv`, `clima`, `taxi_zones`) |
| Gold `daily_zone_metrics` | Gold de la casa: `tarifa_por_milla_barrio`. Cada equipo nombra las suyas |
| `spark_local`, `--env local`, `get_spark("local")` | Cómputo `code_editor` (`"local"` sigue valiendo como alias) |
| `--step`, `--env`, `--engine` | `--paso`. No hay `--env` ni `--engine`: el entorno no se elige y el cómputo se llama `--computo` |
| `make muestra`, `make run-local` | `make correr` (los comandos viejos ya no existen) |
| `BIGDATA.CONTROL.WATERMARK` | `BIGDATA.CONTROL_DEV.WATERMARK` y `BIGDATA.CONTROL_PROD.WATERMARK` (la vieja es la de la práctica de las clases 5 y 6) |
| `BIGDATA.DEV.DAILY_ZONE_METRICS` como «la tabla» | Cada equipo nombra sus tablas; viven en `BIGDATA.DEV` o `BIGDATA.PROD` |
| Rol `ACCOUNTADMIN` y warehouse `COMPUTE_WH` | `BIGDATA_DEV` y `BIGDATA_WH` para todo lo del Taller. Los otros son nombres de las clases 1 a 6 |
| «Con las funciones del equipo» (clase 6 y Taller) | Quiere decir «con el código de tu fork». En Glue corre el `bronze.py` de la casa; tu cambio vive en `silver.py`, `gold.py` y su tabla en `carga.py` |

<a id="donde"></a>
## Dónde se cambia cada cosa

El pipeline tiene cuatro pasos (`bronze`, `silver`, `gold`, `snowflake`), cada uno es una función (`correr_bronze`, `correr_silver`, `correr_gold`, `cargar_snowflake`) y se llama igual desde un notebook, desde `make correr PASO=...` y desde una tarea del DAG `pipeline_taxi`. Las perillas están en `pipeline.yaml`, en la raíz del repositorio:

```yaml
computo: code_editor   # dónde se calcula: code_editor | glue_small | glue_medium | glue_large
limite: "1000"        # filas por fuente: "1000" | "100000" | "todos" (con code_editor solo 1000 o 100000)
mes: "2024-01"         # AAAA-MM; vacío = todos los meses de config/dev.yaml
reprocesar: false      # true = ignora la tabla de control y procesa el mes otra vez
```

| Qué quiero cambiar | Dónde | Nota |
|---|---|---|
| El límite de filas (`1000`, `100000`, `todos`) | `pipeline.yaml`, `LIMITE=` en `make`, `limite=` en la función o el formulario del DAG | `todos` solo con Glue; en prod siempre es `todos` |
| El cómputo | `pipeline.yaml`, `COMPUTO=`, `computo=` o el formulario | Es lo único que cambia entre el Code Editor y Glue |
| El mes y si se reprocesa | `pipeline.yaml`, `MES=` y `REPROCESAR=`, o el formulario | La tabla de control decide si se salta |
| El entorno | **No se cambia: es automático.** Code Editor = dev; prod lo pone el despliegue en la VM | El código se niega a correr prod fuera de ahí |
| Pasar algo a prod | Pull request, merge a `main`, CI/CD y el DAG en la VM | Nunca desde el Code Editor |
| La lógica del pipeline | Solo `bronze.py`, `silver.py`, `gold.py` (y la tabla de tu gold en `carga.py`) | Lo demás es de la casa |

Quien gana si hay varios: **el argumento del comando, de la función o del formulario gana sobre `pipeline.yaml`, y este gana sobre el valor por defecto**.

Cada corrida imprime el mismo encabezado en todos lados (consola, notebook, Airflow, Glue y prod):

```text
==================================================================
 Entorno    : DEV
 Cómputo    : code_editor
 Paso       : bronze
 Mes        : 2024-01
 Límite     : 1000
 Reprocesar : false
 Lee        : s3://bigdata-lake-123456789012-us-east-2/dev/bronze/_crudo/fhvhv/mes=2024-01/
              s3://bigdata-lake-123456789012-us-east-2/dev/bronze/_crudo/taxi_zones/
              s3://bigdata-lake-123456789012-us-east-2/dev/bronze/_crudo/clima/mes=2024-01/
 Escribe    : s3://bigdata-lake-123456789012-us-east-2/dev/bronze/fhvhv/mes=2024-01/
              s3://bigdata-lake-123456789012-us-east-2/dev/bronze/taxi_zones/
              s3://bigdata-lake-123456789012-us-east-2/dev/bronze/clima/mes=2024-01/
 Control    : BIGDATA.CONTROL_DEV.WATERMARK
==================================================================
```

y al final un cierre con una línea por tabla: cuántas filas leyó, cuántas escribió y si **se saltó** o **registró** en la tabla de control.

<a id="notebooks"></a>
## Cómo se abren los notebooks

Copia el notebook a una carpeta tuya, para no tocar el del repositorio:

```bash
mkdir -p ~/clase07_mis_notebooks
mkdir -p ~/clase07_mis_notebooks && cp ~/bigdata/curso/clase07/01_construir_paso_a_paso.ipynb ~/clase07_mis_notebooks/
```

En el explorador de archivos de la izquierda, abre `clase07_mis_notebooks`, haz doble clic en el notebook y, arriba a la derecha, elige el kernel **Python (bigdata)**. No elijas los que dicen *Glue* o *SparkMagic*: abren una sesión de AWS Glue que cobra mientras está abierta. Ejecuta una celda con **Shift + Enter**.

En esta máquina solo cabe un proceso de Spark a la vez. Si tienes abierto otro notebook con Spark encendido, ciérralo (este termina con una celda que lo apaga) o reinicia su kernel. Si Airflow del Code Editor está encendido, apágalo con `cd ~/bigdata && make airflow-local-down` antes de abrir un notebook, y vuelve a encenderlo cuando la clase lo pida.

<a id="no-vale"></a>
## Lo que no vale después de migrar

- **Los `.sql` de `curso/clase06/athena/` dejan de funcionar.** Apuntan a `bronze/` en la raíz del bucket, que ya no existe. Hoy usas los de `curso/clase07/athena/`, con tablas que se llaman `dev_...` y `prod_...`.
- **La VM de prod puede listar un DAG de las clases 5 y 6 en pausa.** Es un resto de la base de datos de Airflow de prod: el archivo ya no está. No importa y no hay que hacer nada.
- **La práctica de ingesta de las clases 5 y 6 sigue corriendo**, pero solo en el Airflow del Code Editor y escribiendo en el disco. No es el pipeline. El pipeline se llama `pipeline_taxi`.
- **Si lanzas el DAG en dev con Glue,** el código que corre es el de tu árbol de trabajo (se sube a `code/dev/`), no el de `main`. Lo que corre en prod es siempre el de `main`.

<a id="clase"></a>
## Cómo es la clase

1. Apertura: qué dijimos en las clases 5 y 6 y qué cambia; dev y prod; dónde se cambia cada cosa.
2. **Empezamos limpios:** `resetear_entorno` en dev (el DAG que borra todo el entorno de ese Airflow).
3. **Notebook 1:** se construye y se prueba cada función con 1 000 viajes, en el dev de verdad: Spark del Code Editor escribe en `s3://<lake>/dev/` y la tabla de control es `BIGDATA.CONTROL_DEV.WATERMARK`. No se escribe nada en el disco. El límite se aplica solo en bronze.
4. **`resetear_entorno` en dev otra vez:** el notebook dejó datos reales (crudo, un lote de bronze, filas de control); se borran para que las tareas del DAG partan de cero.
5. **Del notebook al `.py`:** las celdas finales del Notebook 1 dicen qué funciones cambiaste (`DISTINTO`) y corren las pruebas del equipo; se abren `bronze.py` y `silver.py` (son las mismas funciones), se ve cómo se copia un cambio y se corre `make test` (salen `PENDIENTE`).
6. **Las tareas del DAG, una por una** (`airflow tasks test`): primero bronze y Athena; luego silver y Athena; luego gold y Athena. Ahí se notan los problemas: bronze sin huella y qué hace la tabla de control.
7. Ejecutar en Snowsight el `CREATE TABLE` (el código nunca crea la tabla; si falta, `cargar_snowflake` falla e imprime el SQL) y correr el DAG completo desde la interfaz: con `reprocesar` sin marcar, bronze, silver y gold **se saltan** y solo carga Snowflake.
8. Resetear (que también borra la tabla de Snowflake), ejecutar otra vez el `CREATE TABLE` en Snowsight y correr todo otra vez: funciona una vez.
9. **Reprocesar a propósito** (`reprocesar=true`): bronze guarda los dos lotes, silver los espeja sin deduplicar y gold multiplica; medido: silver ×2 y gold ×8. Se ve en Athena y en Snowflake.
10. `make correr` y `glue_small`, y el ejercicio de dimensionamiento: cuánto tarda cada combinación de límite y cómputo.
11. Cierre: la escalera de dev a prod. Llevar todo a prod (pull request, CI/CD, DAG en la VM) y validarlo con Athena y Snowflake **pasó a la clase 8**; el borrador está en `curso/clase08/borrador_prod.md`.

Las dos reglas que se repiten: el límite recorta **solo bronze**, y **sin `reprocesar` la segunda corrida se salta**: los duplicados aparecen solo al forzarlo.

**Clase 8 (martes 24):** se lleva este pipeline a prod por pull request, CI/CD y el DAG en la VM, se valida con Athena y Snowflake, se muestra el DAG que resetea todo en prod y arranca el Taller 2.
