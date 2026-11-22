# Clase 7 · ensayo en el Code Editor (solo instructor)

Esta guía recorre la clase 7 en la máquina real del Code Editor, con la cuenta de prueba y en el orden del deck. Ejecuta cada bloque y copia la salida que pide la línea **«Pega»**. Lo que no sale como se espera también sirve: pégalo tal cual. Las cifras que el deck dice «se anotan en el ensayo» salen de aquí.

Tiempo estimado: unas 3 horas y media, sin contar las esperas de Glue y del CI. Se hace dos veces: el domingo (con la cuenta en el diseño viejo) y el lunes antes de clase (con la cuenta ya migrada). Cada paso dice qué slides cubre. **Costo:** los pasos 7 y 13 usan Glue; el 14 enciende la VM de prod.

## 0. Traer la rama y revisar el entorno

```bash
cd ~/bigdata && git fetch origin && git checkout clase07-contenido && git pull
cd ~/bigdata && .venv/bin/python --version
cd ~/bigdata && make doctor
```

Si la versión no es 3.12, ejecuta `cd ~/bigdata && make reparar-entorno` y vuelve a elegir el kernel `.venv`.

**Pega:** la versión de Python y la salida de `make doctor` (en especial las líneas de `PIPELINE_ENTORNO` y de los jars).

## 1. Migración de una cuenta con el diseño viejo (slides 8 y 9)

Solo el domingo. `simular-diseno-viejo.sh` deja la cuenta de prueba con `bronze/` y `muestra/` en la raíz.

```bash
cd ~/bigdata && bash scripts/simular-diseno-viejo.sh
cd ~/bigdata && aws s3 ls "s3://bigdata-lake-$(aws sts get-caller-identity --query Account --output text)-us-east-2/"
cd ~/bigdata && time make migrar-clase07
cd ~/bigdata && aws s3 ls "s3://bigdata-lake-$(aws sts get-caller-identity --query Account --output text)-us-east-2/"
```

En el plan de Terraform de `make migrar-clase07` mira la línea `Plan: N to add, N to change, N to destroy` **antes** de escribir `yes`. Si `destroy` no es 0, escribe `no` y detén el ensayo.

Después, la comprobación «Antes de seguir» de `curso/clase07/README.md` (las seis).

**Pega:** la raíz del bucket antes y después, la línea `Plan:` de Terraform, el tiempo total de `make migrar-clase07` y cuánto tardó cada uno de sus seis pasos (anota la hora de cada `==> Paso`).

## 2. Spark contra S3 desde el Code Editor (riesgo 1) (slides 20 y 21)

```bash
cd ~/bigdata && ls -la ~/.spark-jars
cd ~/bigdata && free -h
cd ~/bigdata && time make correr PASO=bronze LIMITE=1000 REPROCESAR=true
```

`REPROCESAR=true` es solo para este ensayo: después, en el paso 10, se hace `resetear_entorno`. Si falla por credenciales, repite con `PIPELINE_S3A_CREDENCIALES=boto3 make correr ...`.

**Pega:** el encabezado y el cierre completos, el tiempo, la memoria `available` de `free -h` y cualquier error de credenciales o de jars. Anota si bronze descargó el crudo (`DESCARGA`) o ya estaba (`YA ESTÁ`).

## 3. Notebook 1 completo (slides 16 a 45)

```bash
mkdir -p ~/clase07_mis_notebooks && cp ~/bigdata/curso/clase07/0*.ipynb ~/clase07_mis_notebooks/
cd ~/bigdata && make airflow-local-down
```

Abre `01_construir_paso_a_paso.ipynb`, elige el kernel `.venv` y ejecuta las celdas **una por una** (no Run All: las Celdas 20 y 21 son de verdad), cronometrando las lentas.

