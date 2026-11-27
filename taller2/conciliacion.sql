-- =====================================================================
-- TALLER 2 · conciliacion.sql · ¿Cuadran las cifras de una capa a la siguiente?
-- Rol: Modelador SQL (Andrea Páez Cardona) · Entorno: dev · Mes: 2024-01
-- =====================================================================
-- Recorrido: bronze -> silver -> gold -> Snowflake, más la tabla de control.
--   PARTE 1 a 3 se corren en ATHENA (workgroup bigdata-wg, base bigdata_lake, us-east-2),
--   una sentencia por vez.
--   PARTE 4 y 5 se corren en SNOWSIGHT.
--
-- Tabla del equipo: gold equipo_4_rango_distancia
--   Athena    : bigdata_lake.dev_gold_equipo_4_rango_distancia (se crea en la PARTE 0)
--   Snowflake : BIGDATA.DEV.EQUIPO_4_RANGO_DISTANCIA
--
-- Debajo de cada consulta hay un bloque "Resultado / Interpretación" para llenar con lo que
-- dé la corrida final (limite = todos, mes = 2024-01).
-- =====================================================================


-- =====================================================================
-- PARTE 0 · Tabla de Athena para el gold del equipo (una sola vez, en Athena)
-- Reemplazar <CUENTA> por el número de la cuenta de AWS de la anfitriona (12 dígitos), igual que
-- en curso/clase07/athena/01_tablas.sql. Solo lee los Parquet: no copia ni cambia nada.
-- =====================================================================
CREATE EXTERNAL TABLE IF NOT EXISTS bigdata_lake.dev_gold_equipo_4_rango_distancia (
  fecha               date,
  rango_distancia     string,
  lluvia_mm           double,
  viajes              bigint,
  distancia_total_mi  double,
  ingreso_total       double
)
PARTITIONED BY (mes string)
STORED AS PARQUET
LOCATION 's3://bigdata-lake-<CUENTA>-us-east-2/dev/gold/equipo_4_rango_distancia/'
TBLPROPERTIES (
  'projection.enabled'            = 'true',
  'projection.mes.type'           = 'date',
  'projection.mes.format'         = 'yyyy-MM',
  'projection.mes.range'          = '2024-01,2024-12',
  'projection.mes.interval'       = '1',
  'projection.mes.interval.unit'  = 'MONTHS',
  'storage.location.template'     = 's3://bigdata-lake-<CUENTA>-us-east-2/dev/gold/equipo_4_rango_distancia/mes=${mes}/'
);


-- =====================================================================
-- PARTE 1 · BRONZE -> SILVER (Athena)
-- Regla: filas del crudo - descartes de cada tipo - duplicados = filas de silver.
-- LÍMITE: el workgroup bigdata-wg corta toda consulta que lea más de 1 GB. Por eso aquí no se
-- lee la columna _hash_fila (64 caracteres x 19,6 millones de filas pesa más de 1 GB): los lotes
-- se cuentan con _id_lote y los descartes se clasifican sobre el CRUDO, que es una sola copia
-- del archivo de la TLC (bronze = crudo + metadatos, una vez por lote).
-- =====================================================================

-- 1.0 Tabla de Athena para el crudo (una sola vez).
CREATE EXTERNAL TABLE IF NOT EXISTS bigdata_lake.dev_crudo_fhvhv (
  hvfhs_license_num string, dispatching_base_num string, originating_base_num string,
  request_datetime timestamp, on_scene_datetime timestamp, pickup_datetime timestamp,
  dropoff_datetime timestamp, pulocationid int, dolocationid int, trip_miles double,
  trip_time bigint, base_passenger_fare double, tolls double, bcf double, sales_tax double,
  congestion_surcharge double, airport_fee double, tips double, driver_pay double,
  shared_request_flag string, shared_match_flag string, access_a_ride_flag string,
  wav_request_flag string, wav_match_flag string
)
PARTITIONED BY (mes string)
STORED AS PARQUET
LOCATION 's3://bigdata-lake-015962475040-us-east-2/dev/bronze/_crudo/fhvhv/'
TBLPROPERTIES (
  'projection.enabled' = 'true', 'projection.mes.type' = 'date',
  'projection.mes.format' = 'yyyy-MM', 'projection.mes.range' = '2024-01,2024-12',
  'projection.mes.interval' = '1', 'projection.mes.interval.unit' = 'MONTHS',
  'storage.location.template' = 's3://bigdata-lake-015962475040-us-east-2/dev/bronze/_crudo/fhvhv/mes=${mes}/'
);

-- 1.1 Lotes de bronze: cada reproceso guarda una copia completa del mes.
SELECT "_id_lote", count(*) AS filas
FROM bigdata_lake.dev_bronze_fhvhv
WHERE mes = '2024-01'
GROUP BY "_id_lote"
ORDER BY filas;
-- Resultado:
--   20261127T210739Z_b0dc77   19 663 930
--   20261127T212312Z_3b2b7b   19 663 930
-- Interpretación: dos lotes idénticos = la 2.ª corrida (reprocesar = true) guardó el mes otra
-- vez. Cada lote tiene las mismas filas que el crudo (1.2): bronze no pierde ni agrega filas.

