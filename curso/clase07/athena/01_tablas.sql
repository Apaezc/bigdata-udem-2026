-- =====================================================================
-- CLASE 7 · Athena sobre el lake · 01 · Declarar las tablas (rutas por entorno)
-- =====================================================================
--
-- PROBLEMA
--   El pipeline escribe archivos en S3 y nadie los ha mirado. Para saber qué dejó cada paso
--   (cuántos lotes tiene bronze, cuántas filas tiene silver, cuántos viajes suma gold) hay que
--   consultarlos. Athena lee los archivos donde están, con SQL, sin cargarlos en ninguna base.
--   Antes hay que decirle al catálogo (Glue) dónde están y qué columnas traen: eso hace
--   CREATE EXTERNAL TABLE.
--
-- LAS RUTAS (las arma src/pipeline/herramientas/rutas.py, función ruta_lake; <ENTORNO> = dev o prod)
--   s3://bigdata-lake-<CUENTA>-us-east-2/<ENTORNO>/
--     bronze/fhvhv/mes=AAAA-MM/lote=<id>/        viajes, un lote por ingesta
--     bronze/clima/mes=AAAA-MM/lote=<id>/        clima, una fila por día
--     bronze/taxi_zones/lote=<id>/               zonas (sin mes)
--     bronze/_crudo/...                          los archivos tal como se descargaron
--     silver/fhvhv/mes=AAAA-MM/                  espejo limpio de los viajes
--     silver/clima/mes=AAAA-MM/                  espejo limpio del clima
--     silver/taxi_zones/                         espejo limpio de las zonas
--     gold/tarifa_por_milla_barrio/mes=AAAA-MM/  la tabla de gold de la casa
--
--   Dev y prod no comparten ninguna carpeta. Cada tabla de Athena lleva el entorno y la capa en
--   el nombre (dev_bronze_fhvhv, prod_silver_fhvhv), así nunca confundes de cuál lees.
--
-- DÓNDE Y CÓMO SE EJECUTA
--   Consola de AWS > región US East (Ohio), us-east-2 > Athena > Query editor.
--     Workgroup:      bigdata-wg   (corta cualquier consulta que lea más de 1 GB)
--     Data source:    AwsDataCatalog
--     Database:       bigdata_lake
--   Athena ejecuta UNA sentencia por vez: pega cada bloque (de CREATE a ';') y haz clic en Run.
--
-- QUÉ REEMPLAZAR (obligatorio, son DOS cosas)
--   En el editor de Athena sirve Ctrl+F / Cmd+F > Reemplazar todo:
--     <CUENTA>   por tu número de cuenta de 12 dígitos (el de `aws sts get-caller-identity`).
--     <ENTORNO>  por  dev  (lo que escribe el pipeline desde tu Code Editor) o por  prod
--                (lo que escribe el DAG de la VM, después del PR y del CI/CD).
--   Si no reemplazas <ENTORNO>, el CREATE falla: el signo < no es válido en un nombre de tabla.
--   Desde la terminal hay un atajo (el último comando cuenta las marcas que quedan):
--     cd ~/bigdata
--     CUENTA=$(aws sts get-caller-identity --query Account --output text)
--     sed "s/<CUENTA>/$CUENTA/g; s/<ENTORNO>/dev/g" curso/clase07/athena/01_tablas.sql > ~/01_tablas_dev.sql
--
-- POR QUÉ UN LOTE NUEVO APARECE SIN VOLVER A EJECUTAR NADA
--   Las tablas de bronze apuntan a la carpeta del MES (mes=AAAA-MM/), no a un lote concreto.
--   Athena lista esa carpeta cada vez que corres una consulta y lee todo lo que hay debajo, en
--   las subcarpetas lote=<id>/. Cuando el pipeline escribe un lote nuevo, la siguiente consulta
--   ya lo ve: no hay que tocar el DDL. Así se ven los dos lotes de la demostración de duplicados.
--   La columna oculta "$path" dice de qué archivo sale cada fila, y por tanto de qué lote
--   (el bloque 8 lo usa).
--
-- POR QUÉ PROYECCIÓN DE PARTICIONES
--   El catálogo no descubre solo las carpetas mes=AAAA-MM. Con proyección le dices a Athena la
--   regla (mes de 2024-01 a 2024-12, uno por mes) y calcula las rutas al ejecutar la consulta:
--   no hay particiones que registrar ni MSCK REPAIR que correr. Si la consulta filtra por mes,
--   Athena solo abre esa carpeta y paga solo esos bytes. Zonas no tiene mes: sin partición.
--
-- LAS COLUMNAS DE METADATOS
--   Bronze guarda, además de las columnas originales, _fecha_ingesta, _id_lote, _hash_fila,
--   _fuente y _archivo_origen SI agregar_metadatos (bronze.py) las agregó. Mientras esa función
--   no haga nada (problema a propósito de la clase), los archivos no las traen: las columnas
--   existen en la tabla de Athena pero salen NULL. Silver conserva _hash_fila, _id_lote y
--   _fecha_ingesta con la misma regla. Los nombres que empiezan con _ llevan comillas invertidas
--   en el CREATE y comillas dobles en el SELECT.
--
-- REGLAS DE ESTE ARCHIVO
--   Dentro de un CREATE no hay comentarios con -- (la consola de Athena falla con ellos) y los
--   tipos struct van en una sola línea.
--
-- LAS TABLAS DE LA CLASE 6
--   bronze_fhvhv, bronze_clima, bronze_taxi_zones, silver_fhvhv_trips y gold_daily_zone_metrics
--   (sin entorno en el nombre) apuntan al diseño anterior. Después de `make migrar-clase07` ya
--   no tienen datos. Se borran con DROP TABLE (el bloque 10); los archivos no se tocan porque
--   las tablas son EXTERNAL.
--
-- PRUEBA
--   Se ejecuta por primera vez en el ensayo de la clase 7: ver curso/clase07/prueba_ensayo.md,
--   donde se anotan las cifras reales y se confirma que un lote nuevo aparece sin recrear tablas.
-- =====================================================================


