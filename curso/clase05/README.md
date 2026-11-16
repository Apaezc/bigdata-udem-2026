# Clase 5 · Transformar con Spark (mar 17 nov)

Pregunta de la clase: ¿cómo se pasa de 20 millones de viajes crudos a un resumen confiable? Es la primera clase en la que escribes código del pipeline. El trabajo se hace en tres notebooks que corren en el Code Editor de SageMaker, con Spark en local, y se termina en la terminal.

| Archivo | Para quién | Qué es |
|---|---|---|
| [`01_fundamentos.ipynb`](01_fundamentos.ipynb) | Estudiantes | Tus primeras líneas de Spark con los viajes de NYC: conoces las tres fuentes de datos y practicas ver, seleccionar, transformar, filtrar, agrupar y unir, además de depurar paso a paso. Cada sección termina con un «Pruébalo tú». |
| [`02_como_funciona.ipynb`](02_como_funciona.ipynb) | Estudiantes | Lo que Spark hace por dentro: driver, ejecutores y particiones; pandas frente a Spark frente a Snowflake; lazy y `explain()`; operaciones estrechas y anchas; *shuffle*; `broadcast`. |
| [`03_lab.ipynb`](03_lab.ipynb) | Estudiantes | El lab: tu pipeline de bronze a gold, con huecos `# TU CÓDIGO AQUÍ` y una prueba debajo de cada ejercicio que dice `OK`, `PENDIENTE` o `REVISAR`. Termina con el pipeline desde la terminal. |
| [`03_lab_solucion.ipynb`](03_lab_solucion.ipynb) | Instructor | El mismo lab con los siete ejercicios resueltos. |
| [`prueba_code_editor.md`](prueba_code_editor.md) | Autor | Guion para probar los tres notebooks en un Code Editor real antes de la clase. |

Los datos de la clase son los de enero de 2024: 19 663 930 viajes FHVHV, las 265 zonas de la ciudad y el clima diario de Open-Meteo. El archivo de viajes lo lee el notebook desde tu propio bucket `bigdata-lake-<CUENTA>-us-east-2` y lo guarda una sola vez en `~/datos_clase05`, fuera del repositorio, para que nunca llegue a un commit.

## 1. Instalar (una sola vez)

Necesitas haber terminado la [guía](../../docs/guia.md): el repositorio en `~/bigdata` con su `.venv`, tu lake con el bronze de enero y la conexión a Snowflake llamada `default`. Desde una terminal del Code Editor:

```bash
cd ~/bigdata && .venv/bin/pip install -r requirements-dev.txt
```

Entrada: ese comando. Salida esperada: unos minutos de descargas y, al final, una línea que empieza con `Successfully installed` y lista los paquetes nuevos (`pandas`, `pyarrow`, `snowflake-connector-python`, `ipykernel`, `setuptools`...). Si ya estaban instalados, dice `Requirement already satisfied`.

Después registra el entorno del proyecto como un kernel de Jupyter con nombre propio:

```bash
cd ~/bigdata && .venv/bin/python -m ipykernel install --user --name bigdata --display-name "Python (bigdata)"
```

Salida esperada: `Installed kernelspec bigdata in ...`. Un kernel es el programa Python que ejecuta las celdas del notebook; este lo registra con el Python de `~/bigdata/.venv`, que es el que tiene PySpark.

Comprueba tres cosas antes de la clase:

```bash
cd ~/bigdata && .venv/bin/python -c "import pandas, pyarrow, pyspark, snowflake.connector; print('librerias ok')"
java -version
cd ~/bigdata && .venv/bin/python -c "import snowflake.connector as s; c = s.connect(connection_name='default'); print(c.cursor().execute('select current_user()').fetchone()); c.close()"
```

Salida esperada: `librerias ok`; una versión de Java que empieza por `openjdk version "17`; y una tupla con tu usuario de Snowflake, por ejemplo `('TU_USUARIO',)`. Si `java -version` no encuentra Java, no te preocupes todavía: la primera celda de cada notebook busca el Java que instaló `make setup` en `~/.local/opt/java17`.

## 2. Trabajar sobre una copia del notebook