**Pega:**
- Celda 2 y 3: el encabezado y la tabla de carpetas.
- Celda 5: tiempo y si bajó o ya estaba el crudo.
- Celda 6 y 7: `Filas leídas` y `True`.
- Celda 9: la lista de registros (debe ser `[]` en una cuenta limpia).
- Celda 14, 16: las salidas completas.
- Celda 20 y 21: el encabezado y el cierre de cada una, y el tiempo de la 20.
- Celda 22 y 23: el registro y la carpeta `lote=`.
- Celda 24: filas en bronze, en silver y descartadas.
- Celda 26 y 27: las tres cifras de cada una.
- Celda 30 y 31: filas de gold, viajes que suma, y las dos comparaciones.
- Celda 34: la línea `CREA` y las siete columnas.
- Tiempo total del notebook.

Cierra con la Celda 35 (apaga Spark).

## 4. Notebook 2 completo (slides 46 a 59)

Abre `02_funciones_listas.ipynb` y usa Run All.

**Pega:** las salidas de las Celdas 4, 7, 9, 11, 12 y 13 completas y el tiempo total. En la Celda 13 debe salir `Resumen: 9 PENDIENTE, 9 OK` (si no es así, pega qué pruebas cambiaron). Cierra el kernel (Kernel > Shut Down).

## 5. make test y los PENDIENTE (slides 60 a 62)

```bash
cd ~/bigdata && time make test
```

**Pega:** el resumen final de pytest con `-rs` (las líneas `SKIPPED` y `N passed, N skipped`), la línea de las pruebas de los DAGs y el tiempo. Debe haber 23 omitidas: 10 de `PENDIENTE` y 13 de la práctica de ingesta.

## 6. make correr, paso por paso (slides 63 a 71)

Estado de partida: dev con bronze registrado por el notebook (pasos 2 y 3). Si el paso 2 usó `REPROCESAR=true`, haz primero el paso 10 y repite el 3.

```bash
cd ~/bigdata && PYTHONPATH=src .venv/bin/python -m pipeline.run --paso bronze
cd ~/bigdata && make -n correr PASO=bronze
cd ~/bigdata && time make correr PASO=bronze
cd ~/bigdata && time make correr PASO=silver
cd ~/bigdata && time make correr PASO=gold
cd ~/bigdata && time make correr PASO=snowflake
```

En Snowsight (rol `BIGDATA_DEV`, warehouse `BIGDATA_WH`, base `BIGDATA`):

```sql
USE ROLE BIGDATA_DEV;
USE WAREHOUSE BIGDATA_WH;
USE DATABASE BIGDATA;
SELECT COUNT(*) AS filas, SUM(VIAJES) AS viajes, MIN(FECHA), MAX(FECHA)
FROM BIGDATA.DEV.TARIFA_POR_MILLA_BARRIO;
```

**Pega:** el cierre y el tiempo de cada paso (en el cierre de silver y de gold, las cifras `N` y `M` del deck), la salida de `make -n`, y el resultado de la consulta. Anota la relación `SUM(VIAJES)` frente a las filas de silver de viajes: debe ser 1.

## 7. Glue small desde make (slides 72 a 74)

```bash
cd ~/bigdata && time make correr PASO=silver COMPUTO=glue_small
cd ~/bigdata && time make correr PASO=silver COMPUTO=glue_small REPROCESAR=true
```

Comprueba que el código que corre es el de tu árbol y no el de `main`: mira en el log de Glue la ruta `code/dev/pipeline.zip` (y que `code/pipeline.zip` no cambió: `aws s3 ls s3://<lake>/code/ --recursive`).

**Pega:** el encabezado de los dos comandos, el cierre, las URL de la consola de Glue y del Spark UI que imprime el lanzador, el tiempo de cada uno (el primero es el costo de arrancar Glue aunque se salte) y la fecha de `code/pipeline.zip` antes y después.

## 8. Airflow del Code Editor (slides 75 a 81)

