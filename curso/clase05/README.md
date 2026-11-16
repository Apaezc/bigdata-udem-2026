# Clase 5 · Transformar con Spark (mar 17 nov)

Pregunta de la clase: ¿cómo llegan al lake, sin repetirse, los datos de tres fuentes que cambian cada mes? Es la primera clase en la que escribes código del pipeline: aprendes a usar Spark y después escribes la ingesta de las tres fuentes a tu propio bronze. El trabajo se hace en tres notebooks que corren en el Code Editor de SageMaker, con Spark en local. El lab de silver y gold, que antes era parte de esta clase, es ahora el lab de la clase 6 (`curso/clase06/`).

| Archivo | Para quién | Qué es |
|---|---|---|
| [`01_fundamentos.ipynb`](01_fundamentos.ipynb) | Estudiantes | Tus primeras líneas de Spark con los viajes de NYC: conoces las tres fuentes de datos y practicas ver, seleccionar, transformar, filtrar, agrupar y unir, además de depurar paso a paso. Cada sección termina con un «Pruébalo tú», y una sección propia presenta las funciones de columna que usarás en el lab. |
| [`02_como_funciona.ipynb`](02_como_funciona.ipynb) | Estudiantes | Lo que Spark hace por dentro: driver, ejecutores y particiones; pandas frente a Spark frente a Snowflake; lazy y `explain()`; operaciones estrechas y anchas; *shuffle*; `broadcast`. |
| [`03_lab.ipynb`](03_lab.ipynb) | Estudiantes | El lab: la ingesta a bronze de las tres fuentes. Antes de cada ejercicio hay una explicación corta (consumir una fuente, guardar el crudo por lote, metadatos y huella, tabla de control con `reprocesar`). Tiene cuatro ejercicios con huecos `# TU CÓDIGO AQUÍ` y una prueba debajo de cada uno que dice `OK`, `PENDIENTE` o `REVISAR`: la huella de una fila y las funciones `ingestar_clima`, `ingestar_zonas` e `ingestar_viajes`. |
| [`03_lab_solucion.ipynb`](03_lab_solucion.ipynb) | Instructor | El mismo lab con los cuatro ejercicios resueltos. |
| [`prueba_code_editor.md`](prueba_code_editor.md) | Autor | Guion para probar los tres notebooks en un Code Editor real antes de la clase. |

Los datos de la clase son los de enero de 2024: 19 663 930 viajes FHVHV, las 265 zonas de la ciudad y el clima diario de Open-Meteo. Los notebooks 01 y 02 leen el archivo de viajes desde tu propio bucket `bigdata-lake-<CUENTA>-us-east-2` y lo guardan una sola vez en `~/datos_clase05`, fuera del repositorio, para que nunca llegue a un commit. El lab 03 descarga desde las fuentes originales (la TLC y Open-Meteo) y escribe su bronze en `~/datos_clase05/bronze_alumno`; en el modo de prueba de los viajes baja otra vez el archivo de unos 450 MiB, así que conviene tener ese espacio libre en disco.

La tabla de control de la ingesta vive en Snowflake, en `BIGDATA.CONTROL.WATERMARK`. Los métodos `consultar_watermark` y `registrar_watermark` ya están hechos en `src/pipeline/watermark.py`. El esquema `CONTROL` y la tabla los crea Terraform: **al inicio de la clase**, corre `cd ~/bigdata && git pull && make reparar-entorno && make snowflake` (confirma el plan con `yes`; solo agrega recursos nuevos; la sección 1 explica cada parte). Usan la conexión `default` de `~/.snowflake/connections.toml` (el lab tiene una variable `CONEXION_SNOWFLAKE` por si la tuya se llama distinto) con el rol `ACCOUNTADMIN` y el warehouse `COMPUTE_WH`.

## 1. Preparar el entorno (al inicio de cada clase)

Necesitas haber terminado la [guía](../../docs/guia.md): el repositorio en `~/bigdata`, tu lake con el bronze de enero y la conexión a Snowflake llamada `default` (el lab de esta clase también la usa, para la tabla de control). Cada vez que el Code Editor se reinicia, SageMaker puede haber actualizado la imagen y cambiado la versión de Python del sistema; si eso pasa, el `.venv` deja de ver sus librerías y el comando `snow` falla. Por eso la clase empieza siempre con este comando, desde una terminal del Code Editor:

```bash
cd ~/bigdata && git pull && make reparar-entorno && make snowflake
```

