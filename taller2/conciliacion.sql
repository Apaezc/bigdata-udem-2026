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
-- Regla: filas únicas de bronze - descartes de cada tipo = filas de silver.
-- =====================================================================

-- 1.1 Cuántas filas y cuántos lotes hay en bronze. Bronze guarda un lote nuevo en cada
--     reproceso, así que puede tener copias; silver debe quedarse con una sola.
SELECT
  count(*)                                              AS filas_bronze,
  count(DISTINCT "_hash_fila")                          AS filas_unicas_bronze,
  count(DISTINCT regexp_extract("$path", 'lote=([^/]+)', 1)) AS lotes
FROM bigdata_lake.dev_bronze_fhvhv
WHERE mes = '2024-01';
-- Resultado: filas_bronze = ____ · filas_unicas_bronze = ____ · lotes = ____
-- Interpretación: si hay más de un lote, filas_bronze es un múltiplo de las filas únicas
-- (son las copias del reproceso). La conciliación se hace sobre las filas ÚNICAS.

-- 1.2 Descartes por tipo, en cascada: cada fila cuenta en la PRIMERA regla de silver que no
--     cumple (el mismo orden de limpiar_viajes en src/pipeline/silver.py). Así ninguna fila se
--     cuenta dos veces y la suma de los tipos es exactamente el total descartado.
WITH unicas AS (
  SELECT *
  FROM (
    SELECT b.*,
           row_number() OVER (PARTITION BY "_hash_fila" ORDER BY "_fecha_ingesta") AS rn
    FROM bigdata_lake.dev_bronze_fhvhv b
    WHERE mes = '2024-01'
  )
  WHERE rn = 1
),
clasificadas AS (
  SELECT
    CASE
      WHEN pickup_datetime IS NULL                              THEN '1 sin hora de recogida'
      WHEN pulocationid IS NULL                                 THEN '2 sin zona de recogida'
      WHEN trip_miles IS NULL OR trip_miles <= 0                THEN '3 distancia <= 0 o nula'
      WHEN trip_miles >= 100                                    THEN '4 distancia >= 100 mi'
      WHEN base_passenger_fare IS NULL OR base_passenger_fare <= 0 THEN '5 tarifa base <= 0 o nula'
      WHEN trip_time IS NULL
        OR trip_time / 60.0 < 1 OR trip_time / 60.0 > 180       THEN '6 duración fuera de 1-180 min'
      WHEN pickup_datetime <  TIMESTAMP '2024-01-01 00:00:00'
        OR pickup_datetime >= TIMESTAMP '2024-02-01 00:00:00'   THEN '7 recogida fuera del mes'
      ELSE '0 pasa a silver'
    END AS destino
  FROM unicas
)
SELECT destino, count(*) AS filas
FROM clasificadas
GROUP BY destino
ORDER BY destino;
-- Resultado:
--   0 pasa a silver ............ ____
--   3 distancia <= 0 o nula .... ____
--   ... (un renglón por tipo que aparezca)
-- Interpretación: la fila "0 pasa a silver" debe ser IGUAL a las filas de silver de 1.3.
-- Si coincide, la diferencia bronze - silver queda explicada fila por fila. Una regla que no
-- descartó nada no aparece: quiere decir que ese dato venía bien.

-- 1.3 Filas de silver y comprobación de duplicados (deben ser iguales).
SELECT
  count(*)                     AS filas_silver,
  count(DISTINCT "_hash_fila") AS hashes_distintos
FROM bigdata_lake.dev_silver_fhvhv
WHERE mes = '2024-01';
-- Resultado: filas_silver = ____ · hashes_distintos = ____
-- Interpretación: iguales = silver no tiene duplicados (deduplicar funciona) y
-- filas_silver = "0 pasa a silver" de 1.2 = bronze -> silver cuadra.

