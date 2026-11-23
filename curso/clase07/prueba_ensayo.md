# Clase 7 · ensayo en el Code Editor (solo instructor)

Esta guía recorre la clase 7 en la máquina real del Code Editor, con la cuenta de prueba y **en el orden de la clase**. Ejecuta cada bloque y copia la salida que pide la línea **«Pega»**. Lo que no sale como se espera también sirve: pégalo tal cual. Las cifras que el deck dice «se anotan en el ensayo» salen de aquí.

Tiempo estimado: unas 3 horas y media, sin contar las esperas de Glue y del CI. Se hace dos veces: el domingo (con la cuenta en el diseño viejo) y el lunes antes de clase (con la cuenta ya migrada). **Costo:** el paso 11 usa Glue. El paso 12 (PR, CI, Deploy y prod) **ya no es de la clase 7: pasó a la clase 8** (martes 24 de noviembre, borrador en `curso/clase08/borrador_prod.md`); ensáyalo para esa clase, no para el lunes. La clase 7 cierra con una sola slide que anuncia el camino a prod.

La secuencia de la clase: (1) empezar limpio con `resetear_entorno` en dev; (2) Notebook 1 con `limite` 1000, en el dev de verdad; (3) `resetear_entorno` en dev otra vez y copiar a los `.py`; (4) las tareas del DAG una por una con `airflow tasks test`, con Athena entre cada una; (5) ejecutar en Snowsight el `CREATE TABLE` (el código nunca crea la tabla) y correr el DAG completo desde la interfaz; (6) resetear, ejecutar otra vez el `CREATE TABLE` y correr todo otra vez (funciona una vez); (7) correr con `reprocesar=true` y ver los duplicados; después, dimensionamiento (con dev limpio y Airflow apagado antes de cada medida con `code_editor`) y la slide de cierre que anuncia prod para la clase 8.

## 0. Traer la rama y revisar el entorno

```bash
cd ~/bigdata && git fetch origin && git checkout clase07-contenido && git pull
cd ~/bigdata && .venv/bin/python --version
cd ~/bigdata && make doctor
```

**Pega:** la versión de Python y la salida de `make doctor` (en especial `PIPELINE_ENTORNO` y los jars).

## 1. Migración de una cuenta con el diseño viejo

Solo el domingo. `simular-diseno-viejo.sh` deja la cuenta con `bronze/` y `muestra/` en la raíz.

```bash
cd ~/bigdata && bash scripts/simular-diseno-viejo.sh
cd ~/bigdata && time make migrar-clase07
cd ~/bigdata && aws s3 ls "s3://bigdata-lake-$(aws sts get-caller-identity --query Account --output text)-us-east-2/"
```

Mira la línea `Plan: N to add, N to change, N to destroy` **antes** de escribir `yes`; si `destroy` no es 0, escribe `no` y detén el ensayo. Después, las seis comprobaciones «Antes de seguir» de `curso/clase07/README.md`.

**Pega:** la raíz del bucket antes y después, la línea `Plan:`, el tiempo total y el de cada uno de los seis pasos.

## 2. Empezar limpio: Airflow del Code Editor y `resetear_entorno` (slides de «empezamos limpios»)

```bash
cd ~/bigdata && make -n airflow-local
cd ~/bigdata && time bash scripts/airflow-local.sh up
cd ~/bigdata && make airflow-local-estado
```

En la interfaz (`/codeeditor/default/ports/8080/`) activa `pipeline_taxi` y `resetear_entorno`. Lanza `resetear_entorno` en este orden: (a) confirmación mala (`borrar prod`) y `Solo listar` desmarcada: debe fallar en `validar` sin borrar; (b) `Solo listar` marcada: lista y termina; (c) `Solo listar` desmarcada, `Conservar el crudo` marcada y `borrar dev`.

```bash
cd ~/bigdata && aws s3 ls "s3://bigdata-lake-$(aws sts get-caller-identity --query Account --output text)-us-east-2/dev/" --recursive | head
```

En Snowsight: `SELECT COUNT(*) FROM BIGDATA.CONTROL_DEV.WATERMARK;` (0) y `SHOW TABLES IN SCHEMA BIGDATA.DEV;` (vacío).

