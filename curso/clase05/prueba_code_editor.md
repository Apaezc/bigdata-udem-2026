# Guion de prueba de la clase 5 en el Code Editor

Para el autor. La clase 5 son tres notebooks: `01_fundamentos`, `02_como_funciona` y `03_lab` (con su `03_lab_solucion`), y el lab ya no es el de silver y gold sino el de **ingesta a bronze** de las tres fuentes, con la tabla de control en Snowflake. El lab anterior de silver y gold se movió a `curso/clase06/lab_silver_gold.ipynb` (y `lab_silver_gold_solucion.ipynb`); su prueba está en la sección 5 de este guion. Este guion recorre los notebooks en el Code Editor, en orden, con la salida esperada de cada paso y lo que debes pegarme al final. Hazlo primero con los notebooks de estudiante y al final con `03_lab_solucion.ipynb`.

## Qué se probó ya, y dónde

Todo el código de los tres notebooks se ejecutó en un Mac de 32 GB con Python 3.12, PySpark 3.5.6 y Java 17, con un kernel de Jupyter real. Sirve como prueba de que el código y las pruebas del lab son correctos, y no como medida de tiempos del Code Editor: no compares tiempos uno a uno.

| Qué | Resultado en el Mac |
|---|---|
| Los cuatro `.ipynb` son JSON válido (`nbformat`), sin salidas guardadas, con la sintaxis de todas las celdas correcta y sin nombres sin definir (`ruff` con las reglas `F`) | Correcto |
| `01_fundamentos` ejecutado completo con un kernel real | Sin errores. Las salidas coinciden con las tablas del texto (primer viaje de enero, 265 zonas, 31 días de clima, `Llaves repetidas en zonas: 0`, `Las filas de más son exactamente los viajes de JFK: True`, SQL y DataFrames con 0 filas de diferencia). Las soluciones plegables de los «Pruébalo tú» se ejecutaron todas sin error, y con las tres correcciones de la sección de depuración los tres `comprobar` dicen `OK` |
| `02_como_funciona` ejecutado completo, con Snowflake (`connection_name="bigdata-test"`, `COMPUTE_WH`, base `CURSO_PRUEBA_C5`, borrada al final) | Sin errores. Los tres motores dan 8 006 grupos, 19 663 930 viajes e ingreso 471 132 933.49 y dos líneas `COINCIDEN`; un grupo de 1 048 576 filas con 24 columnas ocupa 526 MB en pandas; `Exchange SinglePartition` en la ventana sin partición; `SortMergeJoin` frente a `BroadcastHashJoin` con `Resultados iguales: True` |
| `03_lab` (enunciado) | Cuatro líneas `PENDIENTE` (E1 a E4); la celda de datos reales dice que todavía no y no hay ningún error |
| `03_lab_solucion` | Cuatro líneas `OK`. Las pruebas usan archivos pequeños (100 viajes, 12 zonas, 31 días de clima de `tests/data`), la tabla `prueba_*` y el mes `2099-01`, y borran sus registros al terminar. La ejecución real descarga el clima de enero (3 llamadas: ingesta, «ya hay registro», reproceso con lote nuevo), las 265 zonas (2 llamadas) y los viajes de enero en modo de prueba (descarga el archivo de 450.9 MiB, 19 s en el Mac, y escribe 1 000 filas): la tabla de control queda con 2, 1 y 1 registros, y la celda de cierre los borra |
| Respuestas malas del lab | Sin `coalesce` del nulo, E1 dice `REVISAR` con la pista de `(«a», nulo)` y E2 a E4 piden resolver E1. Una ingesta que ignora la tabla de control dice `REVISAR  La segunda llamada (reprocesar=False) volvió a descargar`; con el crudo sin la carpeta del lote, `REVISAR  El crudo debe guardarse en ...`; sin registrar, `REVISAR  Después de la primera llamada la tabla de control debe tener 1 registro ... y tiene 0`; sin el marcador, `REVISAR  El lote debe estar completo: falta el marcador _LOTE_COMPLETO`; con una columna de más, `REVISAR  Las columnas deben ser ...`; sin recortar con `limite_filas`, `REVISAR  El lote debe tener 40 filas y tiene 100`; sin la guarda, `REVISAR  La guarda debe rechazar limite_filas con la tabla real` |
| Tabla de control con Snowflake real (`connection_name="bigdata-test"`, rol `ACCOUNTADMIN`, `COMPUTE_WH`) | `consultar_watermark` de un mes inexistente da `[]`; el registro de `demo` aparece como JSON con siete campos; un segundo con `reprocesar=True` aparece después del primero; los borrados solo aceptan tablas `demo` o `prueba*`. El esquema y la tabla los crea Terraform (ver «Pendiente» más abajo) |
| Pruebas de `watermark.py` sin red (`tests/test_watermark.py`) | Diez pruebas con un conector falso: rol y warehouse sin DDL, consulta parametrizada y ordenada por `INICIO`, JSON con siete campos, inicio en UTC sin zona, nombre de conexión configurable, conexión cerrada ante errores, mensaje claro cuando falta la tabla o el permiso, borrado solo de tablas de prueba |
| Lab de la clase 6 (`lab_silver_gold_solucion`) con el bronze que dejó el lab de ingesta | Cinco líneas `OK` (E1, E2, E3, E4a y E4b); la cadena lee los dos lotes del clima de `prueba_clima` (62 filas, 31 sin repetidos por la huella) y da `Tu gold es equivalente al del pipeline del repo: True`. El enunciado da cinco líneas `PENDIENTE` sin errores |

