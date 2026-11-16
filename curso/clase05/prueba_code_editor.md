# Guion de prueba de la clase 5 en el Code Editor

Para el autor. El notebook se escribió y se probó parcialmente en un Mac sin Java, así que **nada de Spark se ha ejecutado todavía**. Este guion recorre el notebook en el Code Editor, en orden, con la salida esperada de cada paso y lo que debes pegarme al final. Hazlo con `clase05.ipynb` (versión estudiante) y, al final, con `clase05_solucion.ipynb`.

## Qué se probó ya, y dónde

Las cifras de esta tabla vienen de un Mac de 32 GB con Python 3.12 (no del Code Editor): sirven como referencia de lo que no depende de la máquina (resultados) y como cota de lo que sí depende (tiempos y memoria). No las compares uno a uno con las del Code Editor.

| Qué | Resultado en el Mac |
|---|---|
| Ambos `.ipynb` son JSON válido (`nbformat`), la sintaxis de todas las celdas compila y no hay nombres sin definir | Correcto |
| Sección 0 (kernel, bucket, descarga desde el bucket propio, utilidades) | Correcta; el bucket de la cuenta de prueba tiene el mismo diseño que el de los estudiantes. Descarga de los 450.9 MiB: 54 s |
| Sección 2.1 y 2.2 (pandas) | Leer 3 columnas con pyarrow 0.1 s, convertir a DataFrame 0.1 s, filtrar y agrupar 1.0 s; DataFrame de 375 MB; pico de memoria del proceso entre 2.0 y 2.6 GB. Un grupo de 1 048 576 filas con las 24 columnas: 526 MB (estimación del mes completo 9.6 GB y del año 117.2 GB, aritmética sobre esa medición) |
| Sección 2.4 y 2.5 (Snowflake, warehouse X-Small, stage temporal sobre el bucket público) | Consulta de 10.2 a 11.7 s con `USE_VECTORIZED_SCANNER = TRUE`; **169 a 170 s sin esa opción** (misma consulta, mismo resultado); 8 006 grupos zona-día, 19 663 930 viajes, ingreso 471 132 933.49. Coinciden con pandas: 0 grupos sin pareja, 0 diferencias en viajes, diferencia máxima de ingreso 0.000000 |
| Ejercicio 1 (`ingerir_clima`) con la solución | `OK` contra Open-Meteo real (la prueba hace una descarga y comprueba la segunda ejecución sin red); 0.7 s. Con cuatro implementaciones incorrectas (sin comprobar existencia, re-serializando el JSON, sin metadatos, ruta equivocada) la prueba dice `REVISAR` con la pista correcta |
| Mecanismo `verificar` | Con el notebook de estudiante, las seis funciones dicen `PENDIENTE`; con la solución, `OK`; una prueba que falla da `REVISAR` y su pista; una que lanza una excepción da `REVISAR` y el tipo de error |
| Una sola fila repetida en enero con la clave `CLAVE_BRUTA` | Medido con pandas sobre el archivo completo |

**Lo que NO se ha ejecutado** y esta prueba debe cubrir: todo lo que usa Spark (secciones 0.5, 1, 2.3, 3, 4, 5 y 6 excepto E1), el enlace de la Spark UI, `make`, `pytest` y `ruff` desde el notebook y la sección 7.

## 1. Preparar el Code Editor