-- 1.4 Tablas de referencia: no deben crecer al reprocesar.
SELECT 'clima' AS tabla, count(*) AS filas
FROM bigdata_lake.dev_silver_clima WHERE mes = '2024-01'
UNION ALL
SELECT 'taxi_zones', count(*) FROM bigdata_lake.dev_silver_taxi_zones;
-- Resultado: clima = ____ (esperado 31) · taxi_zones = ____ (esperado 265)
-- Interpretación: si dan 62 y 530 hay copias, y el cruce de enriquecer multiplicaría los viajes.


-- =====================================================================
-- PARTE 2 · SILVER -> GOLD (Athena)
-- Regla: filas de silver = SUMA de viajes de gold (gold agrupa; contar sus filas no sirve).
-- =====================================================================

-- 2.1 Tabla del equipo.
SELECT
  (SELECT count(*)    FROM bigdata_lake.dev_silver_fhvhv WHERE mes = '2024-01') AS filas_silver,
  (SELECT sum(viajes) FROM bigdata_lake.dev_gold_equipo_4_rango_distancia   WHERE mes = '2024-01') AS viajes_gold,
  (SELECT count(*)    FROM bigdata_lake.dev_gold_equipo_4_rango_distancia   WHERE mes = '2024-01') AS filas_gold;
-- Resultado: filas_silver = ____ · viajes_gold = ____ · filas_gold = ____
-- Interpretación: viajes_gold = filas_silver -> cuadra. Si viajes_gold es un múltiplo exacto
-- (x4, x8) silver trae copias y el cruce con zonas y clima las multiplicó.
-- La tabla del equipo no filtra viajes: todo viaje de silver cae en un rango (corto, medio o
-- largo), así que aquí no debe haber ninguna diferencia.

-- 2.1b Viajes por rango (para el informe): la suma de los tres debe dar viajes_gold.
SELECT rango_distancia, sum(viajes) AS viajes, count(DISTINCT fecha) AS dias
FROM bigdata_lake.dev_gold_equipo_4_rango_distancia
WHERE mes = '2024-01'
GROUP BY rango_distancia
ORDER BY rango_distancia;
-- Resultado: corto ____ · medio ____ · largo ____ (31 días cada uno)

-- 2.2 La misma comprobación con la tabla de la casa (sale de la misma corrida).
SELECT
  (SELECT count(*)    FROM bigdata_lake.dev_silver_fhvhv WHERE mes = '2024-01') AS filas_silver,
  (SELECT sum(viajes) FROM bigdata_lake.dev_gold_tarifa_por_milla_barrio
   WHERE mes = '2024-01')                                                       AS viajes_gold_casa;
-- Resultado: ____ · ____
-- Interpretación: las dos tablas de gold deben dar la misma suma de viajes.


-- =====================================================================
-- PARTE 3 · REPROCESO (Athena) · correr 1.1, 1.3 y 2.1 otra vez después de reprocesar el mes
-- =====================================================================
--   corrida             lotes   filas_silver   hashes_distintos   viajes_gold
--   1.ª corrida         1       ____           ____               ____
--   reprocesar = true   2       ____           ____               ____
-- Interpretación esperada: bronze sube a 2 lotes, pero silver y gold NO cambian. Esa es la
-- prueba de que deduplicar funciona: silver no hereda las copias de bronze.


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
-- Resultado: FILAS = ____ · VIAJES = ____
-- Interpretación: FILAS = filas_gold (2.1) = FILAS del registro gold (4.1), y
-- VIAJES = viajes_gold (2.1) = filas_silver (1.3). Si todo coincide, la cifra de la respuesta
-- viene de una tabla que conserva todos los viajes limpios, sin perder ni duplicar ninguno.


-- =====================================================================
-- RESUMEN DE LA CONCILIACIÓN (llenar al final)
-- =====================================================================
--   capa                     cifra                 valor     ¿cuadra con?
--   bronze (únicas)          filas                 ____
--   descartes de silver      filas (por tipo)      ____      bronze - descartes = silver
--   silver                   filas                 ____      = hashes distintos
--   gold (Athena)            suma de viajes        ____      = filas de silver
--   Snowflake                SUM(VIAJES)           ____      = suma de viajes de gold
-- =====================================================================
