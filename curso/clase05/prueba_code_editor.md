# Guion de prueba de la clase 5 en el Code Editor

Para el autor. La clase 5 son tres notebooks: `01_fundamentos`, `02_como_funciona` y `03_lab` (con su `03_lab_solucion`). Este guion los recorre en el Code Editor, en orden, con la salida esperada de cada paso y lo que debes pegarme al final. Hazlo primero con los notebooks de estudiante y al final con `03_lab_solucion.ipynb`.

## Qué se probó ya, y dónde

Todo el código de los tres notebooks se ejecutó en un Mac de 32 GB con Python 3.12, PySpark 3.5.6 y Java 17, con un kernel de Jupyter real. Sirve como prueba de que el código y las pruebas del lab son correctos, y no como medida de tiempos del Code Editor: no compares tiempos uno a uno.

| Qué | Resultado en el Mac |
|---|---|
| Los cuatro `.ipynb` son JSON válido (`nbformat`), sin salidas guardadas, con la sintaxis de todas las celdas correcta y sin nombres sin definir (`ruff` con las reglas `F`) | Correcto |
| `01_fundamentos` ejecutado completo con un kernel real | Sin errores. Las salidas coinciden con las tablas del texto (primer viaje de enero, 265 zonas, 31 días de clima, `Llaves repetidas en zonas: 0`, `Las filas de más son exactamente los viajes de JFK: True`, SQL y DataFrames con 0 filas de diferencia). Las soluciones plegables de los «Pruébalo tú» se ejecutaron todas sin error, y con las tres correcciones de la sección de depuración los tres `comprobar` dicen `OK` |
| `02_como_funciona` ejecutado completo, con Snowflake (`connection_name="bigdata-test"`, `COMPUTE_WH`, base `CURSO_PRUEBA_C5`, borrada al final) | Sin errores. Los tres motores dan 8 006 grupos, 19 663 930 viajes e ingreso 471 132 933.49 y dos líneas `COINCIDEN`; un grupo de 1 048 576 filas con 24 columnas ocupa 526 MB en pandas; `Exchange SinglePartition` en la ventana sin partición; `SortMergeJoin` frente a `BroadcastHashJoin` con `Resultados iguales: True` |
| `03_lab` (enunciado) | Siete líneas `PENDIENTE` (1a, 1b, 2, 3, 4, 5a y 5b) y las celdas que dependen de ellas imprimen su aviso, sin ningún error |
| `03_lab_solucion` | Siete líneas `OK`; la ingesta real descarga una sola vez y deja un crudo y dos lotes con su marcador `_LOTE_COMPLETO` (62 filas con dos lotes); la cadena completa da `Tu gold es equivalente al del pipeline del repo: True` (14 499 filas y 197 208 viajes sobre la muestra); correlación diaria lluvia-viajes de la muestra 0.132 |
| Pruebas del lab con respuestas malas | Sin `coalesce` del nulo, 1a dice `REVISAR` con la pista del nulo y 1b dice que primero hay que resolver 1a; con `crudo_ya_existe = False`, 1b dice `REVISAR  La segunda ejecución volvió a llamar a la red`; con la huella calculada con menos columnas, 1b dice `REVISAR` por la huella; sin `F.broadcast`, 4 dice `REVISAR  El plan no usa BroadcastHashJoin`; con `F.avg` de promedios, 5b dice `REVISAR` con la cuenta de 1.2. El ejercicio 3 con `row_number()` también da `OK` |
| La huella frente a su definición | La prueba 1a recalcula la huella con `hashlib` (texto, nulo como `<nulo>`, unir con `||`, SHA-256) y la compara con la columna de Spark y con `bronze.hash_fila` del pipeline; la 1b la recalcula sobre las 31 filas del lote real de Open-Meteo |
| Con el gold del pipeline | Sin filas sin pareja, con los mismos viajes y la misma lluvia; en 100 de 14 499 filas un monto difiere en el último decimal por el orden de la suma (por eso la comparación usa una tolerancia de 0.011) |


**Lo que solo se puede probar en el Code Editor** y este guion debe cubrir: el kernel **Python (bigdata)** del `.venv` (sin los kernels de Glue), el Java de `~/.local/opt/java17`, las dos CPU y 7.6 GB de la instancia (el pico de pandas y el desempeño con `defaultParallelism` igual a 2), el enlace de la Spark UI detrás del proxy, la copia del archivo desde tu bucket, las rutas nuevas del lake (`bronze/_crudo/...`) en tu bucket real, Snowflake con `USE ROLE ACCOUNTADMIN` y `USE WAREHOUSE COMPUTE_WH`, y la sección «A mano primero» (`pipeline.run`, `make`, `pytest`, `ruff`).

## 1. Preparar el Code Editor