Cada parte hace una cosa. `git pull` trae la última versión de los notebooks y del código. `make reparar-entorno` recrea el `.venv` con Python 3.12, reinstala las dependencias (`pandas`, `pyarrow`, `snowflake-connector-python`, `ipykernel`, `setuptools`...), registra el kernel de Jupyter **Python (bigdata)** y comprueba que `snow` funcione. `make snowflake` aplica Terraform y crea la tabla `BIGDATA.CONTROL.WATERMARK` con sus permisos; muestra un plan y debes confirmarlo escribiendo `yes` (solo agrega recursos nuevos).

Salida esperada: unos minutos de instalación y, al final de `make reparar-entorno`, la línea `==> Entorno reparado: Python 3.12.x, snow OK`. Un kernel es el programa Python que ejecuta las celdas del notebook; el que se registra usa el Python de `~/bigdata/.venv`, que es el que tiene PySpark. Como el `.venv` se crea de nuevo, **si ya tenías un notebook abierto debes elegir otra vez el kernel** (sección 3) y reiniciarlo.

Comprueba tres cosas antes de la clase:

```bash
cd ~/bigdata && .venv/bin/python -c "import pandas, pyarrow, pyspark, snowflake.connector; print('librerias ok')"
java -version
cd ~/bigdata && .venv/bin/python -c "import snowflake.connector as s; c = s.connect(connection_name='default'); print(c.cursor().execute('select current_user()').fetchone()); c.close()"
```

Salida esperada: `librerias ok`; una versión de Java que empieza por `openjdk version "17`; y una tupla con tu usuario de Snowflake, por ejemplo `('TU_USUARIO',)`. Esta última comprobación es la que necesita el lab 03: si falla, la tabla de control no podrá consultarse. La tabla de control y sus permisos ya los creó `make snowflake` en el comando anterior. Si `java -version` no encuentra Java, no te preocupes todavía: la primera celda de cada notebook busca el Java que instaló `make setup` en `~/.local/opt/java17`.

## 2. Trabajar sobre una copia del notebook

No edites los notebooks que vienen en el repositorio. Si los modificas y después el instructor sube una corrección, `git pull` se detiene con un conflicto. En lugar de eso, copia los notebooks a una carpeta tuya, fuera del repositorio, y trabaja ahí. Desde una terminal del Code Editor:

```bash
mkdir -p ~/clase05_mis_notebooks && cp ~/bigdata/curso/clase05/01_fundamentos.ipynb ~/bigdata/curso/clase05/02_como_funciona.ipynb ~/bigdata/curso/clase05/03_lab.ipynb ~/clase05_mis_notebooks/
```

Salida esperada: ninguna (si no hay error, la copia salió bien). Comprueba con `ls ~/clase05_mis_notebooks`: deben aparecer los tres archivos. No copies `03_lab_solucion.ipynb`: es la versión del instructor. Los notebooks funcionan desde cualquier carpeta; encuentran el repositorio en `~/bigdata` por sí solos.

## 3. Abrir un notebook y elegir el kernel

1. En el Code Editor abre el explorador de archivos y entra a `clase05_mis_notebooks/`.
2. Abre `01_fundamentos.ipynb`. Si el editor ofrece instalar la extensión de Jupyter, acéptala.
3. Arriba a la derecha haz clic en **Select Kernel**, elige **Jupyter Kernel** y después **Python (bigdata)**. Hazlo de nuevo cada vez que corras `make reparar-entorno`, porque ese comando recrea el `.venv`. Si no aparece, elige el intérprete `~/bigdata/.venv/bin/python`.
4. Ejecuta la primera celda de código (la Celda 1). Debe imprimir una ruta de Python que contiene `.venv` y la versión de Java. Si imprime `AVISO: este kernel no es el del proyecto`, el kernel está mal elegido: vuelve al paso 3.

**Nunca elijas un kernel que se llame `Glue PySpark`, `Glue Spark` ni `SparkMagic`.** El Code Editor los ofrece en la lista, pero abren una sesión de AWS Glue en la nube, y esa sesión cobra mientras está abierta. Los notebooks de esta clase usan Spark en tu propia máquina, con el kernel **Python (bigdata)**, y no cuestan nada.

Ejecuta las celdas en orden con Shift+Enter. Cada celda de código empieza con un comentario `# Celda N` que dice su número dentro del notebook; el texto y la clase usan ese número cuando te mandan a una celda concreta.

## 4. Cerrar Spark antes de la terminal y entre notebooks