**Pega:** el tiempo de arranque de Airflow y `airflow-local-estado`; el log de `validar` del intento malo; `contar` y `resumen` de (b) y (c); cuánto tardó el borrado real; y las tres comprobaciones.

## 3. Notebook 1 completo, en dev de verdad (slides del Notebook 1)

```bash
mkdir -p ~/clase07_mis_notebooks && cp ~/bigdata/curso/clase07/01_construir_paso_a_paso.ipynb ~/clase07_mis_notebooks/
cd ~/bigdata && make airflow-local-down
```

Abre `01_construir_paso_a_paso.ipynb`, elige el kernel `.venv` y ejecuta las celdas **una por una**, cronometrando las lentas. El notebook corre contra el dev de verdad: escribe en `s3://<lake>/dev/` y anota en `BIGDATA.CONTROL_DEV.WATERMARK` (incluidas filas de ensayo de 2023), y **no debe escribir nada en el disco** (sin `/tmp/lake_clase07`); compruébalo en el paso 3b. Necesita los `.jar` de `make jars-s3a`.

**Pega:** Celda 2 (encabezado con rutas `s3://`, sin `[RAÍZ DE PRUEBA]`), 5 (tiempo del crudo), 6 y 7, 9 (debe ser `[]`), 14, 16, 20 y 21 (encabezado y cierre; tiempo de la 20), 22 y 23, 24, 26 y 27, 30 y 31, 34 (`CREA` y siete columnas), 35 (todas deben decir `igual`) y 36 (`Resumen: 9 PENDIENTE, 9 OK`) y el tiempo total. Cierra con la Celda 37. Anota el tiempo de la Celda 20 (la primera corrida sube ~450 MB a S3) y confirma que las celdas 10 a 17 usan meses de 2023 y no dejan nada en enero.

**3b. Comprobar que dev quedó con datos reales y que el disco no se tocó:**

```bash
cd ~/bigdata && aws s3 ls "s3://bigdata-lake-$(aws sts get-caller-identity --query Account --output text)-us-east-2/dev/bronze/" --recursive | grep lote= | head
ls /tmp/lake_clase07 2>&1 | head -2
```

En Snowsight: `SELECT TABLA, CAPA, MES, COUNT(*) FROM BIGDATA.CONTROL_DEV.WATERMARK GROUP BY ALL;` debe mostrar las tres tablas de bronze de `2024-01` (una fila cada una) y los meses de ensayo de 2023. **Pega:** las tres salidas (un lote de `fhvhv` en S3; `ls` debe decir que no existe la carpeta; las filas de control).

**3c. Empezar limpio otra vez (slide de `resetear_entorno` después del notebook):** en Airflow del Code Editor, lanza `resetear_entorno` con `Solo listar` marcada (anota cuántos objetos, registros y tablas cuenta) y después con `Solo listar` desmarcada, `Conservar el crudo` marcada y `borrar dev`. Repite la consulta de control: debe dar 0 filas. **Pega:** `contar` y `resumen` de las dos corridas.

## 4. Del notebook al `.py` y `make test`

Las Celdas 35 y 36 del Notebook 1 ya se ejecutaron en el paso 3 (comparación con los `.py` y `probar_mis_funciones`). Ahora abre `src/pipeline/bronze.py` y `silver.py` y comprueba que `agregar_metadatos` y `deduplicar` son la misma función que las Celdas 18 y 27. Prueba el cambio de punta a punta: en el notebook, agrega un comentario a `deduplicar` y vuelve a ejecutar la Celda 35 (debe decir `DISTINTO` solo en esa función); cópiala al `.py`, reinicia el kernel y la Celda 35 debe volver a `igual`. Revierte el cambio.

```bash
cd ~/bigdata && time make test
```

**Pega:** el resumen de pytest con `-rs` (las líneas `SKIPPED` y `N passed, N skipped`: deben ser 10 omitidas, todas `PENDIENTE`) y el tiempo.

## 5. Las tareas del DAG, una por una, con Athena entre cada una

Con Airflow del Code Editor **encendido**. En una terminal:

```bash
cd ~/bigdata && export PIPELINE_ENTORNO=dev
export AIRFLOW_HOME="$HOME/.airflow-local/home" PATH="$HOME/.airflow-local/venv/bin:$PATH"
export AIRFLOW__CORE__DAGS_FOLDER="$HOME/bigdata/airflow/dags" PYTHONPATH="$HOME/bigdata/airflow" AIRFLOW__CORE__LOAD_EXAMPLES=false
cd ~/bigdata && time airflow tasks test pipeline_taxi correr_bronze 2024-01-01 --task-params '{"computo": "code_editor", "limite": "1000", "mes": "2024-01", "reprocesar": false}'
```

Si `--task-params` no llega a `ejecutar_paso` (la tarea falla por parámetros), anótalo: es lo primero que hay que arreglar en la clase. Después, la declaración de las tablas:

```bash
cd ~/bigdata && CUENTA=$(aws sts get-caller-identity --query Account --output text)
cd ~/bigdata && sed "s/<CUENTA>/$CUENTA/g; s/<ENTORNO>/dev/g" curso/clase07/athena/01_tablas.sql > ~/01_tablas_dev.sql
```

En Athena (us-east-2, `bigdata-wg`, `bigdata_lake`) ejecuta `~/01_tablas_dev.sql` una sentencia a la vez. **Confirma dos cosas del diseño:** que `SHOW TABLES` lista las siete tablas `dev_`, y que la consulta A1 **lee las subcarpetas `lote=`** (si devuelve 0 filas con bronze escrito, Athena no está leyendo recursivo y hay que cambiar el DDL de bronze).

**Punto A (después de bronze):** consultas A1, A2, A3, A4 (y A5 si declaraste `dev_crudo_fhvhv`) de `athena/02_duplicados_y_conciliacion.sql`. En Snowsight, la consulta E1. **Pega:** encabezado, cierre y tiempo de la tarea; las consultas A con sus *Data scanned* (A1 debe dar un lote de 1 000 filas; A3, 0 con huella); y E1 (tres filas de bronze).

**Punto B (después de silver):**

```bash
cd ~/bigdata && time airflow tasks test pipeline_taxi correr_silver 2024-01-01 --task-params '{"computo": "code_editor", "limite": "1000", "mes": "2024-01", "reprocesar": false}'
```

Consultas B1, B2 y B3. **Pega:** cierre, tiempo, y las tres (filas de bronze, de silver y descartadas).

**Punto C (después de gold):**

```bash
cd ~/bigdata && time airflow tasks test pipeline_taxi correr_gold 2024-01-01 --task-params '{"computo": "code_editor", "limite": "1000", "mes": "2024-01", "reprocesar": false}'
```

Consultas C1 y C2 y, en Snowsight, E1 otra vez. **Pega:** cierre, tiempo y la relación de C1 (debe ser 1).

## 6. El CREATE TABLE en Snowsight y el DAG completo desde la interfaz

En Snowsight, ejecuta `USE ROLE BIGDATA_DEV; USE WAREHOUSE BIGDATA_WH; USE DATABASE BIGDATA;` y el `CREATE TABLE IF NOT EXISTS BIGDATA.DEV.TARIFA_POR_MILLA_BARRIO` (el de `carga.py`, el mismo que imprime la Celda 34 y el error de `cargar_snowflake` si la tabla falta). El código nunca crea la tabla. En la interfaz, lanza `pipeline_taxi` con `code_editor`, `1000`, `2024-01` y **Reprocesar sin marcar**.

**Debe pasar:** `correr_bronze`, `correr_silver` y `correr_gold` terminan en segundos con `SE SALTÓ`; `cargar_snowflake` trabaja y registra. Después, E3 (`COUNT(*)`, `SUM(VIAJES)`) y E1.

**Pega:** la duración de cada tarea en el Grid, el log de `correr_bronze` (el `SE SALTÓ`) y el de `cargar_snowflake` completo, y E3: `SUM(VIAJES)` debe ser igual a las filas de silver (B1).

## 7. Resetear y correr todo otra vez: funciona una vez

Lanza `resetear_entorno` (`Conservar el crudo` marcada, `borrar dev`). Después `pipeline_taxi` con Reprocesar sin marcar.