```bash
cd ~/bigdata && make -n airflow-local
cd ~/bigdata && time bash scripts/airflow-local.sh up
cd ~/bigdata && make airflow-local-estado
```

Abre la interfaz (`/codeeditor/default/ports/8080/`), activa `pipeline_taxi` y lánzalo con `computo = code_editor`, `limite = 1000`, `mes = 2024-01` y **Reprocesar marcado**. Esto crea el segundo lote de bronze.

**Pega:** el tiempo del arranque, la salida de `airflow-local-estado`, cuánto tardó el DAG y cuánto cada tarea (columna Duration del Grid), el encabezado y el cierre del log de `correr_silver`, y la memoria más baja que mostró `free -h` mientras corría (en otra terminal: `watch -n 5 free -h`).

## 9. Duplicados con Athena (slides 82 a 95)

```bash
cd ~/bigdata && CUENTA=$(aws sts get-caller-identity --query Account --output text)
cd ~/bigdata && sed "s/<CUENTA>/$CUENTA/g; s/<ENTORNO>/dev/g" curso/clase07/athena/01_tablas.sql > ~/01_tablas_dev.sql
cd ~/bigdata && aws s3 ls "s3://bigdata-lake-$CUENTA-us-east-2/dev/bronze/fhvhv/mes=2024-01/"
```

En la consola de Athena (región us-east-2, workgroup `bigdata-wg`, base `bigdata_lake`), ejecuta `~/01_tablas_dev.sql` una sentencia a la vez y después los pasos 1, 2, 3A, 3B, 3C y 4 de `curso/clase07/athena/02_duplicados_y_conciliacion.sql`.

Después, una corrida más y repite los pasos 1 y 2:

```bash
cd ~/bigdata && time make correr REPROCESAR=true
```

**Pega:** `aws s3 ls` (debe haber 2 carpetas `lote=`); y por cada consulta el resultado, el tiempo y los *Data scanned*. Anota en una tabla, por corrida (1.ª, 2.ª, 3.ª): filas de silver de viajes, clima y zonas, viajes de gold y la relación. **Debe dar** silver ×1, ×2, ×3 y gold ×1, ×8, ×27; si no, pega qué salió. Anota también el mensaje del paso 3C (huellas en 0).

## 10. Consulta de la tabla de control y de Snowflake (slide 88)

En Snowsight, con `BIGDATA_DEV`:

```sql
USE ROLE BIGDATA_DEV;
USE WAREHOUSE BIGDATA_WH;
USE DATABASE BIGDATA;
SELECT TABLA, CAPA, MES, FILAS, LEIDAS, COMPUTO, LIMITE, REPROCESAR, INICIO
FROM BIGDATA.CONTROL_DEV.WATERMARK ORDER BY INICIO;
SELECT TABLA, CAPA, MES, FILAS, LEIDAS, COMPUTO, INICIO
FROM BIGDATA.CONTROL_DEV.WATERMARK
QUALIFY ROW_NUMBER() OVER (PARTITION BY TABLA, CAPA, MES ORDER BY INICIO DESC) = 1
ORDER BY CAPA, TABLA, MES;
SELECT COUNT(*) AS filas, SUM(VIAJES) AS viajes FROM BIGDATA.DEV.TARIFA_POR_MILLA_BARRIO;
```

**Pega:** las dos listas de la tabla de control y la última consulta. Confirma que `SUM(VIAJES)` coincide con `viajes_en_gold` del paso 9 (×27).

## 11. resetear_entorno en dev (slides 89 a 94)

En la interfaz de Airflow de dev: activa `resetear_entorno` y lánzalo así, en este orden.

1. Con una confirmación mala (por ejemplo `borrar prod`) y `Solo listar` desmarcada: debe fallar en `validar` sin borrar nada.
2. Con `Solo listar` marcada: lista y termina.
3. Con `Solo listar` desmarcada, `Conservar el crudo` marcada y la confirmación `borrar dev`.

