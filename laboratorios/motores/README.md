# Laboratorio: mismo pipeline, dos motores (sesión 7)

Ejecuta **el mismo código** de silver y gold (`src/pipeline`) en dos motores y compara:

| | AWS Glue (Spark sobre S3) | Snowpark Connect (Spark traducido a SQL de Snowflake) |
|---|---|---|
| Dónde corre | Cluster Spark de Glue (`dev`: 2 workers G.1X) | Warehouse de Snowflake (XS) |
| Dónde viven los datos | Parquet en S3 | Tablas de Snowflake |
| Cómo se cobra | DPU-hora (US$0.44) mientras corre el job | Créditos por segundo de warehouse encendido |

## Pasos

1. **Glue:** en el Airflow de dev (`make airflow-local`) lanza `pipeline_taxi` con `entorno=dev` y `mes=2024-01`.
   Anota la duración de `silver_dev` y `gold_dev` y, en la consola de Glue, `DPU-seconds` de cada run.
2. **Snowpark Connect** (en el Code Editor):
   ```bash
   cd ~/<tu-fork>
   python3 -m venv ~/.snowpark-venv && ~/.snowpark-venv/bin/pip install "snowpark-connect[jdk]" "pyspark==3.5.6" pyyaml
   mkdir -p ~/fhvhv && cd ~/fhvhv
   curl -sfO https://d37ci6vzurychx.cloudfront.net/trip-data/fhvhv_tripdata_2024-01.parquet
   curl -sfO https://d37ci6vzurychx.cloudfront.net/misc/taxi_zone_lookup.csv
   curl -sf -o open_meteo_2024-01.json "https://archive-api.open-meteo.com/v1/archive?latitude=40.71&longitude=-74.01&start_date=2024-01-01&end_date=2024-01-31&daily=precipitation_sum,temperature_2m_mean&timezone=America%2FNew_York"
   cd ~/<tu-fork>
   SNOWFLAKE_ROLE=BIGDATA_DEV SNOWFLAKE_WAREHOUSE=BIGDATA_WH \
     ~/.snowpark-venv/bin/python laboratorios/motores/snowpark_connect.py --datos ~/fhvhv --mes 2024-01
   ```
3. **Créditos** (Snowsight, unos minutos después):
   ```sql
   SELECT start_time, credits_used
   FROM TABLE(BIGDATA.INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY(
     DATEADD('hour', -2, CURRENT_TIMESTAMP()), CURRENT_TIMESTAMP(), 'BIGDATA_WH'));
   ```
4. Compara `BIGDATA.DEV.LAB_GOLD_SNOWPARK` con `BIGDATA.DEV.DAILY_ZONE_METRICS` (mismo mes): mismas filas y
   sumas; puede haber diferencias en el 2.º decimal de los promedios por redondeo (no compares con igualdad exacta).

## Tabla a completar

| Métrica | Glue (`dev`) | Snowpark Connect (XS) |
|---|---|---|
| Arranque (sesión / job) | | |
| Carga de datos | — (ya están en S3) | |
| Silver + gold + escritura | | |
| Costo (US$ o créditos) | | |
| Líneas de código cambiadas | 0 | 0 |
| Observabilidad (Spark UI / Query Profile) | | |
| ¿Dónde quedan los datos? ¿Cuánto cuesta moverlos? | | |

Preguntas: ¿cuándo conviene cada motor? ¿Qué pasa si Snowpark lee el Parquet crudo en cada paso en lugar de una
tabla? ¿Qué cambia con un warehouse S o M?

## Referencia del instructor (validación, 1 mes de FHVHV = 19.7 M filas)

| Fase | Glue `small` | Snowpark XS, sobre archivo crudo | Snowpark XS, sobre tabla cargada |
|---|---|---|---|
| Arranque | ~50 s (job) | ~10 s (sesión) | ~10 s |
| Carga | — | — (relee el archivo en cada acción) | 268 s (una vez; incluye subir 450 MB) |
| Silver + gold + escritura | ~10 s | 172 s | **14 s** |
| Costo | ~US$0.02 | ~0.1 créditos | ~0.08 créditos (casi todo la carga) |

Gold idéntico en los tres casos (15 909 filas). Lección: Snowflake procesa rápido lo que ya está en tablas; Glue
procesa archivos crudos en S3 sin moverlos.
