# Clase 5 · Transformar con Spark (mar 17 nov)

Pregunta de la clase: ¿cómo se pasa de 20 millones de viajes crudos a un resumen confiable? Es la primera clase en la que escribes código del pipeline. Todo el trabajo se hace en un notebook que corre en el Code Editor de SageMaker, con Spark en local.

| Archivo | Para quién | Qué es |
|---|---|---|
| [`clase05.ipynb`](clase05.ipynb) | Estudiantes | El notebook con huecos `# TU CÓDIGO AQUÍ` y una prueba debajo de cada ejercicio. |
| [`clase05_solucion.ipynb`](clase05_solucion.ipynb) | Instructor | El mismo notebook con los cinco ejercicios resueltos. |
| [`prueba_code_editor.md`](prueba_code_editor.md) | Autor | Guion para probar el notebook en un Code Editor real antes de la clase. |

Los datos de la clase son los de enero de 2024: 19 663 930 viajes FHVHV, las 265 zonas de la ciudad y el clima diario de Open-Meteo. El archivo de viajes lo lee el notebook desde tu propio bucket `bigdata-lake-<CUENTA>-us-east-2` y lo guarda una sola vez en `~/datos_clase05` (fuera del repositorio, para que nunca llegue a un commit).

## 1. Instalar (una sola vez)

Necesitas haber terminado la [guía](../../docs/guia.md): el repositorio en `~/bigdata` con su `.venv`, tu lake con el bronze de enero y la conexión a Snowflake llamada `default`. Desde una terminal del Code Editor:

```bash
cd ~/bigdata && .venv/bin/pip install -r requirements-dev.txt
```

Entrada: ese comando. Salida esperada: unos minutos de descargas y, al final, una línea que empieza con `Successfully installed` y lista los paquetes nuevos (`pandas`, `pyarrow`, `snowflake-connector-python`, `ipykernel`...). Si ya estaban instalados, dice `Requirement already satisfied`.

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

Salida esperada: `librerias ok`; una versión de Java que empieza por `openjdk version "17`; y una tupla con tu usuario de Snowflake, por ejemplo `('TU_USUARIO',)`.

## 2. Abrir el notebook y elegir el kernel

1. En el Code Editor abre el explorador de archivos y entra a `bigdata/curso/clase05/`.
2. Abre `clase05.ipynb`. Si el editor ofrece instalar la extensión de Jupyter, acéptala.
3. Arriba a la derecha pulsa **Select Kernel**, elige **Jupyter Kernel** y después **Python (bigdata)**. Si no aparece, elige el intérprete `~/bigdata/.venv/bin/python`.
4. Ejecuta la primera celda de código (sección 0.1). Debe imprimir una ruta de Python que contiene `.venv` y la versión de Java. Si imprime `AVISO: este kernel no es el del proyecto`, el kernel está mal elegido: vuelve al paso 3.

Ejecuta las celdas en orden con Shift+Enter. Solo puede haber un proceso de Spark a la vez: no abras el notebook dos veces ni ejecutes `make test` o `make run-local` mientras Spark siga encendido. La sección 6 trae una celda con `spark.stop()` y dice cuándo ejecutarla.

## 3. Qué debes ver, sección por sección

Las cifras no están escritas aquí a propósito: las produce cada celda en tu máquina.

| Sección | Qué debe pasar |
|---|---|
| 0 Preparación | Imprime tu cuenta y tu bucket (`bigdata-lake-<CUENTA>-us-east-2`), descarga el archivo de enero una sola vez (451 MiB), arranca Spark y muestra `defaultParallelism` y el enlace de la Spark UI. |
| 1 Arquitectura | El número de particiones del archivo y una tabla con las filas de cada una, cuya suma es 19 663 930. |
| 2 La misma pregunta | Tiempos y memoria de pandas, Spark y Snowflake, y tres líneas `pandas vs ...: COINCIDEN`. |
| 3 Lazy y plan | Las celdas de «definir» tardan milisegundos; el `count()` tarda lo que cuesta leer el archivo; `explain()` muestra `ReadSchema` y `PushedFilters`. |
| 4 Estrechas, anchas y lo que no escala | Un plan sin `Exchange` y otro con `Exchange`; `HashAggregate` parcial y final; `Exchange SinglePartition` en la ventana sin partición; el ranking de zonas con los aeropuertos; la comparación de archivos pequeños. |
| 5 Broadcast | `SortMergeJoin` frente a `BroadcastHashJoin`, dos tiempos y `Resultados iguales: True`. |
| 6 Lab | Cada prueba imprime `OK`, `PENDIENTE` o `REVISAR` con una pista. Con el enunciado sin resolver todas dicen `PENDIENTE`; con todo resuelto, todas dicen `OK`. |
| 7 A mano primero | Los comandos de la terminal y la salida esperada, para correrlos después de cerrar Spark. |