**Lo que solo se puede probar en el Code Editor** y este guion debe cubrir: el kernel **Python (bigdata)** del `.venv` (sin los kernels de Glue), el Java de `~/.local/opt/java17`, las dos CPU y 7.6 GB de la instancia (el pico de pandas y el desempeño con `defaultParallelism` igual a 2), el enlace de la Spark UI detrás del proxy, la copia del archivo desde tu bucket, las rutas nuevas del lake (`bronze/_crudo/...`) en tu bucket real, Snowflake con `USE ROLE ACCOUNTADMIN` y `USE WAREHOUSE COMPUTE_WH`, **la creación del esquema y la tabla `BIGDATA.CONTROL.WATERMARK` con tu cuenta**, la descarga del archivo de viajes (450.9 MiB) desde las redes del Code Editor y el espacio en disco que deja el lab de ingesta, y la sección «A mano primero» del lab de la clase 6 (`pipeline.run`, `make`, `pytest`, `ruff`).

## 1. Preparar el Code Editor

1. Lleva al Code Editor la carpeta `curso/clase05/` y el archivo `requirements-dev.txt` de la rama `clase05-contenido` (haz `git pull` en `~/bigdata`, o sube los archivos por el explorador).
2. Abre una terminal y mira los recursos:

```bash
nproc
free -m
cd ~/bigdata && .venv/bin/python --version
java -version
```

Salida esperada: `2` (la instancia ml.t3.large tiene 2 vCPU), una fila `Mem:` con unos 8 GB, `Python 3.12.x` y `openjdk version "17...`. Si `.venv/bin/python --version` falla o dice otra versión, es el síntoma de la imagen actualizada: sigue con el paso 3, que lo recrea. **Pégame estas cuatro salidas.**

3. Repara el entorno (recrea el `.venv` con Python 3.12, instala las dependencias, registra el kernel y comprueba `snow`) y verifica las librerías. Es el mismo comando con el que empieza la clase, y el que hay que usar si SageMaker actualizó la imagen del Code Editor:

```bash
cd ~/bigdata && git pull && make reparar-entorno
/opt/conda/bin/python3 --version
cd ~/bigdata && .venv/bin/python -c "import pandas, pyarrow, pyspark, snowflake.connector; print('librerias ok')"
cd ~/bigdata && .venv/bin/python -c "import distutils; print('distutils ok')"
```