En esta máquina solo cabe un proceso de Spark a la vez. Por eso cada notebook termina con una celda `spark.stop()` y esa celda se ejecuta antes de abrir el siguiente notebook y antes de usar la terminal para `make test` o `pipeline.run`. Si olvidas cerrar Spark, el otro proceso se queda esperando o falla por memoria; la solución es ejecutar la celda de cierre o reiniciar el kernel del notebook que lo tenía abierto.

## 5. Qué debes ver, notebook por notebook

Las cifras no están escritas aquí a propósito: las produce cada celda en tu máquina.

| Notebook y sección | Qué debe pasar |
|---|---|
| **01** · 0 Preparación | Imprime tu cuenta y tu bucket, trae el archivo de enero una sola vez (451 MiB), las zonas y el clima, arranca Spark y muestra `defaultParallelism` y el enlace de la Spark UI. |
| **01** · 1 Conoce tus datos | El esquema de los viajes (24 columnas), un viaje completo en vertical, las 265 zonas como texto, y el clima aplanado a 31 filas. |
| **01** · 2 a 11 | Cada sección imprime tablas pequeñas y cifras; cada «Pruébalo tú» se resuelve con una o dos líneas. La sección 8 termina diciendo que el `join` conservó todos los viajes y que, con una zona repetida, las filas de más son exactamente los viajes de esa zona. |
| **01** · 12 Funciones de columna | Seis ejemplos cortos (`F.coalesce` y `F.lit`, `F.concat_ws`, `F.sha2`, `F.concat`, `F.broadcast`, `dropDuplicates` y `orderBy`), cada uno con su «Pruébalo tú»: son las piezas que el lab te pide escribir. |
| **01** · 13 Depurar | Un recorrido por pasos con nombre sobre una muestra y después sobre todo enero, y tres errores que arreglas hasta que `comprobar` dice `OK`. |
| **02** · 1 Arquitectura | El número de particiones del archivo y una tabla con las filas de cada una, cuya suma es 19 663 930. |
| **02** · 2 Pandas, Spark y Snowflake | Tiempos y memoria de los tres, y dos líneas `pandas vs ...: COINCIDEN`. |
| **02** · 3 y 4 | Las celdas de «definir» tardan milisegundos; el `count()` tarda lo que cuesta leer el archivo; el plan muestra `ReadSchema` y `PushedFilters`; un plan sin `Exchange` y otro con `Exchange`; `HashAggregate` parcial y final; `Exchange SinglePartition` en la ventana sin partición. |
| **02** · 5 Broadcast | `SortMergeJoin` frente a `BroadcastHashJoin`, dos tiempos y `Resultados iguales: True`. |
| **03** · 0 Preparación | Las mismas comprobaciones del 01, tus rutas (`bronze_alumno` y la ruta de S3 que usará el DAG), el nombre de tu conexión de Snowflake y Spark encendido. |
| **03** · 1 Consumir una fuente | Las tres URL de febrero de 2024, el peso del archivo de viajes sin descargarlo, el comienzo del JSON del clima (termina el día 29, porque 2024 es bisiesto) y el comienzo del CSV de zonas. |
| **03** · 2 y 3 | Las rutas de un lote de ejemplo, con el crudo y el lote bajo el mismo identificador; la tabla de metadatos y el ejercicio 1, la huella de una fila. |
| **03** · 4 La tabla de control | La demostración con la tabla `demo`: consultar un mes que no existe devuelve `[]`, registrar una ingesta y consultar devuelve un JSON con siete campos, un segundo registro con `reprocesar=True` aparece después del primero, y al final se borran los registros de `demo`. La primera celda tarda un poco más porque crea el esquema y la tabla. |
| **03** · ejercicios 2, 3 y 4 | Cada uno trae pistas desplegables y una prueba que imprime `OK`, `PENDIENTE` o `REVISAR` con una pista. Con el enunciado sin resolver las cuatro líneas dicen `PENDIENTE`; con todo resuelto, `OK`. Cada prueba tarda unos segundos porque abre varias conexiones a Snowflake y usa la tabla `prueba_*` y el mes `2099-01`, que borra al terminar. |
| **03** · ejecución con datos reales | Clima en tres llamadas (ingesta, no hace nada, reproceso con otro lote), zonas en dos y viajes en modo de prueba: descarga el archivo de enero completo y escribe 1 000 filas. Después lista los archivos, muestra la tabla de control de cada fuente y lee un lote de cada una. Un mes completo de viajes es opcional y viene apagado. |
| **03** · cierre | Borra los registros de práctica de la tabla de control, borra los archivos de prueba temporales y apaga Spark. |