## 4. Errores comunes

| Lo que ves | Causa | Cómo evitarlo o arreglarlo |
|---|---|---|
| `ModuleNotFoundError: No module named 'pandas'` (o `pyarrow`, `snowflake`) | El notebook corre con otro kernel, no con el del proyecto | Elige el kernel **Python (bigdata)** (sección 2 de este README) y reinicia el kernel |
| `ModuleNotFoundError: No module named 'pipeline'` | La celda 0.2 no encontró la raíz del repositorio (el notebook se abrió desde fuera de `~/bigdata`) | Abre el notebook desde `~/bigdata/curso/clase05/`; la celda busca `pyproject.toml` subiendo desde esa carpeta |
| `Java gateway process exited before sending its port number` o `JAVA_HOME is not set` | Spark no encuentra Java | Ejecuta `java -version` en una terminal; debe mostrar la versión 17. Si no, avisa al instructor |
| `AttributeError: module 'lib' has no attribute 'X509_V_FLAG_NOTIFY_POLICY'` al importar `snowflake.connector` | `cryptography` y `pyOpenSSL` quedaron en versiones incompatibles | Repite `cd ~/bigdata && .venv/bin/pip install -r requirements-dev.txt`: el archivo fija las dos versiones correctas |
| El kernel muere (`Kernel died`) en la celda de pandas o con `OutOfMemoryError: Java heap space` en Spark | Se trajo demasiado al driver, o hay dos procesos grandes a la vez | Reinicia el kernel, cierra otros notebooks y no ejecutes `toPandas()` sobre datos crudos; en la sección 6 usa siempre la muestra |
| Spark no arranca o la Spark UI aparece en el puerto 4041 | Ya hay otro Spark abierto (otro notebook o una terminal) | Cierra el otro con `spark.stop()` o reiniciando su kernel; el enlace que imprime la celda 0.5 ya trae el puerto correcto |
| La Spark UI no abre desde el enlace | La sesión de Spark ya se cerró, o el enlace del proxy está mal armado | Comprueba que Spark sigue vivo; si no abre, avisa al instructor y sigue: las cifras de las etapas también se imprimen desde Python |
| `NoCredentialsError` o `ExpiredToken` en la celda 0.2 | No hay credenciales de AWS en esa terminal | En el Code Editor no hace falta ningún perfil; comprueba con `aws sts get-caller-identity`. Fuera del Code Editor define `AWS_PROFILE` |
| La descarga del archivo de enero se corta y queda `fhvhv_tripdata_2024-01.parquet.parcial` | La conexión se interrumpió | Borra el archivo `.parcial` de `~/datos_clase05/bronze/fhvhv/mes=2024-01/` y vuelve a ejecutar la celda |
| `Could not find connection 'default'` o `Failed to connect to DB` | Falta la conexión de Snowflake o la llave | Ejecuta `cd ~/bigdata && make snowflake-conexion`; es el target que crea la conexión por llave en `~/.snowflake/connections.toml` |
| `Tu conexión no trae warehouse` | La conexión `default` no tiene warehouse | Ejecuta `sf('USE WAREHOUSE <nombre>')` con el de tu cuenta y vuelve a correr la celda |
| `Database 'CURSO' does not exist or not authorized` | No creaste la base `CURSO` en las clases 2 a 4, o usas otro rol | Cambia `SF_BASE` en la celda por una base que puedas usar, o avisa al instructor |
| La consulta de Snowflake tarda mucho más de lo esperado | Se quitó `USE_VECTORIZED_SCANNER = TRUE` del formato del stage | Déjala: sin ella Snowflake interpreta cada fila del Parquet como un valor semiestructurado |
| Una prueba del lab dice `PENDIENTE` aunque escribiste código | Quedó la línea `...  # TU CÓDIGO AQUÍ` | Reemplaza los tres puntos por tu código (el comentario puede quedarse) y ejecuta la celda de la función otra vez |
| Una prueba dice `REVISAR` y una pista | Tu código corre pero algo no coincide | Lee la pista, corrige la celda de la función, ejecútala y vuelve a ejecutar la celda de la prueba |
| E1 falla con `HTTP Error 429` o `URLError` | Open-Meteo limita las peticiones o no hay red | Espera un minuto y vuelve a ejecutar la celda de la prueba |
| `ModuleNotFoundError: No module named 'pipeline'` al correr el comando de la sección 7 | Falta `PYTHONPATH=src` | Escríbelo antes de `.venv/bin/python`, o usa `make` |
| `No rule to make target 'run-local'` | Ejecutaste `make` fuera de `~/bigdata` | Empieza siempre con `cd ~/bigdata &&` |

## 5. Después de la clase

El notebook no se entrega. Lo que sí queda es el código de tus cinco funciones: en la clase 6 las copiarás a `src/pipeline/` y las ejecutará Airflow. Guarda el notebook con tus soluciones.