Salida esperada: al final de `make reparar-entorno`, `Entorno reparado: Python 3.12.x, snow OK`; la versión del Python de conda (puede ser 3.13: ya no importa, porque el `.venv` usa 3.12 con `uv`); `librerias ok` y `distutils ok`. **Pégame la salida de `make reparar-entorno` y la del Python de conda**: si el Code Editor volvió a cambiar de imagen, quiero saber con qué versión quedó y si `uv` seguía en `/opt/conda/bin/uv`. Si `snow` falló antes de reparar, anota el mensaje (`No module named 'snowflake.cli'`). Si el último falla con `No module named 'distutils'`, `setuptools` no se instaló: dímelo. Si el tercero falla con `X509_V_FLAG_NOTIFY_POLICY`, copia el error completo.

4. Comprueba la conexión de Snowflake y el warehouse:

```bash
cd ~/bigdata && .venv/bin/python -c "import snowflake.connector as s; c = s.connect(connection_name='default'); cur = c.cursor(); print(cur.execute('select current_user(), current_role(), current_warehouse()').fetchone()); c.close()"
```

Salida esperada: una tupla con tu usuario y tu rol; el warehouse puede salir `None`, porque la conexión por llave no lo trae y el notebook lo fija con `USE WAREHOUSE COMPUTE_WH`. Si tu warehouse se llama distinto, dímelo.

5. Haz las copias de trabajo, como lo hará un estudiante, y comprueba que el repositorio queda sin cambios:

```bash
mkdir -p ~/clase05_mis_notebooks && cp ~/bigdata/curso/clase05/01_fundamentos.ipynb ~/bigdata/curso/clase05/02_como_funciona.ipynb ~/bigdata/curso/clase05/03_lab.ipynb ~/clase05_mis_notebooks/
ls ~/clase05_mis_notebooks
cd ~/bigdata && git status --short curso/clase05
```

Salida esperada: los tres archivos listados y ningún cambio en `curso/clase05` después de trabajar. **Anota si los notebooks funcionan desde `~/clase05_mis_notebooks` (fuera del repositorio).**

6. En una segunda terminal deja corriendo el monitor de memoria durante todo el trabajo:

```bash
watch -n 5 'free -m | head -2; ps -eo rss,comm --sort=-rss | head -4'
```

## 2. `01_fundamentos.ipynb`

Abre la copia, elige el kernel **Python (bigdata)** (confirma que la lista también ofrece los kernels de Glue y que **no** los usas) y ejecuta celda por celda. Cada «Pruébalo tú» se puede dejar en blanco, o resolver con la solución plegable, para probar que funcionan.

