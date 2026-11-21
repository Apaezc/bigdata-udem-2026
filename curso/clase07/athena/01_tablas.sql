-- =====================================================================
-- CLASE 7 · Athena sobre el lake · 01 · Declarar las tablas (rutas por entorno)
-- =====================================================================
--
-- PROBLEMA
--   Antes, dev y prod compartían la carpeta bronze/ del bucket: una corrida en dev creaba un
--   lote nuevo que prod leía sin que nadie lo decidiera. Ahora cada entorno tiene sus propias
--   carpetas y no comparten ninguna:
--
--     s3://bigdata-lake-<CUENTA>-us-east-2/<ENTORNO>/<capa>/<tabla>/mes=AAAA-MM/
--
--   con <ENTORNO> = dev o prod. Este archivo declara en Athena las tablas de UN entorno, y el
--   NOMBRE de cada tabla empieza con el entorno (dev_silver_fhvhv_trips, prod_silver_fhvhv_trips),
--   así nunca confundes de cuál lees. Para tener los dos, ejecuta el archivo dos veces.
--
-- DÓNDE Y CÓMO SE EJECUTA
--   Consola de AWS > región US East (Ohio), us-east-2 > Athena > Query editor.
--     Workgroup:      bigdata-wg   (corta cualquier consulta que lea más de 1 GB)
--     Data source:    AwsDataCatalog
--     Database:       bigdata_lake
--   Athena ejecuta UNA sentencia por vez: pega cada bloque (de CREATE a ';') y pulsa Run.
--
-- QUÉ REEMPLAZAR (obligatorio, son DOS cosas)
--   En el editor de Athena sirve Ctrl+F / Cmd+F > Reemplazar todo:
--     <CUENTA>   por tu número de cuenta de 12 dígitos (el de `aws sts get-caller-identity`).
--     <ENTORNO>  por  prod  (el bronze del año completo que dejó make muestra) o por  dev
--                (el que dejó una corrida de pipeline_taxi en el Airflow del Code Editor).
--   Si no reemplazas <ENTORNO>, el CREATE falla: el signo < no es válido en un nombre de tabla.
--
-- QUÉ SE DECLARA (todo bajo s3://bigdata-lake-<CUENTA>-us-east-2/<ENTORNO>/)
--   bronze/_crudo/fhvhv/mes=AAAA-MM/fhvhv_tripdata_AAAA-MM.parquet   viajes, Parquet original
--   bronze/_crudo/clima/mes=AAAA-MM/open_meteo_AAAA-MM.json          clima, JSON original
--   bronze/_crudo/taxi_zones/taxi_zone_lookup.csv                    zonas, CSV original
--   silver/fhvhv_trips/pickup_date=AAAA-MM-DD/                       viajes limpios y enriquecidos
--   gold/daily_zone_metrics/mes=AAAA-MM/                             métricas diarias por zona y empresa
--
--   Bronze se declara sobre _crudo/ (los archivos tal como llegaron), NO sobre las carpetas
--   con lote=...: ahí el esquema trae cinco columnas de metadatos y cada reingesta agrega un
--   lote nuevo, así que las filas se repetirían.
--   Silver y gold existen cuando ya corriste esos pasos en ese entorno; si no, la tabla se crea
--   y devuelve 0 filas.
--
-- CÓMO SABER DE QUÉ BUCKET Y CARPETA ESTÁS LEYENDO
--   Athena sabe de qué archivo sale cada fila: la columna oculta "$path". El bloque 7 la
--   consulta y te muestra la ruta s3:// completa. Las rutas de abajo salen de la misma regla
--   que usa el código (src/pipeline/settings.py, función ruta_lake); la tabla completa de tu
--   entorno la imprime pio.donde_estoy("<ENTORNO>") en un notebook.
--
-- LAS TABLAS DE LA CLASE 6
--   Las tablas bronze_fhvhv, bronze_clima, bronze_taxi_zones, silver_fhvhv_trips y
--   gold_daily_zone_metrics (sin entorno en el nombre) apuntan a las carpetas del diseño
--   anterior (bronze/ en la raíz del bucket). Ya no tienen datos. Se borran con DROP TABLE
--   (el bloque 8); los archivos no se tocan porque las tablas son EXTERNAL.
--
-- POR QUÉ PROYECCIÓN DE PARTICIONES
--   Igual que en la clase 6: se le dice a Athena la regla (mes de 2024-01 a 2024-12, uno por
--   mes) y calcula las rutas al ejecutar la consulta. No hay particiones que registrar. Si la
--   consulta filtra por mes, Athena solo abre esas carpetas y paga solo esos bytes.
--
-- PRUEBA
--   Pendiente: ejecutar este archivo en la cuenta de pruebas después de regenerar el lake con
--   make muestra (ver docs/rutas_del_lake.md) y anotar aquí las cifras reales.
-- =====================================================================


-- 0. Base de datos. Terraform ya crea bigdata_lake con make deploy; esta línea es inocua si existe.
CREATE DATABASE IF NOT EXISTS bigdata_lake;


-- 1. Viajes FHVHV (Uber, Lyft...) en bronze, archivos originales de NYC TLC. Un archivo de
--    ~470 MB por mes (~19 a 21 millones de filas). EXTERNAL = si se borra la tabla, los archivos
--    quedan. trip_time está en segundos.
--    Dentro de un CREATE no se escriben comentarios con --: la consola de Athena falla con ellos.
CREATE EXTERNAL TABLE IF NOT EXISTS bigdata_lake.<ENTORNO>_bronze_fhvhv (
  hvfhs_license_num     string,
  dispatching_base_num  string,
  originating_base_num  string,
  request_datetime      timestamp,
  on_scene_datetime     timestamp,
  pickup_datetime       timestamp,
  dropoff_datetime      timestamp,
  pulocationid          int,
  dolocationid          int,
  trip_miles            double,
  trip_time             bigint,
  base_passenger_fare   double,
  tolls                 double,
  bcf                   double,
  sales_tax             double,
  congestion_surcharge  double,
  airport_fee           double,
  tips                  double,
  driver_pay            double,
  shared_request_flag   string,
  shared_match_flag     string,
  access_a_ride_flag    string,
  wav_request_flag      string,
  wav_match_flag        string
)
PARTITIONED BY (mes string)
STORED AS PARQUET
LOCATION 's3://bigdata-lake-<CUENTA>-us-east-2/<ENTORNO>/bronze/_crudo/fhvhv/'
TBLPROPERTIES (
  'projection.enabled'            = 'true',
  'projection.mes.type'           = 'date',
  'projection.mes.format'         = 'yyyy-MM',
  'projection.mes.range'          = '2024-01,2024-12',
  'projection.mes.interval'       = '1',
  'projection.mes.interval.unit'  = 'MONTHS',
  'storage.location.template'     = 's3://bigdata-lake-<CUENTA>-us-east-2/<ENTORNO>/bronze/_crudo/fhvhv/mes=${mes}/'
);


-- 2. Clima diario de Open-Meteo en bronze. El JSON trae listas paralelas dentro de "daily"
--    (fechas, lluvia, temperatura). Se declaran como arreglos y se "despliegan" con UNNEST al
--    consultar. Un archivo de ~1 KB por mes.
CREATE EXTERNAL TABLE IF NOT EXISTS bigdata_lake.<ENTORNO>_bronze_clima (
  latitude   double,
  longitude  double,
  timezone   string,
  daily      struct<time:array<string>,precipitation_sum:array<double>,temperature_2m_mean:array<double>>
)
PARTITIONED BY (mes string)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://bigdata-lake-<CUENTA>-us-east-2/<ENTORNO>/bronze/_crudo/clima/'
TBLPROPERTIES (
  'projection.enabled'            = 'true',
  'projection.mes.type'           = 'date',
  'projection.mes.format'         = 'yyyy-MM',
  'projection.mes.range'          = '2024-01,2024-12',
  'projection.mes.interval'       = '1',
  'projection.mes.interval.unit'  = 'MONTHS',
  'storage.location.template'     = 's3://bigdata-lake-<CUENTA>-us-east-2/<ENTORNO>/bronze/_crudo/clima/mes=${mes}/'
);


-- 3. Zonas de taxi (CSV, 265 filas). No tiene mes: es una tabla de referencia, sin particiones.
--    OpenCSVSerde entrega todo como texto; la primera línea es el encabezado y se salta.
CREATE EXTERNAL TABLE IF NOT EXISTS bigdata_lake.<ENTORNO>_bronze_taxi_zones (
  locationid    string,
  borough       string,
  zone          string,
  service_zone  string
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES ('separatorChar' = ',', 'quoteChar' = '"')
LOCATION 's3://bigdata-lake-<CUENTA>-us-east-2/<ENTORNO>/bronze/_crudo/taxi_zones/'
TBLPROPERTIES ('skip.header.line.count' = '1');


-- 4. Silver (viajes limpios, con cada columna convertida a su tipo de dato y enriquecidos).
--    Particionado por día de recogida. El rango de pickup_date cubre 2024; los días sin carpeta
--    devuelven 0 filas.
CREATE EXTERNAL TABLE IF NOT EXISTS bigdata_lake.<ENTORNO>_silver_fhvhv_trips (
  pu_location_id    int,
  pickup_datetime   timestamp,
  dropoff_datetime  timestamp,
  do_location_id    int,
  empresa           string,
  distancia_mi      double,
  duracion_min      double,
  tarifa_base       double,
  propina           double,
  pago_conductor    double,
  total_pagado      double,
  borough           string,
  lluvia_mm         double,
  temp_media_c      double,
  zona              string
)
PARTITIONED BY (pickup_date string)
STORED AS PARQUET
LOCATION 's3://bigdata-lake-<CUENTA>-us-east-2/<ENTORNO>/silver/fhvhv_trips/'
TBLPROPERTIES (
  'projection.enabled'                = 'true',
  'projection.pickup_date.type'       = 'date',
  'projection.pickup_date.format'     = 'yyyy-MM-dd',
  'projection.pickup_date.range'      = '2024-01-01,2024-12-31',
  'projection.pickup_date.interval'   = '1',
  'projection.pickup_date.interval.unit' = 'DAYS',
  'storage.location.template'         = 's3://bigdata-lake-<CUENTA>-us-east-2/<ENTORNO>/silver/fhvhv_trips/pickup_date=${pickup_date}/'
);


-- 5. Gold (métricas diarias por zona y empresa), particionado por mes.
CREATE EXTERNAL TABLE IF NOT EXISTS bigdata_lake.<ENTORNO>_gold_daily_zone_metrics (
  fecha               date,
  zona                string,
  empresa             string,
  viajes              bigint,
  ingreso_total       double,
  propina_promedio    double,
  distancia_promedio  double,
  lluvia_mm           double
)
PARTITIONED BY (mes string)
STORED AS PARQUET
LOCATION 's3://bigdata-lake-<CUENTA>-us-east-2/<ENTORNO>/gold/daily_zone_metrics/'
TBLPROPERTIES (
  'projection.enabled'            = 'true',
  'projection.mes.type'           = 'date',
  'projection.mes.format'         = 'yyyy-MM',
  'projection.mes.range'          = '2024-01,2024-12',
  'projection.mes.interval'       = '1',
  'projection.mes.interval.unit'  = 'MONTHS',
  'storage.location.template'     = 's3://bigdata-lake-<CUENTA>-us-east-2/<ENTORNO>/gold/daily_zone_metrics/mes=${mes}/'
);


-- 6. Verificación: las cinco tablas con el nombre de <ENTORNO> deben aparecer en la lista.
SHOW TABLES IN bigdata_lake;


-- 7. ¿De qué bucket y carpeta estoy leyendo? "$path" es la ruta s3:// completa del archivo.
--    Debe empezar con s3://bigdata-lake-<CUENTA>-us-east-2/<ENTORNO>/bronze/_crudo/fhvhv/.
--    Si ves otro entorno en la ruta, la tabla está mal declarada.
SELECT "$path" AS archivo, count(*) AS viajes
FROM bigdata_lake.<ENTORNO>_bronze_fhvhv
WHERE mes = '2024-01'
GROUP BY "$path";


-- 8. Opcional: borrar las tablas de la clase 6, que apuntan al diseño anterior (sin datos).
--    Cada una en su propia ejecución. Los archivos no se tocan.
-- DROP TABLE IF EXISTS bigdata_lake.bronze_fhvhv;
-- DROP TABLE IF EXISTS bigdata_lake.bronze_clima;
-- DROP TABLE IF EXISTS bigdata_lake.bronze_taxi_zones;
-- DROP TABLE IF EXISTS bigdata_lake.silver_fhvhv_trips;
-- DROP TABLE IF EXISTS bigdata_lake.gold_daily_zone_metrics;
