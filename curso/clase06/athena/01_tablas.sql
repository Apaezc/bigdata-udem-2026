-- =====================================================================
-- CLASE 6 · Athena sobre el lake · 01 · Declarar las tablas
-- =====================================================================
--
-- PROBLEMA
--   La ingesta de la clase 5 dejó archivos en bronze, pero nadie los ha mirado. Para saber qué
--   trajo de verdad hay que consultarlos. Athena lee los archivos en S3 donde están, con SQL,
--   sin cargarlos en ninguna base. Antes de consultar hay que decirle al catálogo (Glue) dónde
--   están los archivos y qué columnas tienen: eso hace CREATE EXTERNAL TABLE.
--
-- DÓNDE Y CÓMO SE EJECUTA
--   Consola de AWS > región US East (Ohio), us-east-2 > Athena > Query editor.
--     Workgroup:      bigdata-wg   (corta cualquier consulta que lea más de 1 GB)
--     Data source:    AwsDataCatalog
--     Database:       bigdata_lake
--   Athena ejecuta UNA sentencia por vez: pega cada bloque (de CREATE a ';') y pulsa Run.
--   Desde la terminal sirve lo mismo:
--     aws athena start-query-execution --work-group bigdata-wg --region us-east-2 \
--       --query-execution-context Database=bigdata_lake,Catalog=AwsDataCatalog \
--       --query-string "<la sentencia>"
--
-- CÓMO REEMPLAZAR EL BUCKET (obligatorio)
--   El bucket del lake lleva el número de tu cuenta: bigdata-lake-<CUENTA>-us-east-2.
--   Cada LOCATION de este archivo trae un marcador en lugar del número. Antes de ejecutar, reemplázalo por
--   tu número de cuenta de 12 dígitos (el mismo de `aws sts get-caller-identity`). En el editor
--   de Athena sirve Ctrl+F / Cmd+F > Reemplazar todo.
--
-- QUÉ SE DECLARA
--   Bronze, en el FORMATO ANTERIOR de la ingesta (la copia cruda, sin lote=):
--     bronze/fhvhv/mes=AAAA-MM/fhvhv_tripdata_AAAA-MM.parquet   viajes, Parquet original
--     bronze/clima/mes=AAAA-MM/open_meteo_AAAA-MM.json          clima, JSON original
--     bronze/taxi_zones/taxi_zone_lookup.csv                    zonas, CSV original
--   Silver y gold de dev (si ya los construiste con make): dev/silver/ y dev/gold/.
--   OJO: si tu bucket se llenó con la versión nueva de make muestra (la que escribe lote=...), esos
--   archivos crudos se movieron a bronze/_crudo/<fuente>/... (mismos archivos, mismos bytes).
--   En ese caso cambia en las tres tablas de bronze "/bronze/<fuente>/" por
--   "/bronze/_crudo/<fuente>/" en LOCATION y en storage.location.template. No apuntes la tabla
--   a la carpeta con lote=: ahí el esquema es otro (trae cinco columnas de metadatos) y cada
--   reingesta agrega un lote nuevo, así que las filas se repetirían.
--
-- POR QUÉ PROYECCIÓN DE PARTICIONES
--   El catálogo no descubre solo las carpetas mes=AAAA-MM. Sin proyección habría que correr
--   MSCK REPAIR TABLE cada vez que llegue un mes. Con proyección le dices a Athena la regla
--   (mes va de 2024-01 a 2024-12, uno por mes) y calcula las rutas al ejecutar la consulta:
--   no hay particiones que registrar ni que mantener. Un mes sin carpeta devuelve 0 filas.
--   Si la consulta filtra por mes, Athena solo abre esas carpetas (poda de particiones) y
--   paga solo esos bytes.
--
-- PRUEBA
--   Cada tabla se creó y se consultó en la cuenta de pruebas (ver validacion/contenido/
--   clase06_medidas.md). Las cifras reales de cada consulta están allí.
-- =====================================================================


-- 0. Base de datos. Terraform ya crea bigdata_lake con make deploy; esta línea es inocua si existe.
CREATE DATABASE IF NOT EXISTS bigdata_lake;