| Celdas | Qué debes ver | Anota |
|---|---|---|
| 0.1 kernel y Java | Ruta con `.venv`, `Java: openjdk version "17...`, versiones de pandas, pyarrow y pyspark, sin `AVISO` | Si el editor ofreció instalar la extensión de Jupyter y si el kernel apareció en la lista |
| 0.2 bucket | `Tu bucket: bigdata-lake-<cuenta>-us-east-2` y `Acceso al bucket: correcto` | Si imprime `AVISO` |
| 0.3 descarga | `Descargado desde s3://bigdata-lake-.../bronze/_crudo/fhvhv/...` (o `.../bronze/fhvhv/mes=2024-01/...` si tu lake aún tiene el diseño anterior) con 450.9 MiB, las zonas y el clima de Open-Meteo. Si repites la celda: `Ya existe, no se descarga` | **De qué ruta del bucket bajó cada archivo** y los segundos |
| 0.5 Spark | Versión 3.5.6, `master local[*]`, driver `2g`, `defaultParallelism` y un enlace de Spark UI que termina en `/jobs/` | `defaultParallelism` (se espera 2) y **si el enlace abre la Spark UI con estilos** |
| 1 Conoce tus datos | El esquema de 24 columnas, un viaje completo (`HV0003`, zona 161, tarifa 45.61 como primer viaje de enero), las zonas como texto y el clima en 31 filas con `fecha`, `lluvia_mm` y `temperatura` | Si algún dato de las tablas del texto no coincide con lo que imprime |
| 2 a 7 | Salidas pequeñas y cifras; `LocationID` ordenado como texto (1, 10, 100...) y como número | Que ningún «Pruébalo tú» con solución falle |
| 8 join | `Llaves repetidas en zonas: 0`, el mismo número de viajes antes y después, y `Las filas de más son exactamente los viajes de JFK: True` | Los segundos de los `count()` |
| 9 SQL | `Filas que están en uno y no en el otro: 0` | |
| 10 y 11 | Cuatro «definir» en milésimas y un `count()`; los cuatro `toPandas`/`collect` con sus tiempos | **Los tiempos del `toPandas` de un millón de filas y del resumen** |
| 12 funciones de columna | Seis ejemplos con salidas pequeñas (`coalesce` y `lit`, `concat_ws`, `sha2`, `concat`, `broadcast`, `dropDuplicates` y `orderBy`), con su «Pruébalo tú» y solución | Que el plan del `broadcast` muestre `BroadcastHashJoin` y que ninguna solución plegable falle |
| 13 depurar | La traza de cada paso sobre la muestra, el mismo código sobre todo enero, el error de `PULocation` resumido y tres errores | Que los tres errores impriman el mensaje resumido y, tras corregirlos con las soluciones, que cada `comprobar` diga `OK` |
| Cierre | `Spark cerrado.` | |

## 3. `02_como_funciona.ipynb`

Ejecútalo después de cerrar Spark en el notebook 01. Es la versión reducida y ya probada del notebook anterior: se quitaron los archivos pequeños y las claves desbalanceadas (pasan a la clase 7).

| Celdas | Qué debes ver | Anota |
|---|---|---|
| 0 preparación | Igual que en el 01 | Segundos de arranque de Spark |
| 1 particiones | Un número de particiones y una tabla de filas por partición cuya suma es 19 663 930 | Número de particiones |
| 2.1 pandas | Tres tiempos, DataFrame de unos cientos de MB y pico de memoria | Los tres tiempos y el pico: **es la celda que más riesgo tiene de matar el kernel en 8 GB** |
| 2.2 el año completo | La estimación del año con las 3 columnas de la pregunta (unos 32 GB) y las de mes y año con las 24 columnas | Las tres estimaciones |
| 2.3 Spark | Dos tiempos (SQL y DataFrame) y el mismo número de grupos (8 006) | Los dos tiempos |
| 2.4 Snowflake | Rol `ACCOUNTADMIN`, warehouse `COMPUTE_WH`, `SELECT 1`, el archivo en el stage, el tiempo de la consulta y el ID | Los tiempos y si el warehouse arrancó de cero |
| 2.5 comparar | Tabla con 8 006 grupos, 19 663 930 viajes e ingreso 471 132 933.49, y dos líneas `COINCIDEN` | La tabla completa |
| 2.6 | La tabla de «cuándo conviene cada uno» | Frases que no te gusten |
| 3 lazy y plan | Cuatro «definir» de milisegundos y un `count()`; en el plan, `ReadSchema` con 2 columnas y `PushedFilters` con `EqualTo(PULocationID,132)` | Si el resumen de `FileScan` se imprime bien |
| 4.1 a 4.3 | Sin `Exchange` en la estrecha; con `Exchange hashpartitioning` en la ancha; `HashAggregate` parcial y final; la tabla de etapas | La tabla de etapas y si la API de la Spark UI respondió |
| 4.4 | `Exchange SinglePartition` en la ventana sin partición y `hashpartitioning` en la otra, con dos tiempos; los dos `toPandas` | Los tiempos |
| 5 broadcast | `SortMergeJoin` y `BroadcastHashJoin`, dos tiempos, `Resultados iguales: True`, umbral restaurado | Los dos tiempos |
| Cierre | `Spark cerrado.` | |