-- 1.2 Descartes por tipo, en cascada, sobre el crudo: cada fila cuenta en la PRIMERA regla de
--     silver que no cumple (el orden de limpiar_viajes en src/pipeline/silver.py). Así ninguna
--     fila se cuenta dos veces y la suma de los tipos es el total del crudo.
SELECT destino, count(*) AS filas
FROM (
  SELECT
    CASE
      WHEN pickup_datetime IS NULL                                 THEN '1 sin hora de recogida'
      WHEN pulocationid IS NULL                                    THEN '2 sin zona de recogida'
      WHEN trip_miles IS NULL OR trip_miles <= 0                   THEN '3 distancia <= 0 o nula'
      WHEN trip_miles >= 100                                       THEN '4 distancia >= 100 mi'
      WHEN base_passenger_fare IS NULL OR base_passenger_fare <= 0 THEN '5 tarifa base <= 0 o nula'
      WHEN trip_time IS NULL
        OR trip_time / 60.0 < 1 OR trip_time / 60.0 > 180          THEN '6 duración fuera de 1-180 min'
      WHEN pickup_datetime <  TIMESTAMP '2024-01-01 00:00:00'
        OR pickup_datetime >= TIMESTAMP '2024-02-01 00:00:00'      THEN '7 recogida fuera del mes'
      ELSE '0 pasa los filtros de silver'
    END AS destino
  FROM bigdata_lake.dev_crudo_fhvhv
  WHERE mes = '2024-01'
)
GROUP BY destino
ORDER BY destino;
-- Resultado:
--   0 pasa los filtros de silver ..... 19 650 023
--   3 distancia <= 0 o nula ..........      3 286
--   4 distancia >= 100 mi ............      1 660
--   5 tarifa base <= 0 o nula ........      7 331
--   6 duración fuera de 1-180 min ....      1 630
--   TOTAL (crudo) .................... 19 663 930   (= filas de cada lote de bronze)
--   Descartados ......................     13 907   (0,07 % del crudo)
-- Interpretación: 19 663 930 - 13 907 descartes = 19 650 023 = filas_silver (1.3): la diferencia
-- bronze -> silver queda explicada fila por fila. El descarte más grande es la tarifa base <= 0
-- (7 331 viajes, más de la mitad). No hubo viajes sin hora, sin zona ni fuera del mes, y no hubo
-- filas repetidas dentro del archivo (pasa los filtros = silver, sin diferencia).

-- 1.3 Silver después del reproceso.
SELECT count(*)                     AS filas_silver,
       count(DISTINCT "_id_lote")   AS lotes_en_silver,
       count_if("_id_lote" IS NULL) AS filas_sin_lote
FROM bigdata_lake.dev_silver_fhvhv
WHERE mes = '2024-01';
-- Resultado: filas_silver = 19 650 023 · lotes_en_silver = 2 · filas_sin_lote = 0
-- Interpretación: bronze tiene 2 copias del mes y silver tiene los viajes UNA vez: 19 650 023,
-- la misma cifra del paquete del curso (Taller 1). lotes_en_silver = 2 no es duplicado: de cada
-- par de copias, deduplicar conserva una cualquiera, unas del lote 1 y otras del lote 2.

-- 1.4 Tablas de referencia: no deben crecer al reprocesar.
SELECT 'clima' AS tabla, count(*) AS filas
FROM bigdata_lake.dev_silver_clima WHERE mes = '2024-01'
UNION ALL
SELECT 'taxi_zones', count(*) FROM bigdata_lake.dev_silver_taxi_zones;
-- Resultado: clima = 31 · taxi_zones = 265
-- Interpretación: un registro por día y uno por zona, aun después del reproceso: las tablas de
-- referencia no se duplicaron, así que el cruce de enriquecer no multiplica viajes.


-- =====================================================================
-- PARTE 2 · SILVER -> GOLD (Athena)
-- Regla: filas de silver = SUMA de viajes de gold (gold agrupa; contar sus filas no sirve).
-- =====================================================================

-- 2.1 Tabla del equipo.
SELECT
  (SELECT count(*)    FROM bigdata_lake.dev_silver_fhvhv WHERE mes = '2024-01') AS filas_silver,
  (SELECT sum(viajes) FROM bigdata_lake.dev_gold_equipo_4_rango_distancia   WHERE mes = '2024-01') AS viajes_gold,
  (SELECT count(*)    FROM bigdata_lake.dev_gold_equipo_4_rango_distancia   WHERE mes = '2024-01') AS filas_gold;
-- Resultado: filas_silver = 19 650 023 · viajes_gold = 19 650 023 · filas_gold = 93
-- Interpretación: cuadra exacto. Cada viaje limpio de silver está una sola vez en gold, y gold
-- tiene 93 filas = 31 días x 3 rangos (el grano esperado).
-- La tabla del equipo no filtra viajes: todo viaje de silver cae en un rango (corto, medio o
-- largo), así que aquí no debe haber ninguna diferencia.