**Pega:** el tiempo de cada tarea, que las cuatro dicen `REGISTRÓ`, y las consultas A1, B1 y C1 (un lote, relación 1) más E3.

## 8. `reprocesar=true`: los duplicados

Lanza `pipeline_taxi` con **Reprocesar marcado** (misma configuración). Después repite A1, B1, B2, C1, D1, D2, D3 y D4 de `02_duplicados_y_conciliacion.sql`, y E3 en Snowsight.

```bash
cd ~/bigdata && aws s3 ls "s3://bigdata-lake-$(aws sts get-caller-identity --query Account --output text)-us-east-2/dev/bronze/fhvhv/mes=2024-01/"
```

Lanza una **tercera** vez con Reprocesar marcado y repite A1, B1 y C1.

**Pega:** `aws s3 ls` (2 carpetas `lote=`, luego 3), el tiempo de cada corrida, y una tabla por corrida (1.ª, 2.ª, 3.ª) con: lotes (A1), filas de silver de viajes, clima y zonas (B1, B2), viajes de gold y la relación (C1) y `SUM(VIAJES)` en Snowflake. **Debe dar** silver ×1, ×2, ×3 y gold ×1, ×8, ×27; si no, pega lo que salió. Anota el resultado de D3 (huellas en 0).

## 9. Prueba de la solución del instructor, en una copia

**Nunca en el repositorio.** Con dev limpio (paso 7):

```bash
rm -rf /tmp/copia_clase07 && mkdir /tmp/copia_clase07
cd ~/bigdata && cp -R src tests pyproject.toml pipeline.yaml /tmp/copia_clase07/
cd ~/bigdata && bash <ruta-de-validacion>/contenido/clase07_solucion/aplicar_solucion.sh /tmp/copia_clase07
cd /tmp/copia_clase07 && PYTHONPATH=src ~/bigdata/.venv/bin/python -m pytest tests/test_pasos.py tests/test_equipo_bronze.py tests/test_equipo_silver.py -q -rs
```

**Pega:** el resumen de pytest de la copia (0 `PENDIENTE`). Si hay tiempo, corre el pipeline con la solución (cópiala sobre `src/pipeline/` en una rama aparte y revierte) y confirma que con `reprocesar=true` la relación de C1 sigue siendo 1.

## 10. `make correr` y Glue small

```bash
cd ~/bigdata && PYTHONPATH=src .venv/bin/python -m pipeline.run --paso silver
cd ~/bigdata && make -n correr PASO=silver COMPUTO=glue_small REPROCESAR=true
cd ~/bigdata && time make correr PASO=silver COMPUTO=glue_small
cd ~/bigdata && time make correr PASO=silver COMPUTO=glue_small REPROCESAR=true
```

Comprueba que corre el código de tu árbol (`code/dev/pipeline.zip`) y que `code/pipeline.zip` no cambia (`aws s3 ls s3://<lake>/code/ --recursive`).

**Pega:** encabezado y cierre de los comandos, las URL de Glue y del Spark UI, el tiempo de cada uno (el primero es el costo de arrancar Glue aunque se salte) y las fechas de `code/pipeline.zip` antes y después.

## 11. Dimensionamiento: las siete filas

Cada medida parte de un dev limpio (`resetear_entorno`, `Conservar el crudo`). Siete corridas: si falta tiempo, mide las filas 0, 1, 4 y 5.

```bash
cd ~/bigdata && time make correr LIMITE=1000 COMPUTO=code_editor
cd ~/bigdata && time make correr LIMITE=1000 COMPUTO=glue_small
cd ~/bigdata && time make correr LIMITE=100000 COMPUTO=code_editor
cd ~/bigdata && time make correr LIMITE=100000 COMPUTO=glue_small
cd ~/bigdata && time make correr LIMITE=todos COMPUTO=glue_small
cd ~/bigdata && time make correr LIMITE=todos COMPUTO=glue_medium
cd ~/bigdata && time make correr LIMITE=todos COMPUTO=glue_large
```

**Pega:** la tabla (tiempo `real` y el de cada paso del cierre), la duración del job de Glue frente al total, `free -h` en las filas de `code_editor`, y qué pasa con `LIMITE=todos COMPUTO=code_editor` (debe fallar diciendo que no cabe).