## 4. `03_lab.ipynb` (ingesta a bronze, enunciado) y `03_lab_solucion.ipynb`

1. Aplica Terraform y comprueba, en una terminal, que la conexión ve la tabla de control (`cd ~/bigdata && git pull && make snowflake`, y confirma el plan con `yes`):

```bash
cd ~/bigdata && .venv/bin/python -c "import snowflake.connector as s; c = s.connect(connection_name='default'); cur = c.cursor(); cur.execute('USE ROLE ACCOUNTADMIN'); cur.execute('USE WAREHOUSE COMPUTE_WH'); cur.execute('SELECT COUNT(*) FROM BIGDATA.CONTROL.WATERMARK'); print('tabla CONTROL lista', cur.fetchone()); c.close()"
```

Salida esperada: `tabla CONTROL lista (0,)`. Si dice `does not exist or not authorized`, falta aplicar `make snowflake`; sin eso, la demostración de la sección 4 del lab y los ejercicios 2 a 4 fallan para todos los estudiantes.

2. En `03_lab.ipynb` ejecuta hasta el final sin resolver nada. Debes ver **cuatro líneas `PENDIENTE`** (E1, E2, E3 y E4), la celda de datos reales diciendo que todavía no, y ningún error rojo. Confirma que `inspect.getsource` funciona en el Code Editor: si alguna dice `OK` o `REVISAR` con el enunciado sin resolver, es lo primero que hay que mirar.
3. Ejecuta la sección 1 (consumir una fuente): las tres URL de febrero de 2024, el peso del archivo de viajes (`HEAD`), el clima de febrero que termina el 2024-02-29 y las zonas. **Anota** si el `HEAD` a CloudFront funciona desde el Code Editor.
4. Ejecuta la demostración de la sección 4 (tres celdas con la tabla `demo`): `Respuesta: '[]'`, el registro como JSON con siete campos, dos registros con `reprocesar=False` y luego `True`, y «Se borraron 2 registros de demo». **Anota los segundos de la primera celda** (crea esquema y tabla) y de cada llamada a Snowflake.
5. Abre `03_lab_solucion.ipynb` (la copia: cópiala ahora a `~/clase05_mis_notebooks/`) y ejecútalo completo. Debes ver cuatro líneas `OK`. La celda de datos reales imprime la ingesta del clima en tres llamadas, las zonas en dos y los viajes en modo de prueba (descarga 450.9 MiB y escribe 1 000 filas); lista los archivos de `bronze_alumno` (crudos por lote, lotes con `_LOTE_COMPLETO`) y la tabla de control (2, 1 y 1 registros); la celda de cierre los borra. **Anota los segundos de la descarga de viajes y del modo de prueba.**
6. Provoca un `REVISAR` a propósito en la solución y vuelve a ejecutar cada prueba:
   - En E1, reemplaza `F.coalesce(como_texto, F.lit(MARCADOR_NULO))` por `como_texto`: debe decir `REVISAR` y la pista sobre `(«a», nulo)`; E2 a E4 piden resolver E1.
   - En E2, cambia `if len(registros) > 0 and not reprocesar:` por `if False:`: debe decir `REVISAR  La segunda llamada (reprocesar=False) volvió a descargar`.
   - En E2, cambia `crudo = ruta_crudo_lote(base_bronze, tabla, id_lote, nombre, mes)` por `crudo = pio.ruta_crudo(base_bronze, tabla, nombre, mes)`: debe decir `REVISAR  El crudo debe guardarse en ...`.
   - En E3, quita la última línea de registro (`registrar_watermark`): debe decir `REVISAR  Después de la primera llamada la tabla de control debe tener 1 registro ...`.
   - En E4, quita la línea `original = original.limit(limite_filas)`: debe decir `REVISAR  El lote debe tener 40 filas y tiene 100`.
   Restaura cada cambio.