No edites los notebooks que vienen en el repositorio. Si los modificas y después el instructor sube una corrección, `git pull` se detiene con un conflicto. En lugar de eso, copia los notebooks a una carpeta tuya, fuera del repositorio, y trabaja ahí. Desde una terminal del Code Editor:

```bash
mkdir -p ~/clase05_mis_notebooks && cp ~/bigdata/curso/clase05/01_fundamentos.ipynb ~/bigdata/curso/clase05/02_como_funciona.ipynb ~/bigdata/curso/clase05/03_lab.ipynb ~/clase05_mis_notebooks/
```

Salida esperada: ninguna (si no hay error, la copia salió bien). Comprueba con `ls ~/clase05_mis_notebooks`: deben aparecer los tres archivos. No copies `03_lab_solucion.ipynb`: es la versión del instructor. Los notebooks funcionan desde cualquier carpeta; encuentran el repositorio en `~/bigdata` por sí solos.

## 3. Abrir un notebook y elegir el kernel

1. En el Code Editor abre el explorador de archivos y entra a `clase05_mis_notebooks/`.
2. Abre `01_fundamentos.ipynb`. Si el editor ofrece instalar la extensión de Jupyter, acéptala.
3. Arriba a la derecha pulsa **Select Kernel**, elige **Jupyter Kernel** y después **Python (bigdata)**. Si no aparece, elige el intérprete `~/bigdata/.venv/bin/python`.
4. Ejecuta la primera celda de código (sección 0.1). Debe imprimir una ruta de Python que contiene `.venv` y la versión de Java. Si imprime `AVISO: este kernel no es el del proyecto`, el kernel está mal elegido: vuelve al paso 3.

**Nunca elijas un kernel que se llame `Glue PySpark`, `Glue Spark` ni `SparkMagic`.** El Code Editor los ofrece en la lista, pero abren una sesión de AWS Glue en la nube, y esa sesión cobra mientras está abierta. Los notebooks de esta clase usan Spark en tu propia máquina, con el kernel **Python (bigdata)**, y no cuestan nada.

Ejecuta las celdas en orden con Shift+Enter.

## 4. Cerrar Spark antes de la terminal y entre notebooks

En esta máquina solo cabe un proceso de Spark a la vez. Por eso cada notebook termina con una celda `spark.stop()` y esa celda se ejecuta antes de abrir el siguiente notebook y antes de usar la terminal para `make test`, `make run-local` o `pipeline.run`. Si olvidas cerrar Spark, el otro proceso se queda esperando o falla por memoria; la solución es ejecutar la celda de cierre o reiniciar el kernel del notebook que lo tenía abierto.

## 5. Qué debes ver, notebook por notebook

Las cifras no están escritas aquí a propósito: las produce cada celda en tu máquina.

| Notebook y sección | Qué debe pasar |
|---|---|
| **01** · 0 Preparación | Imprime tu cuenta y tu bucket, trae el archivo de enero una sola vez (451 MiB), las zonas y el clima, arranca Spark y muestra `defaultParallelism` y el enlace de la Spark UI. |
| **01** · 1 Conoce tus datos | El esquema de los viajes (24 columnas), un viaje completo en vertical, las 265 zonas como texto, y el clima aplanado a 31 filas. |
| **01** · 2 a 11 | Cada sección imprime tablas pequeñas y cifras; cada «Pruébalo tú» se resuelve con una o dos líneas. La sección 8 termina diciendo que el `join` conservó todos los viajes y que, con una zona repetida, las filas de más son exactamente los viajes de esa zona. |
| **01** · 12 Depurar | Un recorrido por pasos con nombre sobre una muestra y después sobre todo enero, y tres errores que arreglas hasta que `comprobar` dice `OK`. |
| **02** · 1 Arquitectura | El número de particiones del archivo y una tabla con las filas de cada una, cuya suma es 19 663 930. |
| **02** · 2 Pandas, Spark y Snowflake | Tiempos y memoria de los tres, y dos líneas `pandas vs ...: COINCIDEN`. |
| **02** · 3 y 4 | Las celdas de «definir» tardan milisegundos; el `count()` tarda lo que cuesta leer el archivo; el plan muestra `ReadSchema` y `PushedFilters`; un plan sin `Exchange` y otro con `Exchange`; `HashAggregate` parcial y final; `Exchange SinglePartition` en la ventana sin partición. |
| **02** · 5 Broadcast | `SortMergeJoin` frente a `BroadcastHashJoin`, dos tiempos y `Resultados iguales: True`. |
| **03** · 1 a 2 | Explicación del diseño de bronze y la muestra de 1 % de enero. |
| **03** · ejercicios 1a a 5b | Cada prueba imprime `OK`, `PENDIENTE` o `REVISAR` con una pista. Con el enunciado sin resolver todas dicen `PENDIENTE`; con todo resuelto, todas dicen `OK`. |
| **03** · cadena completa | `Tu gold es equivalente al del pipeline del repo: True` y una tabla de lluvia y viajes por día. |
| **03** · «A mano primero» | Los comandos de la terminal con su salida esperada, para correrlos después de cerrar Spark. |