Después, comprueba:

```bash
cd ~/bigdata && aws s3 ls "s3://bigdata-lake-$(aws sts get-caller-identity --query Account --output text)-us-east-2/dev/" --recursive | head
```

y en Snowsight, `SELECT COUNT(*) FROM BIGDATA.CONTROL_DEV.WATERMARK;` (debe dar 0) y `SHOW TABLES IN SCHEMA BIGDATA.DEV;` (debe estar vacío).

**Pega:** el log de `validar` del intento con confirmación mala, el de `contar` y el de `resumen` de los otros dos, cuánto tardó el borrado real, y las tres comprobaciones.

## 12. Pipeline limpio y la solución del instructor (slides 94 y 95)

Con dev vacío, el pipeline completo, sin reprocesar:

```bash
cd ~/bigdata && time make correr
```

Repite la consulta del paso 2 de Athena: la relación debe ser 1.

Ahora la prueba de la solución, **en una copia, nunca en el repositorio**:

```bash
rm -rf /tmp/copia_clase07 && mkdir /tmp/copia_clase07
cd ~/bigdata && cp -R src tests pyproject.toml pipeline.yaml /tmp/copia_clase07/
cd ~/bigdata && bash <ruta-de-validacion>/contenido/clase07_solucion/aplicar_solucion.sh /tmp/copia_clase07
cd /tmp/copia_clase07 && PYTHONPATH=src ~/bigdata/.venv/bin/python -m pytest tests/test_pasos.py tests/test_equipo_bronze.py tests/test_equipo_silver.py -q -rs
```

La solución está en `validacion/contenido/clase07_solucion/` (fuera del repositorio). Con ella, las pruebas del equipo pasan de `PENDIENTE` a `OK`, y el reproceso ya no duplica (el pipeline de verdad con la solución se prueba en el paso 14 del ensayo del lunes por la noche, si se decide).

**Pega:** el tiempo y los cuatro cierres de `make correr`, la relación del paso 2 de Athena, y el resumen de pytest de la copia (debe haber 0 `PENDIENTE`).

## 13. Dimensionamiento: las siete filas (slides 95 a 99)

Cada medida parte de un dev limpio (paso 11 con `Conservar el crudo` marcado). Con `time` en cada una; son siete corridas, así que son unas dos horas: si falta tiempo, mide solo las filas 0, 1, 4 y 5.

```bash
cd ~/bigdata && time make correr LIMITE=1000 COMPUTO=code_editor
cd ~/bigdata && time make correr LIMITE=1000 COMPUTO=glue_small
cd ~/bigdata && time make correr LIMITE=100000 COMPUTO=code_editor
cd ~/bigdata && time make correr LIMITE=100000 COMPUTO=glue_small
cd ~/bigdata && time make correr LIMITE=todos COMPUTO=glue_small
cd ~/bigdata && time make correr LIMITE=todos COMPUTO=glue_medium
cd ~/bigdata && time make correr LIMITE=todos COMPUTO=glue_large
```

**Pega:** la tabla completa, con el tiempo `real` del comando y, de cada cierre, el tiempo de cada paso. Para las filas de Glue, la duración del job (consola de Glue) frente al tiempo total (la diferencia es el arranque y el conector). Anota también `free -h` en las filas de `code_editor` con 100 000, y qué pasa con `LIMITE=todos COMPUTO=code_editor` (debe fallar con un mensaje que dice que no cabe).

## 14. PR, CI, Deploy y prod (slides 100 a 117)

```bash
cd ~/bigdata && git switch main && git pull && git switch -c ensayo-clase07-a-prod
cd ~/bigdata && echo "# Ensayo clase 7" >> src/pipeline/gold.py
cd ~/bigdata && make test
cd ~/bigdata && git add src/pipeline/gold.py && git commit -m "Ensayo clase 7: camino a prod"
cd ~/bigdata && git push -u origin ensayo-clase07-a-prod
```