1. Lleva al Code Editor la carpeta `curso/clase05/` y el archivo `requirements-dev.txt` de la rama `clase05-contenido` (haz `git pull` en `~/bigdata`, o sube los archivos por el explorador).
2. Abre una terminal y mira los recursos:

```bash
nproc
free -m
cd ~/bigdata && .venv/bin/python --version
java -version
```

Salida esperada: `2` (la instancia ml.t3.large tiene 2 vCPU), una fila `Mem:` con unos 8 GB, `Python 3.12.x` y `openjdk version "17...`. **Pégame estas cuatro salidas.**

3. Instala y registra el kernel:

```bash
cd ~/bigdata && .venv/bin/pip install -r requirements-dev.txt
cd ~/bigdata && .venv/bin/python -m ipykernel install --user --name bigdata --display-name "Python (bigdata)"
cd ~/bigdata && .venv/bin/python -c "import pandas, pyarrow, pyspark, snowflake.connector; print('librerias ok')"
cd ~/bigdata && .venv/bin/python -c "import distutils; print('distutils ok')"
```

Salida esperada: `Successfully installed ...` (o `Requirement already satisfied`), `Installed kernelspec bigdata in ...`, `librerias ok` y `distutils ok`. Si el último falla con `No module named 'distutils'`, `setuptools` no se instaló: dímelo. Si el tercero falla con `X509_V_FLAG_NOTIFY_POLICY`, copia el error completo.

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
| 12 depurar | La traza de cada paso sobre la muestra, el mismo código sobre todo enero, el error de `PULocation` resumido y tres errores | Que los tres errores impriman el mensaje resumido y, tras corregirlos con las soluciones, que cada `comprobar` diga `OK` |
| Cierre | `Spark cerrado.` | |

## 3. `02_como_funciona.ipynb`

Ejecútalo después de cerrar Spark en el notebook 01. Es la versión reducida y ya probada del notebook anterior: se quitaron los archivos pequeños y las claves desbalanceadas (pasan a la clase 7).

| Celdas | Qué debes ver | Anota |
|---|---|---|
| 0 preparación | Igual que en el 01 | Segundos de arranque de Spark |
| 1 particiones | Un número de particiones y una tabla de filas por partición cuya suma es 19 663 930 | Número de particiones |
| 2.1 pandas | Tres tiempos, DataFrame de unos cientos de MB y pico de memoria | Los tres tiempos y el pico: **es la celda que más riesgo tiene de matar el kernel en 8 GB** |
| 2.2 todas las columnas | Estimaciones de mes y año en GB | Las dos estimaciones |
| 2.3 Spark | Dos tiempos (SQL y DataFrame) y el mismo número de grupos (8 006) | Los dos tiempos |
| 2.4 Snowflake | Rol `ACCOUNTADMIN`, warehouse `COMPUTE_WH`, `SELECT 1`, el archivo en el stage, el tiempo de la consulta y el ID | Los tiempos y si el warehouse arrancó de cero |
| 2.5 comparar | Tabla con 8 006 grupos, 19 663 930 viajes e ingreso 471 132 933.49, y dos líneas `COINCIDEN` | La tabla completa |
| 2.6 | La tabla de «cuándo conviene cada uno» | Frases que no te gusten |
| 3 lazy y plan | Cuatro «definir» de milisegundos y un `count()`; en el plan, `ReadSchema` con 2 columnas y `PushedFilters` con `EqualTo(PULocationID,132)` | Si el resumen de `FileScan` se imprime bien |
| 4.1 a 4.3 | Sin `Exchange` en la estrecha; con `Exchange hashpartitioning` en la ancha; `HashAggregate` parcial y final; la tabla de etapas | La tabla de etapas y si la API de la Spark UI respondió |
| 4.4 | `Exchange SinglePartition` en la ventana sin partición y `hashpartitioning` en la otra, con dos tiempos; los dos `toPandas` | Los tiempos |
| 5 broadcast | `SortMergeJoin` y `BroadcastHashJoin`, dos tiempos, `Resultados iguales: True`, umbral restaurado | Los dos tiempos |
| Cierre | `Spark cerrado.` | |

## 4. `03_lab.ipynb` (enunciado) y `03_lab_solucion.ipynb`