-- 1. Viajes FHVHV (Uber, Lyft...) en bronze. Parquet crudo: las columnas son las del archivo
--    original de NYC TLC, sin transformar. Un archivo de ~470 MB por mes (~19 a 21 millones de filas).
--    EXTERNAL = si se borra la tabla, los archivos quedan. trip_time está en segundos.
--    Dentro de un CREATE no se escriben comentarios con --: la consola de Athena falla con ellos.
CREATE EXTERNAL TABLE IF NOT EXISTS bigdata_lake.bronze_fhvhv (
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
LOCATION 's3://bigdata-lake-<CUENTA>-us-east-2/bronze/fhvhv/'
TBLPROPERTIES (
  'projection.enabled'            = 'true',
  'projection.mes.type'           = 'date',
  'projection.mes.format'         = 'yyyy-MM',
  'projection.mes.range'          = '2024-01,2024-12',
  'projection.mes.interval'       = '1',
  'projection.mes.interval.unit'  = 'MONTHS',
  'storage.location.template'     = 's3://bigdata-lake-<CUENTA>-us-east-2/bronze/fhvhv/mes=${mes}/'
);


-- 2. Clima diario de Open-Meteo en bronze. El JSON trae listas paralelas dentro de "daily"
--    (una lista de fechas, una de lluvia, una de temperatura). Se declaran como arreglos y se
--    "despliegan" con UNNEST al consultar. Un archivo de ~1 KB por mes.
CREATE EXTERNAL TABLE IF NOT EXISTS bigdata_lake.bronze_clima (
  latitude   double,
  longitude  double,
  timezone   string,
  daily      struct<time:array<string>,precipitation_sum:array<double>,temperature_2m_mean:array<double>>
)
PARTITIONED BY (mes string)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://bigdata-lake-<CUENTA>-us-east-2/bronze/clima/'
TBLPROPERTIES (
  'projection.enabled'            = 'true',
  'projection.mes.type'           = 'date',
  'projection.mes.format'         = 'yyyy-MM',
  'projection.mes.range'          = '2024-01,2024-12',
  'projection.mes.interval'       = '1',
  'projection.mes.interval.unit'  = 'MONTHS',
  'storage.location.template'     = 's3://bigdata-lake-<CUENTA>-us-east-2/bronze/clima/mes=${mes}/'
);


-- 3. Zonas de taxi (CSV, 265 filas). No tiene mes: es una tabla de referencia, sin particiones.
--    OpenCSVSerde entrega todo como texto; la primera línea es el encabezado y se salta.
CREATE EXTERNAL TABLE IF NOT EXISTS bigdata_lake.bronze_taxi_zones (
  locationid    string,
  borough       string,
  zone          string,
  service_zone  string
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES ('separatorChar' = ',', 'quoteChar' = '"')
LOCATION 's3://bigdata-lake-<CUENTA>-us-east-2/bronze/taxi_zones/'
TBLPROPERTIES ('skip.header.line.count' = '1');


-- 4. Silver de dev (viajes limpios, con cada columna convertida a su tipo de dato y enriquecidos). Requiere haber corrido silver en dev:
--    existe si en tu bucket hay dev/silver/fhvhv_trips/. Particionado por día de recogida.
--    El rango de pickup_date cubre 2024; los días sin carpeta devuelven 0 filas.
CREATE EXTERNAL TABLE IF NOT EXISTS bigdata_lake.silver_fhvhv_trips (
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
LOCATION 's3://bigdata-lake-<CUENTA>-us-east-2/dev/silver/fhvhv_trips/'
TBLPROPERTIES (
  'projection.enabled'                = 'true',
  'projection.pickup_date.type'       = 'date',
  'projection.pickup_date.format'     = 'yyyy-MM-dd',
  'projection.pickup_date.range'      = '2024-01-01,2024-12-31',
  'projection.pickup_date.interval'   = '1',
  'projection.pickup_date.interval.unit' = 'DAYS',
  'storage.location.template'         = 's3://bigdata-lake-<CUENTA>-us-east-2/dev/silver/fhvhv_trips/pickup_date=${pickup_date}/'
);


-- 5. Gold de dev (métricas diarias por zona y empresa). Requiere dev/gold/daily_zone_metrics/.
CREATE EXTERNAL TABLE IF NOT EXISTS bigdata_lake.gold_daily_zone_metrics (
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
LOCATION 's3://bigdata-lake-<CUENTA>-us-east-2/dev/gold/daily_zone_metrics/'
TBLPROPERTIES (
  'projection.enabled'            = 'true',
  'projection.mes.type'           = 'date',
  'projection.mes.format'         = 'yyyy-MM',
  'projection.mes.range'          = '2024-01,2024-12',
  'projection.mes.interval'       = '1',
  'projection.mes.interval.unit'  = 'MONTHS',
  'storage.location.template'     = 's3://bigdata-lake-<CUENTA>-us-east-2/dev/gold/daily_zone_metrics/mes=${mes}/'
);


-- 6. Verificación: las cinco tablas deben aparecer.
SHOW TABLES IN bigdata_lake;