7. Abre Snowsight y mira `BIGDATA.CONTROL.WATERMARK` mientras la celda de datos reales corre: deben aparecer las filas de `prueba_clima`, `prueba_taxi_zones` y `prueba_fhvhv` y desaparecer al ejecutar la celda de cierre. Abre tu bucket y comprueba que **no** se escribió nada: el lab escribe en `~/datos_clase05/bronze_alumno`, no en S3.
8. Prueba la opción de S3 por separado, sin cambiar el lab: con Spark local no se puede leer `s3://` (esa ruta es para Glue), así que solo comprueba que `BRONZE_S3` imprime `s3://<tu bucket>/bronze`.

### Medición final (celda extra al final de cualquiera de los tres notebooks)

Añade una celda con este código y pégame su salida:

```python
print(json.dumps({k: round(v, 2) for k, v in TIEMPOS.items()}, indent=1, ensure_ascii=False))
```

y, en la terminal, `free -m` justo después.

## 5. El lab de la clase 6 y la sección «A mano primero»

El lab anterior de silver y gold se movió a `curso/clase06/lab_silver_gold.ipynb` y `lab_silver_gold_solucion.ipynb`. Sus ejercicios 1 a 3 (limpiar, duplicados, zonas) y 4a y 4b (gold) son los antiguos 2 a 5; los ejercicios de huella e ingesta del clima pasaron al lab de la clase 5. Lo único que cambió es lo que dependía de la clase 5: la huella de la cadena es `bronze.hash_fila` del pipeline, y el clima de la cadena sale de los lotes de `prueba_clima` que dejó el lab de ingesta en `~/datos_clase05/bronze_alumno` (si no existen, usa el clima de pruebas del repo). Ejecútalo después del lab de ingesta: el enunciado debe dar cinco líneas `PENDIENTE` y la solución cinco `OK` y `Tu gold es equivalente al del pipeline del repo: True`.

Con Spark ya cerrado en el notebook (y el kernel reiniciado si hace falta), la sección «A mano primero» de ese notebook corre estos comandos desde la terminal:

```bash
cd ~/bigdata && PYTHONPATH=src .venv/bin/python -m pipeline.run --step silver --env local --engine local --mes 2024-01 --lake-bucket <tu bucket>
cd ~/bigdata && PYTHONPATH=src .venv/bin/python -m pipeline.run --step gold --env local --engine local --mes 2024-01
cd ~/bigdata && make -n run-local STEP=silver MES=2024-01
cd ~/bigdata && make run-local STEP=silver MES=2024-01
cd ~/bigdata && .venv/bin/python -m pytest tests/test_silver.py
cd ~/bigdata && .venv/bin/ruff check src
cd ~/bigdata && make test
```

Salida esperada, en orden: las cuatro líneas de registro del paso silver (`Paso=silver`, `Lectura viajes`, `Limpieza ... -> ...` y `Calidad OK [silver]`); lo mismo para gold sin `Lectura`; `STEP=silver MES=2024-01 LIMITE= bash scripts/run-local.sh`; lo mismo que el primer comando precedido de `==> Pipeline local: ...`; `passed` de pytest; `All checks passed!` de ruff; y las tres etapas de `make test`. Usa `.venv/bin/python -m pytest` y no `.venv/bin/pytest`: el segundo tiene el shebang roto.

Anota: si el primer comando necesitó `--lake-bucket`, de dónde tomó la muestra local (tu bucket o el público, lo dice la línea `Muestra descargada`) y si bajó 50 archivos, si falló con `ModuleNotFoundError` sin `PYTHONPATH=src`, los segundos de cada comando y las cifras de la línea `Limpieza`.

## 6. Lo que quiero que mires con ojo crítico