## 6. Errores comunes

| Lo que ves | Causa | Cómo evitarlo o arreglarlo |
|---|---|---|
| `Java gateway process exited before sending its port number` o `JAVA_HOME is not set`, o la celda 0.1 imprime `AVISO: no se encontró Java` | El kernel del notebook no lee `~/.bashrc` y no ve el Java que instaló `make setup` | La celda 0.1 busca Java en `~/.local/opt/java17` y define `JAVA_HOME` sola. Si aun así falla, ejecuta `ls ~/.local/opt/java17/bin/java` en una terminal; si no existe, ejecuta `cd ~/bigdata && make setup` y reinicia el kernel |
| `ModuleNotFoundError: No module named 'pandas'` (o `pyarrow`, `snowflake`) | El notebook corre con otro kernel, no con el del proyecto | Elige el kernel **Python (bigdata)** (sección 3 de este README) y reinicia el kernel |
| Aparece una sesión de Glue, un mensaje de *Glue Session* o un cargo de AWS Glue | Elegiste un kernel `Glue PySpark`, `Glue Spark` o `SparkMagic` | Cierra esa sesión, elige **Python (bigdata)** y reinicia. Esos kernels abren una sesión de Glue que cobra |
| `No active warehouse selected in the current session` o `Warehouse: None` en la sección 2 de `02_como_funciona` | La conexión de Snowflake por llave no trae warehouse | La celda ejecuta `USE ROLE ACCOUNTADMIN` y `USE WAREHOUSE COMPUTE_WH`. Si el warehouse de tu cuenta se llama distinto, cambia ese nombre en la celda |
| La Spark UI abre sin estilos (texto plano) o dice `Unsupported URL path` | Spark no conocía el prefijo del proxy del Code Editor, o abriste la raíz del enlace, que redirige mal detrás del proxy | Usa el enlace que imprime la celda 0.5, que termina en `/jobs/`. Esa celda define `PYSPARK_SUBMIT_ARGS` con `spark.ui.proxyBase` **antes** de arrancar Spark; si Spark ya estaba encendido de antes, reinicia el kernel y ejecuta la celda desde el principio |
| `ModuleNotFoundError: No module named 'distutils'` al ejecutar `toPandas()` | PySpark 3.5 usa `distutils` y Python 3.12 lo eliminó; `setuptools` lo reemplaza | Ejecuta `cd ~/bigdata && .venv/bin/pip install -r requirements-dev.txt`: el archivo incluye `setuptools`. Reinicia el kernel |
| `bad interpreter` o `no such file or directory` al ejecutar `.venv/bin/pytest` | El comando `pytest` del entorno tiene escrita la ruta de un Python que ya no existe | Ejecuta las pruebas con `cd ~/bigdata && .venv/bin/python -m pytest tests/test_silver.py`, que usa el Python correcto |
| `error: Your local changes to the following files would be overwritten by merge` al hacer `git pull` | Editaste un notebook que está dentro del repositorio | Trabaja siempre sobre la copia (sección 2). Para rescatar lo que ya escribiste: `cd ~/bigdata && cp curso/clase05/03_lab.ipynb ~/clase05_mis_notebooks/03_lab_recuperado.ipynb && git checkout -- curso/clase05/03_lab.ipynb && git pull`. Cambia `03_lab.ipynb` por el archivo que editaste |
| `AttributeError: module 'lib' has no attribute 'X509_V_FLAG_NOTIFY_POLICY'` al importar `snowflake.connector` | `cryptography` y `pyOpenSSL` quedaron en versiones incompatibles | Repite `cd ~/bigdata && .venv/bin/pip install -r requirements-dev.txt`: el archivo fija las dos versiones correctas |
| El kernel muere (`Kernel died`) o `OutOfMemoryError: Java heap space` | Se trajo demasiado al driver, o hay dos procesos grandes a la vez | Reinicia el kernel, cierra otros notebooks y no ejecutes `toPandas()` sobre datos crudos; en el lab usa siempre la muestra |
| Spark no arranca, se queda esperando o la Spark UI aparece en el puerto 4041 | Ya hay otro Spark abierto (otro notebook o una terminal) | Cierra el otro con `spark.stop()` o reiniciando su kernel (sección 4); el enlace que imprime la celda 0.5 ya trae el puerto correcto |
| `NoCredentialsError` o `ExpiredToken` en la celda 0.2 | No hay credenciales de AWS en esa terminal | En el Code Editor no hace falta ningún perfil; comprueba con `aws sts get-caller-identity`. Fuera del Code Editor define `AWS_PROFILE` |
| La descarga del archivo de enero se corta y queda `fhvhv_tripdata_2024-01.parquet.parcial` | La conexión se interrumpió | Borra el archivo `.parcial` de `~/datos_clase05/bronze/fhvhv/mes=2024-01/` y vuelve a ejecutar la celda |
| `Could not find connection 'default'` o `Failed to connect to DB` | Falta la conexión de Snowflake o la llave | Ejecuta `cd ~/bigdata && make snowflake-conexion`; es el target que crea la conexión por llave en `~/.snowflake/connections.toml` |
| `Database 'CURSO' does not exist or not authorized` | No creaste la base `CURSO` en las clases 2 a 4, o usas otro rol | Cambia `SF_BASE` en la celda por una base que puedas usar, o avisa al instructor |
| La consulta de Snowflake tarda mucho más de lo esperado | Se quitó `USE_VECTORIZED_SCANNER = TRUE` del formato del stage | Déjala: sin ella Snowflake interpreta cada fila del Parquet como un valor semiestructurado |
| Una prueba del lab dice `PENDIENTE` aunque escribiste código | Quedó la línea `...  # TU CÓDIGO AQUÍ` | Reemplaza los tres puntos por tu código (el comentario puede quedarse) y ejecuta la celda de la función otra vez |
| Una prueba dice `REVISAR` y una pista | Tu código corre pero algo no coincide | Lee la pista, corrige la celda de la función, ejecútala y vuelve a ejecutar la celda de la prueba |
| El ejercicio 1b dice `REVISAR  Primero resuelve el ejercicio 1a` | La ingesta usa tu función de huella y esa todavía no dice `OK` | Resuelve y verifica el 1a antes |
| El ejercicio 1b falla con `HTTP Error 429` o `URLError` | Open-Meteo limita las peticiones o no hay red | Espera un minuto y vuelve a ejecutar la celda de la prueba |
| `ModuleNotFoundError: No module named 'pipeline'` al correr un comando de la terminal | Falta `PYTHONPATH=src` | Escríbelo antes de `.venv/bin/python`, o usa `make` |
| `No hay muestra en ... y falta LAKE_BUCKET` o `No hay ningún lote completo` al correr el pipeline en local | La muestra todavía no está descargada o no se generó con el diseño de lotes | Agrega `--lake-bucket <tu bucket>` al comando a mano (con `make` se calcula solo). Si dice que no hay lote, pide al instructor que genere la muestra (`make muestra`) |
| `No rule to make target 'run-local'` | Ejecutaste `make` fuera de `~/bigdata` | Empieza siempre con `cd ~/bigdata &&` |

## 7. Después de la clase

Los notebooks no se entregan. Lo que sí queda es el código de tus funciones del lab: en la clase 6 las copiarás a `src/pipeline/` y las ejecutará Airflow. Guarda tu copia de `03_lab.ipynb` con tus soluciones.