-- 0. Base de datos. Terraform ya crea bigdata_lake con make deploy; esta línea es inocua si existe.
CREATE DATABASE IF NOT EXISTS bigdata_lake;


-- 1. Bronze: viajes FHVHV. Columnas del archivo original de NYC TLC (trip_time en segundos) más
--    los cinco metadatos. Un archivo por lote; cada ingesta agrega una carpeta lote= nueva.
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
  wav_match_flag        string,
  `_fecha_ingesta`      timestamp,
  `_id_lote`            string,
  `_hash_fila`          string,
  `_fuente`             string,
  `_archivo_origen`     string
)
PARTITIONED BY (mes string)
STORED AS PARQUET
LOCATION 's3://bigdata-lake-<CUENTA>-us-east-2/<ENTORNO>/bronze/fhvhv/'
TBLPROPERTIES (
  'projection.enabled'            = 'true',
  'projection.mes.type'           = 'date',
  'projection.mes.format'         = 'yyyy-MM',
  'projection.mes.range'          = '2024-01,2024-12',
  'projection.mes.interval'       = '1',
  'projection.mes.interval.unit'  = 'MONTHS',
  'storage.location.template'     = 's3://bigdata-lake-<CUENTA>-us-east-2/<ENTORNO>/bronze/fhvhv/mes=${mes}/'
);


-- 2. Bronze: clima. Bronze ya lo guarda como una fila por día (fecha, lluvia en mm y temperatura).
CREATE EXTERNAL TABLE IF NOT EXISTS bigdata_lake.<ENTORNO>_bronze_clima (
  fecha              string,
  lluvia_mm          double,
  temperatura        double,
  `_fecha_ingesta`   timestamp,
  `_id_lote`         string,
  `_hash_fila`       string,
  `_fuente`          string,
  `_archivo_origen`  string
)
PARTITIONED BY (mes string)
STORED AS PARQUET
LOCATION 's3://bigdata-lake-<CUENTA>-us-east-2/<ENTORNO>/bronze/clima/'
TBLPROPERTIES (
  'projection.enabled'            = 'true',
  'projection.mes.type'           = 'date',
  'projection.mes.format'         = 'yyyy-MM',
  'projection.mes.range'          = '2024-01,2024-12',
  'projection.mes.interval'       = '1',
  'projection.mes.interval.unit'  = 'MONTHS',
  'storage.location.template'     = 's3://bigdata-lake-<CUENTA>-us-east-2/<ENTORNO>/bronze/clima/mes=${mes}/'
);


