# Clase 6 · prueba en el Code Editor (solo instructor)

Esta prueba recorre la clase 6 en la máquina real del Code Editor, con Airflow dev corriendo ahí mismo. Ejecuta cada bloque en orden y copia la salida que pide la línea **«Pega»**. Lo que no sale como se espera también sirve: pégalo tal cual.

Tiempo estimado: unos 60 minutos. La descarga de enero o febrero de viajes pesa unos 450 MiB.

## 0. Traer la rama y revisar el entorno

```bash
cd ~/bigdata && git fetch origin && git checkout clase06-contenido && git pull
cd ~/bigdata && .venv/bin/python --version
```

Si la versión no es 3.12, ejecuta `cd ~/bigdata && make reparar-entorno` y vuelve a elegir el kernel `.venv`.

**Pega:** la versión de Python.

## 1. Athena sobre tu bronze (slides 11 a 22)

```bash
cd ~/bigdata && CUENTA=$(aws sts get-caller-identity --query Account --output text) && aws s3 ls s3://bigdata-lake-$CUENTA-us-east-2/bronze/
cd ~/bigdata && sed "s/<CUENTA>/$CUENTA/g" curso/clase06/athena/01_tablas.sql > ~/01_tablas_mio.sql && head -40 ~/01_tablas_mio.sql
```

En la consola de Athena (región us-east-2, workgroup `bigdata-wg`), pega y ejecuta `~/01_tablas_mio.sql`. Si tu bronze ya tiene la carpeta `_crudo/`, sigue el aviso del encabezado del archivo. Después ejecuta los pasos 1, 2, 8B y 9 de `curso/clase06/athena/02_explorar_bronze.sql`. El paso 8B es la consulta que choca con el límite de 1 GB.

**Pega:** lo que mostró `aws s3 ls`; y para cada consulta, el resultado, el tiempo y los *Data scanned*. Para el paso 8B, el estado y el mensaje de error.

## 2. Lab de silver y gold (slides 27 a 32)

```bash
mkdir -p ~/clase06_mis_notebooks && cp ~/bigdata/curso/clase06/lab_silver_gold_solucion.ipynb ~/clase06_mis_notebooks/
```

Abre la copia, elige el kernel `.venv` y ejecuta todas las celdas en orden (Run All).

**Pega:** las líneas de cada prueba (OK, PENDIENTE o REVISAR), la salida de las Celdas 9, 10 y 25, y cuánto tardó el notebook completo. Al terminar, cierra Spark con la Celda 26 y apaga el kernel (Kernel > Shut Down).

## 3. Encender Airflow dev y el primer vuelo (slides 33, 41 y 42 a 50)

```bash
cd ~/bigdata && make -n airflow-local
cd ~/bigdata && time bash scripts/airflow-local.sh up
cd ~/bigdata && make airflow-local-estado
```

Abre la interfaz en la ruta que imprime el comando (`/codeeditor/default/ports/8080/`). Entra con `admin` y la contraseña que imprimió. Activa `hola_airflow` y lánzalo con mes `2024-02`.

**Pega:** el tiempo del arranque, la salida de `airflow-local-estado`, y si `reintentar` se vio naranja (reintento) y luego verde. Después cambia `FALLAR_SIEMPRE = True` en `airflow/dags/hola_airflow.py`, guarda, espera unos segundos y lanza otra vez. **Pega:** cuántos segundos tardó la interfaz en tomar el cambio y el mensaje de error del registro. Vuelve a dejar `FALLAR_SIEMPRE = False`.

## 4. El DAG `ingesta_mensual` con funciones resueltas (slides 51 a 60)

Para probar sin escribir el lab, se usa la solución de la ingesta guardada en el bucket de la cuenta de prueba. **Esto cambia un archivo del repositorio: el paso 5 lo restaura.**

```bash
cd ~/bigdata && aws s3 cp s3://bigdata-lake-279160392814-us-east-2/tmp/instructor/ingesta_alumno_solucion.py src/pipeline/ingesta_alumno.py
cd ~/bigdata && .venv/bin/python -m pytest -q tests/test_ingesta_alumno.py
```

Borra los registros de prueba de la tabla de control, exporta las variables de Airflow y ejecuta los comandos a mano:

```bash
cd ~/bigdata && PYTHONPATH=src .venv/bin/python -c "from pipeline.watermark import borrar_registros_de_prueba as b; [print(t, b(t)) for t in ['prueba_taxi_zones','prueba_clima','prueba_fhvhv','prueba_fhvhv_trips','prueba_daily_zone_metrics']]"
export AIRFLOW_HOME="$HOME/.airflow-local/home" PATH="$HOME/.airflow-local/venv/bin:$PATH" AIRFLOW__CORE__DAGS_FOLDER="$HOME/bigdata/airflow/dags" PYTHONPATH="$HOME/bigdata/airflow" AIRFLOW__CORE__LOAD_EXAMPLES=false
cd ~/bigdata && airflow dags reserialize && airflow dags list && airflow dags list-import-errors
cd ~/bigdata && time airflow tasks test ingesta_mensual ingestar_zonas 2024-02-03 --task-params '{"mes": "2024-02", "reprocesar": false}'
```

Ahora la ejecución 1, con la memoria a la vista. Abre una segunda terminal y deja corriendo `watch -n 5 free -h`. En la primera:

```bash
cd ~/bigdata && time airflow dags test ingesta_mensual 2024-02-01 --conf '{"mes": "2024-02", "reprocesar": false}'
```

Ejecución 2: desde la interfaz, lanza `ingesta_mensual` con mes `2024-02` y reprocesar falso. Ejecución 3: lánzalo otra vez con reprocesar verdadero.

Consulta la tabla de control (Snowflake, Worksheets, o `snow sql`):

```sql
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE BIGDATA;
SELECT TABLA, CAPA, MES, FILAS, INICIO, REPROCESAR
FROM CONTROL.WATERMARK
WHERE TABLA LIKE 'prueba%' AND MES IN ('2024-02', 'sin_mes')
ORDER BY INICIO;
```

**Pega:** la salida de pytest; la de `dags list` y `list-import-errors`; la de `tasks test` con su tiempo; las líneas `DECISIÓN` y el tiempo de la ejecución 1; la memoria más baja que mostró `free -h` (columna *available*) y si apareció «database is locked»; qué dijeron las cinco tareas en las ejecuciones 2 y 3; y la tabla de la consulta.

## 5. Dejar todo como estaba

```bash
cd ~/bigdata && git checkout -- src/pipeline/ingesta_alumno.py airflow/dags/hola_airflow.py && git status --short
cd ~/bigdata && make airflow-local-down
```

En Snowflake: `ALTER WAREHOUSE COMPUTE_WH SUSPEND;`

**Pega:** la salida de `git status --short`, que debe quedar vacía.