Abre el pull request (base `main` de **tu fork**), espera los cinco checks, aprueba (otra cuenta) y haz merge. Anota la hora de cada paso. Cuando el **Deploy** termine, comprueba que la VM se encendió y que solo `pipeline_taxi` y `resetear_entorno` están en `dags/` del bucket:

```bash
cd ~/bigdata && make estado
cd ~/bigdata && aws s3 ls "s3://bigdata-lake-$(aws sts get-caller-identity --query Account --output text)-us-east-2/dags/"
cd ~/bigdata && make airflow-local-down
cd ~/bigdata && make airflow-tunel
cd ~/bigdata && make airflow-password
```

En la UI de prod, lanza `pipeline_taxi` con `glue_medium`, `todos`, `2024-01` y Reprocesar sin marcar. Confirma además que el formulario de prod **no** ofrece `code_editor`, `1000` ni un campo de entorno.

Valida con Athena (`01_tablas.sql` con `<ENTORNO>` = `prod`; paso 2 de `02_duplicados_y_conciliacion.sql` con `prod_`) y con Snowflake:

```sql
USE ROLE BIGDATA_DEV;
USE WAREHOUSE BIGDATA_WH;
USE DATABASE BIGDATA;
SELECT TABLA, CAPA, MES, FILAS, COMPUTO, LIMITE, INICIO FROM BIGDATA.CONTROL_PROD.WATERMARK ORDER BY INICIO;
SELECT COUNT(*), SUM(VIAJES) FROM BIGDATA.PROD.TARIFA_POR_MILLA_BARRIO;
INSERT INTO BIGDATA.CONTROL_PROD.WATERMARK (TABLA, CAPA, MES) VALUES ('prueba', 'bronze', '2024-01');
SHOW GRANTS TO ROLE BIGDATA_DEV;
```

El `INSERT` **debe fallar**. Si funciona, para el ensayo y avisa: es un fallo grave de permisos. Cierra con `make airflow-off` y comprueba con `make estado`.

**Pega:** la hora de cada paso (PR, cada check, merge, Deploy, VM encendida, DAG de prod), el tiempo total y de cada tarea del DAG de prod, la salida del formulario de prod, los resultados de Athena y de Snowflake (debe cuadrar: filas de silver, `viajes_en_gold` y `SUM(VIAJES)`; la corrida del 20 de noviembre dio 19 663 930 en bronze y 19 650 023 en silver), el texto exacto del error del `INSERT` y que `SHOW GRANTS` no trae `CREATE`, `INSERT` ni `DELETE` sobre `PROD` ni `CONTROL_PROD`.

## 15. Dejar todo como estaba

```bash
cd ~/bigdata && make airflow-local-down
cd ~/bigdata && git switch main && git branch -D ensayo-clase07-a-prod
cd ~/bigdata && git status --short
```

En Snowflake: `ALTER WAREHOUSE BIGDATA_WH SUSPEND;`. Apaga la VM de prod (`make airflow-off`) y verifica con `make estado`. En GitHub, borra la rama `ensayo-clase07-a-prod` del fork.

**Pega:** la salida de `git status --short` (debe quedar vacía) y de `make estado`.

## Qué hacer con lo pegado

- Las cifras del ensayo van a `validacion/contenido/clase07_medidas.md` (sección «Ensayo del Code Editor, clase 7»).
- Las que el deck dice «se anotan en el ensayo» (`N` y `M` del cierre de silver y de gold, los tiempos de cada paso y de las filas 0 a 6 del dimensionamiento) se actualizan en `curso/clase07/deck/slides.json` y se regenera el guion con `cd ~/bigdata/curso/clase07/deck && python3 generar_guion.py`.
- Si algo del orden o de un comando falló, corrige el deck, el README o el notebook **antes** de enviar las instrucciones de migración a los estudiantes.