-- 3. Bronze: zonas de taxi (265 filas por lote, todo como texto). No tiene mes: la carpeta de
--    cada lote cuelga directo de bronze/taxi_zones/.
CREATE EXTERNAL TABLE IF NOT EXISTS bigdata_lake.<ENTORNO>_bronze_taxi_zones (
  locationid         string,
  borough            string,
  zone               string,
  service_zone       string,
  `_fecha_ingesta`   timestamp,
  `_id_lote`         string,
  `_hash_fila`       string,
  `_fuente`          string,
  `_archivo_origen`  string
)
STORED AS PARQUET
LOCATION 's3://bigdata-lake-<CUENTA>-us-east-2/<ENTORNO>/bronze/taxi_zones/';


-- 4. Silver: viajes limpios. Es el espejo de bronze/fhvhv: una fila por viaje que pasó los
--    filtros (distancia entre 0 y 100 millas, tarifa mayor que cero, duración entre 1 y 180
--    minutos), con cada columna en su tipo y la empresa con su nombre. Silver lee TODOS los
--    lotes de bronze del mes. Reemplaza la carpeta del mes en cada corrida.
CREATE EXTERNAL TABLE IF NOT EXISTS bigdata_lake.<ENTORNO>_silver_fhvhv (
  pickup_datetime   timestamp,
  dropoff_datetime  timestamp,
  pu_location_id    int,
  do_location_id    int,
  empresa           string,
  distancia_mi      double,
  duracion_min      double,
  tarifa_base       double,
  propina           double,
  pago_conductor    double,
  total_pagado      double,
  `_hash_fila`      string,
  `_id_lote`        string,
  `_fecha_ingesta`  timestamp,
  pickup_date       date
)
PARTITIONED BY (mes string)
STORED AS PARQUET
LOCATION 's3://bigdata-lake-<CUENTA>-us-east-2/<ENTORNO>/silver/fhvhv/'
TBLPROPERTIES (
  'projection.enabled'            = 'true',
  'projection.mes.type'           = 'date',
  'projection.mes.format'         = 'yyyy-MM',
  'projection.mes.range'          = '2024-01,2024-12',
  'projection.mes.interval'       = '1',
  'projection.mes.interval.unit'  = 'MONTHS',
  'storage.location.template'     = 's3://bigdata-lake-<CUENTA>-us-east-2/<ENTORNO>/silver/fhvhv/mes=${mes}/'
);


-- 4b. Silver: clima (una fila por día del mes).
CREATE EXTERNAL TABLE IF NOT EXISTS bigdata_lake.<ENTORNO>_silver_clima (
  fecha             date,
  lluvia_mm         double,
  temp_media_c      double,
  `_hash_fila`      string,
  `_id_lote`        string,
  `_fecha_ingesta`  timestamp
)
PARTITIONED BY (mes string)
STORED AS PARQUET
LOCATION 's3://bigdata-lake-<CUENTA>-us-east-2/<ENTORNO>/silver/clima/'
TBLPROPERTIES (
  'projection.enabled'            = 'true',
  'projection.mes.type'           = 'date',
  'projection.mes.format'         = 'yyyy-MM',
  'projection.mes.range'          = '2024-01,2024-12',
  'projection.mes.interval'       = '1',
  'projection.mes.interval.unit'  = 'MONTHS',
  'storage.location.template'     = 's3://bigdata-lake-<CUENTA>-us-east-2/<ENTORNO>/silver/clima/mes=${mes}/'
);


-- 4c. Silver: zonas de taxi (sin mes). LocationID ya es un entero.
CREATE EXTERNAL TABLE IF NOT EXISTS bigdata_lake.<ENTORNO>_silver_taxi_zones (
  locationid        int,
  borough           string,
  zone              string,
  service_zone      string,
  `_hash_fila`      string,
  `_id_lote`        string,
  `_fecha_ingesta`  timestamp
)
STORED AS PARQUET
LOCATION 's3://bigdata-lake-<CUENTA>-us-east-2/<ENTORNO>/silver/taxi_zones/';