1. Lleva al Code Editor la carpeta `curso/clase05/` y el archivo `requirements-dev.txt` de la rama `clase05-contenido` (la rama todavía no tiene commits: sube los archivos por el explorador o haz commit y `git pull` en `~/bigdata`).
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
```

Salida esperada: `Successfully installed ...` (o `Requirement already satisfied`), `Installed kernelspec bigdata in ...` y `librerias ok`. Si el último falla con `X509_V_FLAG_NOTIFY_POLICY`, copia el error completo: significa que `pip` no respetó las versiones fijas de `pyOpenSSL` y `cryptography`.

4. Comprueba la conexión de Snowflake y el warehouse:

```bash
cd ~/bigdata && .venv/bin/python -c "import snowflake.connector as s; c = s.connect(connection_name='default'); cur = c.cursor(); print(cur.execute('select current_user(), current_role(), current_warehouse()').fetchone()); c.close()"
```

Salida esperada: una tupla con tu usuario, tu rol y el **nombre de un warehouse (no `None`)**. Si sale `None`, la celda de la sección 2.4 se detiene con su mensaje; dime qué warehouse hay que usar.

5. En una segunda terminal deja corriendo el monitor de memoria durante todo el notebook:

```bash
watch -n 5 'free -m | head -2; ps -eo rss,comm --sort=-rss | head -4'
```

## 2. Recorrer `clase05.ipynb`

Abre `bigdata/curso/clase05/clase05.ipynb`, elige el kernel **Python (bigdata)** y ejecuta celda por celda. En cada fila: qué ejecutar, qué debes ver y qué anotar.

| Celdas | Qué debes ver | Anota |
|---|---|---|
| 0.1 kernel | Ruta con `.venv`, `Java: openjdk version "17...`, versiones de pandas 2.2.3, pyarrow 17.0.0 y pyspark 3.5.6, sin `AVISO` | Si el editor ofreció instalar la extensión de Jupyter y si el kernel apareció en la lista |
| 0.2 bucket | `Tu bucket: bigdata-lake-<cuenta>-us-east-2` y `Acceso al bucket: correcto` | Si imprime `AVISO` |
| 0.3 descarga | `Descargado desde s3://bigdata-lake-.../bronze/fhvhv/...` con 450.9 MiB, y las zonas. Si repites la celda: `Ya existe, no se descarga` | Segundos de la descarga |
| 0.4 utilidades | Memoria total (unos 8 GB) y memoria del proceso | Los dos valores |
| 0.5 Spark | Versión 3.5.6, `master local[*]`, driver `2g`, `defaultParallelism` y un enlace de Spark UI | El valor de `defaultParallelism` (se espera 2); segundos de arranque; **si el enlace abre la Spark UI en el navegador** (la ruta `.../codeeditor/default/ports/4040/` es una suposición que se arma igual que la de Airflow en `scripts/lib.sh`) |
| 1 particiones | Un número de particiones y una tabla de filas por partición cuya suma es 19 663 930 | Número de particiones y segundos |
| 2.1 pandas | Tres tiempos, DataFrame de unos cientos de MB, pico de memoria | Los tres tiempos y el pico: **es la celda que más riesgo tiene de matar el kernel en 8 GB** |
| 2.2 todas las columnas | Estimaciones de mes y año en GB, contra la memoria de la máquina | Las dos estimaciones |
| 2.3 Spark | Dos tiempos (SQL y DataFrame) y el mismo número de grupos (8 006) | Los dos tiempos y si el proceso Java crece en el monitor |
| 2.4 Snowflake | Rol, warehouse, `SELECT 1`, el archivo en el stage, el tiempo de la consulta y el ID | Los tiempos y si el warehouse arrancó de cero; copia el ID y mira el *Query Profile* |
| 2.5 comparar | Tabla con 8 006 grupos, 19 663 930 viajes e ingreso 471 132 933.49 en los tres motores, y dos líneas `COINCIDEN` | La tabla completa |
| 3 lazy | Cuatro «definir» de milisegundos; el `count()` tarda lo que cuesta leer; en el plan, `ReadSchema` con 2 columnas y `PushedFilters` con `EqualTo(PULocationID,132)` | Tiempos y **si el resumen de `FileScan` (PushedFilters y ReadSchema) se imprime bien**: es una expresión regular sobre el texto del plan |
| 4.1 a 4.3 | Sin `Exchange` en la estrecha; con `Exchange hashpartitioning` en la ancha; `HashAggregate` con `partial_count` y `partial_sum`; la tabla de etapas con filas de shuffle escrito | La tabla de etapas completa y si la API de la Spark UI respondió (si imprime «No se pudo leer la Spark UI», dímelo) |
| 4.4a ventana | `Exchange SinglePartition` en el plan sin partición y `hashpartitioning` en el otro; dos tiempos | Los dos tiempos y si el kernel sufre |
| 4.4b toPandas | Tiempos de 1 millón de filas y del resumen | Los dos tiempos y la memoria |
| 4.4c desbalance | Ranking de zonas, razón de la primera contra la mediana, aeropuertos con su puesto | **La salida completa**: confirma que el texto de la sección dice algo cierto (el texto no cita cifras) |
| 4.4c segunda celda | Razón entre la partición más cargada y la mediana | La línea |
| 4.4d archivos pequeños | Tabla con 200 y 2 particiones: archivos, tamaño medio, filas leídas iguales; carpeta borrada al final | La tabla y los cuatro tiempos |
| 5 broadcast | Plan con `SortMergeJoin` y plan con `BroadcastHashJoin`, dos tiempos, `Resultados iguales: True`, umbral restaurado | Los dos tiempos y los dos planes (las líneas que imprime) |
| 6 preparación | La muestra: filas exactas, filas con duplicados, filas de la referencia | Los tres números y los segundos de armar la muestra |
| E1 a E5 con huecos | Seis líneas `PENDIENTE` | Que las seis digan `PENDIENTE` y que nada lance un error rojo |