1. El enlace de la Spark UI (`.../codeeditor/default/ports/4040/jobs/`) y el permiso `sagemaker:DescribeSpace` desde el kernel.
2. Que `inspect.getsource` funcione sobre las funciones definidas en una celda del Code Editor: de eso depende que `PENDIENTE` aparezca (en el lab de ingesta, en las cuatro funciones).
3. Que `explain()` se capture con `redirect_stdout` y que la línea del `FileScan` se resuma bien.
4. La lectura de etapas por la API de la Spark UI desde Python (`/api/v1/applications/<id>/stages`).
5. Que la celda de pandas (pico de memoria) no mate el kernel en 8 GB.
6. El tiempo de Snowflake desde la cuenta de un estudiante, y que `CURSO` exista con el rol de la conexión `default`.
7. Que la descarga de la Celda 3 de los notebooks 01 y 02 encuentre el archivo en `bronze/_crudo/...` o en la ruta anterior, según cuál tenga tu lake.
8. La claridad del texto: marca cualquier frase que suene a ficha escolar o a promesa de cifra. En especial, la tabla de columnas de los viajes de `01_fundamentos` (¿el diccionario de datos está bien explicado?), la sección de depuración y las explicaciones previas a cada parte del lab de ingesta (consumir una fuente, crudo por lote, metadatos, tabla de control y `reprocesar`).
9. La función `watermark.py` desde tu cuenta: que, tras `make snowflake`, consulte e inserte en la tabla sin permisos extra, cuánto tarda cada llamada (cada una abre su propia conexión) y que el JSON del registro tenga las siete claves esperadas.
10. El diseño de `limite_filas` en `ingestar_viajes`: ¿la guarda que lo limita a tablas `prueba*` te parece suficiente, o prefieres otro mecanismo?

## Pendiente

- **El esquema `BIGDATA.CONTROL`.** Lo crea Terraform (`infra/snowflake/main.tf`, con la tabla `WATERMARK`) y da a `ACCOUNTADMIN` y `BIGDATA_DEV` permiso para consultar, insertar y borrar filas. Los estudiantes deben correr `cd ~/bigdata && git pull && make snowflake` al inicio de la clase 5; `watermark.py` ya no crea nada y, si falta la tabla, falla con un mensaje que lo dice.
- **La conexión desde Glue (clase 6).** En Glue no existe `~/.snowflake/connections.toml`: falta resolver el secreto y el conector para que las funciones de ingesta registren en la tabla de control cuando las llame el DAG.

## 7. Qué pegarme de vuelta

| Qué | De dónde |
|---|---|
| `nproc`, `free -m`, versión de Python y de Java | Paso 1.2 |
| Resultado de la instalación, del kernel, de `distutils` y de la conexión de Snowflake | Pasos 1.3 y 1.4 |
| Si trabajar desde la copia fuera del repositorio funcionó | Paso 1.5 |
| De qué ruta del bucket bajó cada archivo y los segundos | Celda 3 del 01 |
| Si el enlace de la Spark UI abrió con estilos | Celda 5 |
| Segundos de cada celda con `cronometro` y la tabla de 2.5 | Notebook 02 (o la celda extra de medición) |
| Pico de memoria del proceso Python y de Java en cada sección | Celda extra y monitor de la segunda terminal |
| Número de particiones, `defaultParallelism` y la tabla de etapas | Notebook 02, secciones 1 y 4 |
| Las cuatro líneas del lab de ingesta sin resolver, y las cuatro con la solución; los segundos de la descarga de viajes | Notebook 03 |
| La salida de la consulta de la sección 4.1 (esquema `CONTROL`) y los segundos de las llamadas a Snowflake | Terminal y sección 4 del lab |
| Las cinco líneas del lab de la clase 6 sin resolver y con la solución | `curso/clase06/lab_silver_gold*.ipynb` |
| Cualquier celda en rojo o `REVISAR` inesperado, con el traceback completo | Cualquier notebook |
| Salida de los comandos de la sección 5 de este guion (lab de la clase 6) y sus segundos | Terminal |
| Frases del texto que no te gusten | Notebooks |