1. En `03_lab.ipynb` ejecuta hasta el ejercicio 5b sin resolver nada. Debes ver **siete líneas `PENDIENTE`** (1a, 1b, 2, 3, 4, 5a y 5b) y ningún error rojo. Confirma que `inspect.getsource` funciona en el Code Editor: si alguna dice `OK` o `REVISAR` con el enunciado sin resolver, es lo primero que hay que mirar.
2. Abre `03_lab_solucion.ipynb` (la copia, ya que no la copiaste, cópiala ahora a `~/clase05_mis_notebooks/`) y ejecútalo completo. Debes ver siete líneas `OK`; la celda de la ingesta lista los archivos de tu bronze de práctica (un crudo y dos lotes con su marcador `_LOTE_COMPLETO`) y cuenta 62 filas con dos lotes; la cadena imprime `Tu gold es equivalente al del pipeline del repo: True`; y se imprime la tabla de lluvia y viajes con su correlación.
3. Provoca un `REVISAR` a propósito en la solución y vuelve a ejecutar cada prueba:
   - En 1a, reemplaza `F.coalesce(como_texto, F.lit(MARCADOR_NULO))` por `como_texto`: debe decir `REVISAR` y la pista sobre `(«a», nulo)`.
   - En 1b, cambia `crudo_ya_existe = crudo.exists()` por `crudo_ya_existe = False`: debe decir `REVISAR  La segunda ejecución volvió a llamar a la red`.
   - En 1b, calcula el hash después de los metadatos (por ejemplo `calcular_hash_fila(dias.columns + ["_id_lote"])`): debe decir `REVISAR` por la huella.
   - En 4, cambia `F.broadcast(zonas_sel)` por `zonas_sel`: debe decir `REVISAR  El plan no usa BroadcastHashJoin...`.
   - En 5b, cambia la ponderación por `F.avg("propina_promedio")`: debe decir `REVISAR` con la pista de los promedios.
   Restaura cada cambio.
4. En el notebook de estudiante, resuelve el ejercicio 3 con `row_number()` sobre una ventana en lugar de `dropDuplicates` y comprueba que también da `OK`; abre la Spark UI y mira el shuffle de esa celda.
5. Abre tu bucket y comprueba que **no** se escribió nada: el lab trabaja en `~/datos_clase05/bronze_alumno`, no en S3.

### Medición final (celda extra al final de cualquiera de los tres notebooks)

Añade una celda con este código y pégame su salida:

```python
print(json.dumps({k: round(v, 2) for k, v in TIEMPOS.items()}, indent=1, ensure_ascii=False))
```

y, en la terminal, `free -m` justo después.

## 5. La sección «A mano primero» desde la terminal

Con Spark ya cerrado en el notebook (y el kernel reiniciado si hace falta):

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

Anota: si el primer comando necesitó `--lake-bucket`, si la muestra local tiene el diseño de lotes (si dice `No hay ningún lote completo`, hay que regenerar la muestra con `make muestra`), si falló con `ModuleNotFoundError` sin `PYTHONPATH=src`, los segundos de cada comando y las cifras de la línea `Limpieza`.

## 6. Lo que quiero que mires con ojo crítico

1. El enlace de la Spark UI (`.../codeeditor/default/ports/4040/jobs/`) y el permiso `sagemaker:DescribeSpace` desde el kernel.
2. Que `inspect.getsource` funcione sobre las funciones definidas en una celda del Code Editor: de eso depende que `PENDIENTE` aparezca.
3. Que `explain()` se capture con `redirect_stdout` y que la línea del `FileScan` se resuma bien.
4. La lectura de etapas por la API de la Spark UI desde Python (`/api/v1/applications/<id>/stages`).
5. Que la celda de pandas (pico de memoria) no mate el kernel en 8 GB.
6. El tiempo de Snowflake desde la cuenta de un estudiante, y que `CURSO` exista con el rol de la conexión `default`.
7. Que la descarga de la celda 0.3 encuentre el archivo en `bronze/_crudo/...` o en la ruta anterior, según cuál tenga tu lake.
8. La claridad del texto: marca cualquier frase que suene a ficha escolar o a promesa de cifra. En especial, la tabla de columnas de los viajes de `01_fundamentos` (¿el diccionario de datos está bien explicado?) y la sección de depuración.

## 7. Qué pegarme de vuelta

| Qué | De dónde |
|---|---|
| `nproc`, `free -m`, versión de Python y de Java | Paso 1.2 |
| Resultado de la instalación, del kernel, de `distutils` y de la conexión de Snowflake | Pasos 1.3 y 1.4 |
| Si trabajar desde la copia fuera del repositorio funcionó | Paso 1.5 |
| De qué ruta del bucket bajó cada archivo y los segundos | Celda 0.3 del 01 |
| Si el enlace de la Spark UI abrió con estilos | Celda 0.5 |
| Segundos de cada celda con `cronometro` y la tabla de 2.5 | Notebook 02 (o la celda extra de medición) |
| Pico de memoria del proceso Python y de Java en cada sección | Celda extra y monitor de la segunda terminal |
| Número de particiones, `defaultParallelism` y la tabla de etapas | Notebook 02, secciones 1 y 4 |
| Las siete líneas del lab sin resolver, y las siete con la solución | Notebook 03 |
| Cualquier celda en rojo o `REVISAR` inesperado, con el traceback completo | Cualquier notebook |
| Salida de los comandos de la sección 5 de este guion y sus segundos | Terminal |
| Frases del texto que no te gusten | Notebooks |