Después, **cierra Spark con la celda `spark.stop()`** de la sección 6 al terminar, o reinicia el kernel.

### Prueba de los ejercicios

1. Abre `clase05_solucion.ipynb`, ejecútalo completo y confirma que las seis pruebas del lab dicen `OK`, que la celda de la cadena imprime `Tu gold es idéntico al del pipeline del repo: True` y que la tabla de lluvia y viajes se imprime. Anota los tiempos de cada prueba (la celda del `cronometro` de la cadena y el tiempo total del lab).
2. Provoca un `REVISAR` a propósito: en la solución del ejercicio 4 cambia `F.broadcast(zonas_sel)` por `zonas_sel`, ejecuta la celda y la prueba: debe decir `REVISAR  El plan no usa BroadcastHashJoin...`. En el ejercicio 5b cambia la ponderación por `F.avg("propina_promedio")`: debe decir `REVISAR` con la pista de los promedios. Restáuralos.
3. En el notebook de estudiante, resuelve el ejercicio 3 con `row_number()` sobre una ventana (en lugar de `dropDuplicates`) y comprueba que también da `OK`; abre la Spark UI y mira el shuffle de esa celda.

### Medición final (celda extra al final del notebook)

Añade una celda al final de `clase05.ipynb` (no está en el notebook a propósito) y pégame su salida:

```python
print(json.dumps({k: round(v, 2) for k, v in TIEMPOS.items()}, indent=1, ensure_ascii=False))
print("Memoria del proceso Python:", round(rss_mb()), "MB | pico:", round(pico_mb()), "MB")
```

y, en la terminal, `free -m` justo después.

## 3. La sección 7 desde la terminal

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

Salida esperada, en orden: las cuatro líneas de registro del paso silver (`Paso=silver`, `Lectura viajes`, `Limpieza ... -> ...` y `Calidad OK [silver]`); lo mismo para gold sin `Lectura`; `STEP=silver MES=2024-01 LIMITE= bash scripts/run-local.sh` (esa línea sí se verificó aquí con `make -n`); lo mismo que el primer comando, pero precedido de `==> Pipeline local: ...`; `passed` de pytest; `All checks passed!` de ruff; y las tres etapas de `make test`.

Anota: si el primer comando necesitó `--lake-bucket` (la muestra no estaba en `./lake/muestra`), si falló con `ModuleNotFoundError` sin `PYTHONPATH=src`, los segundos de cada comando y las cifras de la línea `Limpieza`.

## 4. Lo que quiero que mires con ojo crítico

Estas son las suposiciones del notebook que no se han podido verificar y que pueden fallar en el Code Editor:

1. El enlace de la Spark UI (`.../codeeditor/default/ports/4040/`) y el permiso `sagemaker:DescribeSpace` desde el kernel.
2. Que `inspect.getsource` funcione sobre las funciones definidas en una celda del Code Editor: de eso depende que `PENDIENTE` aparezca. Si todas las pruebas dicen `OK` o `REVISAR` con el enunciado sin resolver, es lo primero que hay que mirar.
3. Que `explain()` se capture con `redirect_stdout` (en PySpark 3.5.6 imprime con `print`, así que debería) y que la línea del `FileScan` se resuma bien.
4. La lectura de etapas por la API de la Spark UI desde Python (`/api/v1/applications/<id>/stages`).
5. Que la celda de pandas (pico de memoria) no mate el kernel en 8 GB, y que pandas y Spark convivan en la misma sesión.
6. El tiempo de Snowflake desde la cuenta de un estudiante (su warehouse puede ser distinto) y que `CURSO` exista con el rol de la conexión `default`.
7. La claridad del texto: marca cualquier frase que suene a ficha escolar o a promesa de cifra.

## 5. Qué pegarme de vuelta

| Qué | De dónde |
|---|---|
| `nproc`, `free -m`, versión de Python y de Java | Paso 1.2 |
| Resultado de la instalación, del kernel y de la conexión de Snowflake | Pasos 1.3 y 1.4 |
| Segundos de cada celda con `cronometro` y la tabla de 2.5 | Notebook (o la celda extra de medición) |
| Pico de memoria del proceso Python y de Java en cada sección | Celda extra y monitor de la segunda terminal |
| Número de particiones, `defaultParallelism` y la tabla de etapas | Secciones 1 y 4 |
| La salida de la sección 4.4c (zonas, aeropuertos y razón de desbalance) | Notebook |
| Cualquier celda en rojo o `REVISAR` inesperado, con el traceback completo | Notebook |
| Si el enlace de la Spark UI abrió | Sección 0.5 |
| Salida de los comandos de la sección 3 de este guion y sus segundos | Terminal |
| Frases del texto que no te gusten | Notebook |