## 6. Errores comunes

| Lo que ves | Causa | Cómo evitarlo o arreglarlo |
|---|---|---|
| `Java gateway process exited before sending its port number` o `JAVA_HOME is not set`, o la Celda 1 imprime `AVISO: no se encontró Java` | El kernel del notebook no lee `~/.bashrc` y no ve el Java que instaló `make setup` | La Celda 1 busca Java en `~/.local/opt/java17` y define `JAVA_HOME` sola. Si aun así falla, ejecuta `ls ~/.local/opt/java17/bin/java` en una terminal; si no existe, ejecuta `cd ~/bigdata && make setup` y reinicia el kernel |
| `ModuleNotFoundError: No module named 'pandas'` (o `pyarrow`, `snowflake`) | El notebook corre con otro kernel, o el `.venv` quedó roto porque el Code Editor actualizó su imagen y cambió de Python | Elige el kernel **Python (bigdata)** (sección 3 de este README). Si ya lo elegiste y sigue fallando, ejecuta `cd ~/bigdata && make reparar-entorno`, elige el kernel de nuevo y reinicia |
| `ModuleNotFoundError: No module named 'snowflake.cli'` al usar `snow` | `snow` se instaló sobre una versión anterior de Python de la imagen del Code Editor | Ejecuta `cd ~/bigdata && make reparar-entorno`: comprueba `snow` y lo reinstala si falla |
| Aparece una sesión de Glue, un mensaje de *Glue Session* o un cargo de AWS Glue | Elegiste un kernel `Glue PySpark`, `Glue Spark` o `SparkMagic` | Cierra esa sesión, elige **Python (bigdata)** y reinicia. Esos kernels abren una sesión de Glue que cobra |
| `No active warehouse selected in the current session` o `Warehouse: None` en la sección 2 de `02_como_funciona` | La conexión de Snowflake por llave no trae warehouse | La celda ejecuta `USE ROLE ACCOUNTADMIN` y `USE WAREHOUSE COMPUTE_WH`. Si el warehouse de tu cuenta se llama distinto, cambia ese nombre en la celda |
| La Spark UI abre sin estilos (texto plano) o dice `Unsupported URL path` | Spark no conocía el prefijo del proxy del Code Editor, o abriste la raíz del enlace, que redirige mal detrás del proxy | Usa el enlace que imprime la Celda 5, que termina en `/jobs/`. Esa celda define `PYSPARK_SUBMIT_ARGS` con `spark.ui.proxyBase` **antes** de arrancar Spark; si Spark ya estaba encendido de antes, reinicia el kernel y ejecuta la celda desde el principio |
| `ModuleNotFoundError: No module named 'distutils'` al ejecutar `toPandas()` | PySpark 3.5 usa `distutils` y Python 3.12 lo eliminó; `setuptools` lo reemplaza | Ejecuta `cd ~/bigdata && make reparar-entorno`: instala `requirements-dev.txt`, que incluye `setuptools`. Reinicia el kernel |
| `error: Your local changes to the following files would be overwritten by merge` al hacer `git pull` | Editaste un notebook que está dentro del repositorio | Trabaja siempre sobre la copia (sección 2). Para rescatar lo que ya escribiste: `cd ~/bigdata && cp curso/clase05/03_lab.ipynb ~/clase05_mis_notebooks/03_lab_recuperado.ipynb && git checkout -- curso/clase05/03_lab.ipynb && git pull`. Cambia `03_lab.ipynb` por el archivo que editaste |
| `AttributeError: module 'lib' has no attribute 'X509_V_FLAG_NOTIFY_POLICY'` al importar `snowflake.connector` | `cryptography` y `pyOpenSSL` quedaron en versiones incompatibles | Repite `cd ~/bigdata && .venv/bin/pip install -r requirements-dev.txt`: el archivo fija las dos versiones correctas |
| El kernel muere (`Kernel died`) o `OutOfMemoryError: Java heap space` | Se trajo demasiado al driver, o hay dos procesos grandes a la vez | Reinicia el kernel, cierra otros notebooks y no ejecutes `toPandas()` sobre datos crudos |
| Spark no arranca, se queda esperando o la Spark UI aparece en el puerto 4041 | Ya hay otro Spark abierto (otro notebook o una terminal) | Cierra el otro con `spark.stop()` o reiniciando su kernel (sección 4); el enlace que imprime la Celda 5 ya trae el puerto correcto |
| `NoCredentialsError` o `ExpiredToken` en la Celda 2 | No hay credenciales de AWS en esa terminal | En el Code Editor no hace falta ningún perfil; comprueba con `aws sts get-caller-identity`. Fuera del Code Editor define `AWS_PROFILE` |
| La descarga del archivo de enero se corta y queda `fhvhv_tripdata_2024-01.parquet.parcial` | La conexión se interrumpió | Borra el archivo `.parcial` de `~/datos_clase05/bronze/fhvhv/mes=2024-01/` y vuelve a ejecutar la celda |
| `Could not find connection 'default'` o `Failed to connect to DB` | Falta la conexión de Snowflake o la llave | Ejecuta `cd ~/bigdata && make snowflake-conexion`; es el target que crea la conexión por llave en `~/.snowflake/connections.toml` |
| `No se encontró la tabla BIGDATA.CONTROL.WATERMARK` (o `Insufficient privileges to operate on database 'BIGDATA'`) | La tabla de control la crea Terraform y todavía no la aplicaste: `ACCOUNTADMIN` no puede crear esquemas en `BIGDATA`, que es de `TERRAFORM_ROLE` | Ejecuta `cd ~/bigdata && git pull && make snowflake`, escribe `yes` y repite la celda ([detalle](../../docs/problemas.md#p-control-watermark)) |
| `Database 'CURSO' does not exist or not authorized` | No creaste la base `CURSO` en las clases 2 a 4, o usas otro rol | Cambia `SF_BASE` en la celda por una base que puedas usar, o avisa al instructor |
| La consulta de Snowflake tarda mucho más de lo esperado | Se quitó `USE_VECTORIZED_SCANNER = TRUE` del formato del stage | Déjala: sin ella Snowflake interpreta cada fila del Parquet como un valor semiestructurado |
| Una prueba del lab dice `PENDIENTE` aunque escribiste código | Quedó la línea `...  # TU CÓDIGO AQUÍ` | Reemplaza los tres puntos por tu código (el comentario puede quedarse) y ejecuta la celda de la función otra vez |
| Una prueba dice `REVISAR` y una pista | Tu código corre pero algo no coincide | Lee la pista, corrige la celda de la función, ejecútala y vuelve a ejecutar la celda de la prueba |
| Los ejercicios 2, 3 o 4 dicen `REVISAR  Primero resuelve el ejercicio 1` | La ingesta usa tu función de huella y esa todavía no dice `OK` | Resuelve y verifica el ejercicio 1 antes |
| Una prueba de ingesta dice `REVISAR  tu función falló con ...` y el error nombra a Snowflake (`Could not find connection`, `Failed to connect`, `Incorrect username or password`) | `watermark` no encuentra o no puede usar tu conexión | Comprueba la conexión con el comando de la sección 1; si tu conexión no se llama `default`, cambia `CONEXION_SNOWFLAKE` en la Celda 3 y ejecútala otra vez |
| La ingesta real del clima falla con `HTTP Error 429` o `URLError` | Open-Meteo limita las peticiones o no hay red | Espera un minuto y vuelve a ejecutar la celda; los registros de la tabla de control solo se escriben al terminar bien, así que repetir es seguro |
| La celda de datos reales imprime `No se ingesta ...: la tabla de control ya tiene ... registro(s)` | Ya la ejecutaste antes y la tabla de control recuerda esa ingesta | Es el comportamiento esperado. Para repetir desde cero ejecuta la celda de cierre, que borra los registros de práctica, y vuelve a la celda de datos reales |
| La descarga del archivo de viajes se corta o falla por falta de espacio | El archivo pesa unos 450 MiB y el modo de prueba lo descarga completo | Libera espacio (borra `~/datos_clase05/bronze_alumno/_crudo/prueba_fhvhv` y los archivos que ya no uses) y ejecuta la celda otra vez |

## 7. Después de la clase

Los notebooks no se entregan. Lo que sí queda es el código de tus tres funciones de ingesta: en la clase 6 el DAG de Airflow las llamará con el mes y el valor de `reprocesar`, y escribirán en `s3://<tu bucket>/bronze` en lugar de tu carpeta local. Guarda tu copia de `03_lab.ipynb` con tus soluciones. El lab de silver y gold, con la limpieza, los duplicados, las zonas, el gold y la sección «a mano primero», se hace en la clase 6 y está en `curso/clase06/lab_silver_gold.ipynb`; usa los lotes de clima que dejaste en `~/datos_clase05/bronze_alumno`.