## 12. PR, CI, Deploy y prod (clase 8, no se hace el lunes)

```bash
cd ~/bigdata && git switch main && git pull && git switch -c ensayo-clase07-a-prod
cd ~/bigdata && echo "# Ensayo clase 7" >> src/pipeline/gold.py
cd ~/bigdata && make test
cd ~/bigdata && git add src/pipeline/gold.py && git commit -m "Ensayo clase 7: camino a prod"
cd ~/bigdata && git push -u origin ensayo-clase07-a-prod
```

Abre el PR (base `main` de **tu fork**), espera los cinco checks, aprueba con otra cuenta y haz merge; anota la hora de cada paso. Cuando el Deploy termine:

```bash
cd ~/bigdata && make estado
cd ~/bigdata && aws s3 ls "s3://bigdata-lake-$(aws sts get-caller-identity --query Account --output text)-us-east-2/dags/"
cd ~/bigdata && make airflow-local-down
cd ~/bigdata && make airflow-tunel
cd ~/bigdata && make airflow-password
```

Solo `pipeline_taxi` y `resetear_entorno` deben estar en `dags/`. En la UI de prod lanza `pipeline_taxi` con `glue_medium`, `todos`, `2024-01` y Reprocesar sin marcar; confirma que el formulario **no** ofrece `code_editor`, `1000` ni un campo de entorno. Valida con Athena (`01_tablas.sql` con `<ENTORNO>` = `prod`; consultas B1 y C1 con `prod_`) y con Snowflake:

```sql
USE ROLE BIGDATA_DEV;
USE WAREHOUSE BIGDATA_WH;
USE DATABASE BIGDATA;
SELECT TABLA, CAPA, MES, FILAS, COMPUTO, LIMITE, INICIO FROM BIGDATA.CONTROL_PROD.WATERMARK ORDER BY INICIO;
SELECT COUNT(*), SUM(VIAJES) FROM BIGDATA.PROD.TARIFA_POR_MILLA_BARRIO;
INSERT INTO BIGDATA.CONTROL_PROD.WATERMARK (TABLA, CAPA, MES) VALUES ('prueba', 'bronze', '2024-01');
SHOW GRANTS TO ROLE BIGDATA_DEV;
```

El `INSERT` **debe fallar**; si funciona, para y avisa (fallo grave de permisos). Cierra con `make airflow-off` y `make estado`.

**Pega:** la hora de cada paso (PR, cada check, merge, Deploy, VM, DAG de prod), el tiempo de cada tarea de prod, la salida del formulario de prod, los resultados de Athena y Snowflake (deben cuadrar entre sí; la corrida del 20 de noviembre dio 19 663 930 en bronze y 19 650 023 en silver), el texto exacto del error del `INSERT` y que `SHOW GRANTS` no trae `CREATE`, `INSERT` ni `DELETE` sobre `PROD` ni `CONTROL_PROD`.

## 13. Dejar todo como estaba

```bash
cd ~/bigdata && make airflow-local-down
cd ~/bigdata && git switch main && git branch -D ensayo-clase07-a-prod
cd ~/bigdata && git status --short
```

En Snowflake: `ALTER WAREHOUSE BIGDATA_WH SUSPEND;`. `make airflow-off` y `make estado`. En GitHub, borra la rama del ensayo.

**Pega:** `git status --short` (vacía) y `make estado`.

## Qué hacer con lo pegado

- Las cifras van a `validacion/contenido/clase07_medidas.md` (sección «Ensayo del Code Editor, clase 7»).
- Las que el deck dice «se anotan en el ensayo» (`N` y `M` de los cierres, tiempos de cada tarea y las siete filas del dimensionamiento) se actualizan en `curso/clase07/deck/slides.json` y se regenera con `cd ~/bigdata/curso && python3 _deck/build.py clase07/deck --sin-pptx` y `cd ~/bigdata/curso/clase07/deck && python3 generar_guion.py`.
- Si falla `--task-params`, si Athena no lee las carpetas `lote=`, o si el notebook escribe en S3, corrige antes de enviar las instrucciones a los estudiantes.