-- 2.1b Viajes por rango (para el informe): la suma de los tres debe dar viajes_gold.
SELECT rango_distancia, sum(viajes) AS viajes, count(DISTINCT fecha) AS dias
FROM bigdata_lake.dev_gold_equipo_4_rango_distancia
WHERE mes = '2024-01'
GROUP BY rango_distancia
ORDER BY rango_distancia;
-- Resultado: corto 7 175 895 · medio 6 512 281 · largo 5 961 847 (31 días cada uno)
--            suma = 19 650 023. Corto 36,5 % · medio 33,1 % · largo 30,3 % de los viajes.

-- 2.2 La misma comprobación con la tabla de la casa (sale de la misma corrida).
SELECT
  (SELECT count(*)    FROM bigdata_lake.dev_silver_fhvhv WHERE mes = '2024-01') AS filas_silver,
  (SELECT sum(viajes) FROM bigdata_lake.dev_gold_tarifa_por_milla_barrio
   WHERE mes = '2024-01')                                                       AS viajes_gold_casa;
-- Resultado: 19 650 023 · 19 650 023
-- Interpretación: la tabla de la casa y la del equipo suman los mismos viajes: salen de la
-- misma corrida y ninguna pierde ni duplica viajes.


-- =====================================================================
-- PARTE 3 · REPROCESO: antes y después de deduplicar (evidencia en taller2/evidencia/)
-- =====================================================================
--   situación                                   lotes bronze   filas_silver    huella en silver
--   código viejo, 1.ª corrida completa          2 (1 de prueba) 19 651 023      ninguna (NULL)
--   código viejo, reprocesar = true             3              39 301 046      ninguna (NULL)
--   código del equipo, 1.ª corrida (tras reset) 1              (sin captura)   todas
--   código del equipo, reprocesar = true        2              19 650 023      todas
-- Interpretación: con el código viejo, cada reproceso sumaba otra copia del mes en silver
-- (2 x 19 650 023 + 1 000 del lote de prueba = 39 301 046). Con agregar_metadatos y deduplicar,
-- bronze guarda 2 lotes pero silver queda en 19 650 023: el reproceso ya no duplica.


-- =====================================================================
-- PARTE 4 · TABLA DE CONTROL (Snowsight)
-- =====================================================================
USE ROLE BIGDATA_DEV;
USE WAREHOUSE BIGDATA_WH;
USE DATABASE BIGDATA;

-- 4.1 Último registro por (TABLA, CAPA, MES): reprocesar no borra la historia.
SELECT TABLA, CAPA, MES, FILAS, LEIDAS, COMPUTO, LIMITE, REPROCESAR, INICIO
FROM BIGDATA.CONTROL_DEV.WATERMARK
WHERE MES = '2024-01' OR MES IS NULL
QUALIFY ROW_NUMBER() OVER (PARTITION BY TABLA, CAPA, MES ORDER BY INICIO DESC) = 1
ORDER BY CAPA, TABLA;
-- Resultado: (pegar la tabla)
-- Interpretación: FILAS de silver/fhvhv = filas_silver de 1.3; FILAS de gold/<tabla> = filas_gold
-- de 2.1 (en gold, FILAS cuenta grupos, no viajes).


-- =====================================================================
-- PARTE 5 · GOLD -> SNOWFLAKE (Snowsight)
-- =====================================================================

-- 5.1 Lo que quedó cargado en la tabla del equipo.
SELECT COUNT(*) AS FILAS, SUM(VIAJES) AS VIAJES
FROM BIGDATA.DEV.EQUIPO_4_RANGO_DISTANCIA;
-- Resultado: FILAS = 93 · VIAJES = 19 650 023 · DIAS = 31
-- Interpretación: FILAS = filas_gold (2.1) = FILAS del registro gold (4.1), y
-- VIAJES = viajes_gold (2.1) = filas_silver (1.3). Si todo coincide, la cifra de la respuesta
-- viene de una tabla que conserva todos los viajes limpios, sin perder ni duplicar ninguno.


-- =====================================================================
-- RESUMEN DE LA CONCILIACIÓN (llenar al final)
-- =====================================================================
--   capa                     cifra                 valor     ¿cuadra con?
--   crudo = cada lote bronze filas                 19 663 930
--   descartes de silver      filas (4 tipos)          13 907   crudo - descartes = silver
--   silver                   filas                19 650 023   igual tras reprocesar
--   gold equipo (Athena)     suma de viajes       19 650 023   = filas de silver (93 filas)
--   gold casa (Athena)       suma de viajes       19 650 023   = filas de silver
--   Snowflake                SUM(VIAJES)          19 650 023   = gold (93 filas, 31 días)
--
-- CONCLUSIÓN: de los 19 663 930 viajes del archivo de enero, silver descarta 13 907 (0,07 %) por
-- cuatro reglas de calidad y conserva 19 650 023. Esa misma cifra llega sin cambios a las dos
-- tablas de gold y a Snowflake, y no cambia al reprocesar el mes. La respuesta se calcula sobre
-- todos los viajes limpios, sin pérdidas ni duplicados.
-- =====================================================================