-- 5. Gold de la casa: tarifa por milla por fecha, barrio y franja del día. La carpeta mes= es
--    solo partición física: todas las columnas, incluida fecha, van dentro de los Parquet
--    (Snowflake no lee columnas de partición).
CREATE EXTERNAL TABLE IF NOT EXISTS bigdata_lake.<ENTORNO>_gold_tarifa_por_milla_barrio (
  fecha               date,
  borough             string,
  franja              string,
  viajes              bigint,
  distancia_total_mi  double,
  ingreso_total       double,
  tarifa_por_milla    double
)
PARTITIONED BY (mes string)
STORED AS PARQUET
LOCATION 's3://bigdata-lake-<CUENTA>-us-east-2/<ENTORNO>/gold/tarifa_por_milla_barrio/'
TBLPROPERTIES (
  'projection.enabled'            = 'true',
  'projection.mes.type'           = 'date',
  'projection.mes.format'         = 'yyyy-MM',
  'projection.mes.range'          = '2024-01,2024-12',
  'projection.mes.interval'       = '1',
  'projection.mes.interval.unit'  = 'MONTHS',
  'storage.location.template'     = 's3://bigdata-lake-<CUENTA>-us-east-2/<ENTORNO>/gold/tarifa_por_milla_barrio/mes=${mes}/'
);


-- 6. Verificación: las siete tablas con el nombre de <ENTORNO> deben aparecer en la lista
--    (tres de bronze, tres de silver y una de gold).
SHOW TABLES IN bigdata_lake;


-- 7. ¿De qué bucket y carpeta estoy leyendo? "$path" es la ruta s3:// completa del archivo.
--    Debe empezar con s3://bigdata-lake-<CUENTA>-us-east-2/<ENTORNO>/bronze/fhvhv/mes=2024-01/lote=
--    Si ves otro entorno en la ruta, la tabla está mal declarada. Devuelve 0 filas si bronze
--    todavía no corrió en ese entorno.
SELECT "$path" AS archivo, count(*) AS filas
FROM bigdata_lake.<ENTORNO>_bronze_fhvhv
WHERE mes = '2024-01'
GROUP BY "$path";


-- 8. ¿De qué lote sale cada fila? El identificador del lote es la carpeta lote=<id> de la ruta
--    del archivo (funciona aunque _id_lote salga NULL). Con una ingesta hay un lote; cada
--    reproceso agrega otro SIN tocar esta tabla: vuelve a ejecutar esta consulta y aparece.
SELECT regexp_extract("$path", 'lote=([^/]+)', 1) AS lote, count(*) AS filas
FROM bigdata_lake.<ENTORNO>_bronze_fhvhv
WHERE mes = '2024-01'
GROUP BY regexp_extract("$path", 'lote=([^/]+)', 1)
ORDER BY lote;


-- 9. Opcional: el archivo CRUDO tal como se descargó, completo (no lo recorta limite). Sirve
--    para comparar contra lo que bronze guardó. Una tabla por fuente, sobre bronze/_crudo/.
CREATE EXTERNAL TABLE IF NOT EXISTS bigdata_lake.<ENTORNO>_crudo_fhvhv (
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


-- 10. Opcional: borrar las tablas de la clase 6, que apuntan al diseño anterior (sin datos).
--     Cada una en su propia ejecución. Los archivos no se tocan.
-- DROP TABLE IF EXISTS bigdata_lake.bronze_fhvhv;
-- DROP TABLE IF EXISTS bigdata_lake.bronze_clima;
-- DROP TABLE IF EXISTS bigdata_lake.bronze_taxi_zones;
-- DROP TABLE IF EXISTS bigdata_lake.silver_fhvhv_trips;
-- DROP TABLE IF EXISTS bigdata_lake.gold_daily_zone_metrics;
-- Si ya habías declarado las tablas de una versión anterior de este archivo (bronze sobre
-- _crudo, silver_fhvhv_trips o gold_daily_zone_metrics con el entorno en el nombre), bórralas
-- también: apuntan a carpetas que ya no se escriben.
-- DROP TABLE IF EXISTS bigdata_lake.<ENTORNO>_silver_fhvhv_trips;
-- DROP TABLE IF EXISTS bigdata_lake.<ENTORNO>_gold_daily_zone_metrics;
