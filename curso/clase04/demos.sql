-- =====================================================================
-- CLASE 4 · Guion de demos en vivo del instructor (Snowsight)
-- =====================================================================
--
-- Numeración de slides: la del storyboard de la clase 4 (26 slides).
-- Las cifras salen de la corrida del 10 nov. 2026 en la cuenta de pruebas (XS), sobre el paquete
-- público; están anotadas en validacion/contenido/clase04_medidas.md. La demo de Athena
-- (slides 10 y 11) está en athena_demo.sql: se corre en la consola de AWS, no aquí.
--
-- PREPARACIÓN (antes de la clase, no en pantalla)
--   1. En tu cuenta de Snowflake corre lab4_solucion.sql completo (con datos/dim_zona.sql y
--      datos/festivos_2024.sql ya cargados en CURSO.LAB4). Deja listos el stage LAKE_PUBLICO y
--      las tablas DAILY_ZONE_METRICS, DIM_ZONA y FESTIVOS_2024 en CURSO.LAB4.
--   2. Esta hoja:
--        USE ROLE ACCOUNTADMIN;
--        USE WAREHOUSE COMPUTE_WH;      -- XSMALL, AUTO_SUSPEND = 60
--        CREATE SCHEMA IF NOT EXISTS CURSO.DEMO4;
--        USE SCHEMA CURSO.DEMO4;
--      Las demos leen las tablas de CURSO.LAB4 con la ruta completa; solo la demo 1 crea tablas
--      (en CURSO.DEMO4). Para borrarlas: ver el final del archivo.
--   3. Corre la DEMO 0 (crea CURSO.DEMO4 y el stage LAKE_DEMO).
--
-- PLAN B: si Snowsight no responde o una cifra se desvía, muestra la tabla de la slide y di
--   que se midió el 10 de noviembre de 2026. Los conteos y las sumas no cambian entre corridas.
-- =====================================================================


-- =====================================================================
-- DEMO 0 · Preparación de la hoja (antes de la clase; no en pantalla)
-- =====================================================================
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
CREATE SCHEMA IF NOT EXISTS CURSO.DEMO4;
USE SCHEMA CURSO.DEMO4;
-- Un stage propio para las demos: un stage de otro esquema busca su formato de archivo (PARQUET_PUB)
-- en el esquema actual y falla; este lleva el formato en línea, como en la slide 14.
CREATE OR REPLACE STAGE LAKE_DEMO
  URL = 's3://bigdata-udem-2026-publico/paquete/gold/daily_zone_metrics/'
  FILE_FORMAT = (TYPE = PARQUET);


-- =====================================================================
-- DEMO 1 · Cargar enero dos veces duplica sin avisar (slide 4)
-- Qué se muestra: sin memoria de carga, cada fila se repite y no hay error. FORCE = TRUE
--   hace lo mismo a propósito (ver también la demo 4).
-- Resultado esperado: 15909 filas y 19650023 viajes tras la primera carga; 31818 y 39300046
--   tras la segunda.
-- =====================================================================
CREATE OR REPLACE TABLE ENERO_DOBLE LIKE CURSO.LAB4.DAILY_ZONE_METRICS;
COPY INTO ENERO_DOBLE FROM @LAKE_DEMO
  PATTERN = '.*mes=2024-01/.*[.]parquet' MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;
SELECT COUNT(*) AS FILAS, SUM(VIAJES) AS VIAJES FROM ENERO_DOBLE;     -- 15909 · 19650023
COPY INTO ENERO_DOBLE FROM @LAKE_DEMO
  PATTERN = '.*mes=2024-01/.*[.]parquet' MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE FORCE = TRUE;
SELECT COUNT(*) AS FILAS, SUM(VIAJES) AS VIAJES FROM ENERO_DOBLE;     -- 31818 · 39300046


-- =====================================================================
-- DEMO 2 · Leer el Parquet en el lugar con un stage (slide 12)
-- Qué se muestra: LIST y SELECT $1 sobre el bucket público, sin cargar nada.
-- Resultado esperado: 6 archivos .parquet; cada fila de $1 es un objeto con las 8 claves
--   (distancia_promedio, empresa, fecha, ingreso_total, lluvia_mm, propina_promedio, viajes, zona).
-- =====================================================================
LIST @LAKE_DEMO;
SELECT $1 FROM @LAKE_DEMO (PATTERN => '.*mes=2024-01/.*[.]parquet') LIMIT 3;
SELECT $1:fecha::DATE AS FECHA, $1:zona::VARCHAR AS ZONA, $1:empresa::VARCHAR AS EMPRESA,
       $1:viajes::NUMBER AS VIAJES
FROM @LAKE_DEMO (PATTERN => '.*mes=2024-01/.*[.]parquet')
WHERE $1:zona::VARCHAR = 'JFK Airport' AND $1:fecha::DATE = '2024-01-24'
ORDER BY EMPRESA;                                                      -- Lyft 1965 · Uber 7265


-- =====================================================================
-- DEMO 3 · COPY INTO idempotente (slide 14)
-- Qué se muestra: el stage y el COPY INTO de la slide, sobre un esquema propio, y la segunda
--   ejecución.
-- Resultado esperado: la primera carga trae 6 archivos LOADED y 46715 filas; la segunda responde
--   «Copy executed with 0 files processed.» y la tabla sigue en 46715.
-- =====================================================================
CREATE OR REPLACE STAGE LAKE_DEMO
  URL = 's3://bigdata-udem-2026-publico/paquete/gold/daily_zone_metrics/'
  FILE_FORMAT = (TYPE = PARQUET);
CREATE OR REPLACE TABLE DAILY_ZONE_METRICS LIKE CURSO.LAB4.DAILY_ZONE_METRICS;

COPY INTO DAILY_ZONE_METRICS
FROM @LAKE_DEMO
PATTERN = '.*[.]parquet'
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;
SELECT COUNT(*) AS FILAS FROM DAILY_ZONE_METRICS;                      -- 46715

COPY INTO DAILY_ZONE_METRICS
FROM @LAKE_DEMO
PATTERN = '.*[.]parquet'
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;                               -- Copy executed with 0 files processed.
SELECT COUNT(*) AS FILAS FROM DAILY_ZONE_METRICS;                      -- 46715


-- =====================================================================
-- DEMO 4 · FORCE = TRUE duplica (slide 14)
-- Resultado esperado: 93430 filas (el doble de 46715).
-- =====================================================================
COPY INTO DAILY_ZONE_METRICS
FROM @LAKE_DEMO
PATTERN = '.*[.]parquet'
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
FORCE = TRUE;
SELECT COUNT(*) AS FILAS FROM DAILY_ZONE_METRICS;                      -- 93430
-- Recrear la tabla borra la memoria del COPY:
CREATE OR REPLACE TABLE DAILY_ZONE_METRICS LIKE CURSO.LAB4.DAILY_ZONE_METRICS;
COPY INTO DAILY_ZONE_METRICS FROM @LAKE_DEMO
  PATTERN = '.*[.]parquet' MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;    -- 6 archivos LOADED otra vez
SELECT COUNT(*) AS FILAS FROM DAILY_ZONE_METRICS;                      -- 46715


-- =====================================================================
-- DEMO 5 · Conteos de control por mes (slide 15, Lab 4)
-- Resultado esperado: 3 filas: 2024-01 15909 y 19650023; 2024-02 14889 y 19344724;
--   2024-03 15917 y 21273719. Total 46715 filas y 60268466 viajes.
-- =====================================================================
SELECT TO_CHAR(FECHA, 'YYYY-MM') AS MES, COUNT(*) AS FILAS, SUM(VIAJES) AS VIAJES
FROM CURSO.LAB4.DAILY_ZONE_METRICS
GROUP BY 1
ORDER BY 1;


-- =====================================================================
-- DEMO 6 · La lluvia se repite en cada fila del día (slides 16 y 18, trampa 1)
-- Resultado esperado: 514 filas, SUM(LLUVIA_MM) = 11153.8 y MAX(LLUVIA_MM) = 21.7.
-- =====================================================================
SELECT FECHA, COUNT(*) AS FILAS, SUM(LLUVIA_MM) AS SUMA, MAX(LLUVIA_MM) AS LLUVIA
FROM CURSO.LAB4.DAILY_ZONE_METRICS
WHERE FECHA = '2024-01-10'
GROUP BY FECHA;                                                        -- 514 · 11153.8 · 21.7

-- Días con lluvia por mes (contar días, no filas): enero 18 de 31, febrero 13 de 29, marzo 17 de 31
SELECT TO_CHAR(FECHA, 'YYYY-MM') AS MES, COUNT(DISTINCT FECHA) AS DIAS,
       COUNT(DISTINCT IFF(LLUVIA_MM > 0, FECHA, NULL)) AS DIAS_CON_LLUVIA
FROM CURSO.LAB4.DAILY_ZONE_METRICS
GROUP BY 1
ORDER BY 1;

-- Filas por día: entre 511 y 515 en enero, 510 a 516 en febrero y marzo
SELECT TO_CHAR(FECHA, 'YYYY-MM') AS MES, MIN(FILAS) AS MINIMO, MAX(FILAS) AS MAXIMO
FROM (SELECT FECHA, COUNT(*) AS FILAS FROM CURSO.LAB4.DAILY_ZONE_METRICS GROUP BY FECHA)
GROUP BY 1
ORDER BY 1;


-- =====================================================================
-- DEMO 7 · El promedio de promedios (slide 18, trampa 2)
-- Resultado esperado: dos filas de JFK (Lyft 1965 viajes y 4.05; Uber 7265 y 3.76); promedio
--   simple 3.905; ponderado 3.8217 (3.82).
-- =====================================================================
SELECT FECHA, ZONA, EMPRESA, VIAJES, PROPINA_PROMEDIO
FROM CURSO.LAB4.DAILY_ZONE_METRICS
WHERE ZONA = 'JFK Airport' AND FECHA = '2024-01-24'
ORDER BY EMPRESA;
SELECT AVG(PROPINA_PROMEDIO) AS PROMEDIO_SIMPLE,
       ROUND(SUM(PROPINA_PROMEDIO * VIAJES) / SUM(VIAJES), 4) AS PROMEDIO_PONDERADO
FROM CURSO.LAB4.DAILY_ZONE_METRICS
WHERE ZONA = 'JFK Airport' AND FECHA = '2024-01-24';                   -- 3.905 · 3.8217


-- =====================================================================
-- DEMO 8 · Los decimales no se comparan con = (slide 19, trampa 3)
-- Resultado esperado: FALSE sin ROUND y TRUE con ROUND(..., 2).
-- =====================================================================
SELECT 0.1::FLOAT + 0.2::FLOAT = 0.3::FLOAT AS IGUAL_SIN_ROUND,
       ROUND(0.1::FLOAT + 0.2::FLOAT, 2) = ROUND(0.3::FLOAT, 2) AS IGUAL_CON_ROUND;


-- =====================================================================
-- DEMO 9 · Un nombre de zona repetido duplica filas al unir (slide 19, trampa 4)
-- Resultado esperado: 2 nombres repetidos (Corona con LocationID 56 y 57; Governor's Island/
--   Ellis Island/Liberty Island con 103, 104 y 105); 262 combinaciones únicas; unir el gold con
--   DIM_ZONA por nombre pasa de 46715 a 46911 filas (+196) y de 60268466 a 60452731 viajes
--   (+184265, 0.3 %). Newark Airport tiene SERVICE_ZONE y BOROUGH = 'EWR'.
-- =====================================================================
SELECT ZONA, COUNT(*) AS LOCATION_IDS, LISTAGG(LOCATION_ID, ', ') WITHIN GROUP (ORDER BY LOCATION_ID) AS IDS
FROM CURSO.LAB4.DIM_ZONA
GROUP BY ZONA
HAVING COUNT(*) > 1;
SELECT COUNT(*) AS FILAS_UNICAS FROM (SELECT DISTINCT ZONA, BOROUGH, SERVICE_ZONE FROM CURSO.LAB4.DIM_ZONA);   -- 262

SELECT (SELECT COUNT(*) FROM CURSO.LAB4.DAILY_ZONE_METRICS) AS FILAS_ANTES,
       COUNT(*) AS FILAS_DESPUES,
       SUM(G.VIAJES) AS VIAJES_DESPUES
FROM CURSO.LAB4.DAILY_ZONE_METRICS G
JOIN CURSO.LAB4.DIM_ZONA Z ON Z.ZONA = G.ZONA;                         -- 46715 · 46911 · 60452731

-- Zonas del gold sin pareja en el lookup (el control con LEFT JOIN): deben ser 0
SELECT COUNT(DISTINCT G.ZONA) AS ZONAS_SIN_PAREJA
FROM CURSO.LAB4.DAILY_ZONE_METRICS G
LEFT JOIN CURSO.LAB4.DIM_ZONA Z ON Z.ZONA = G.ZONA
WHERE Z.ZONA IS NULL;                                                  -- 0

-- Aeropuertos por SERVICE_ZONE (caso C): JFK y LaGuardia; Newark está aparte
SELECT SERVICE_ZONE, BOROUGH, ZONA
FROM CURSO.LAB4.DIM_ZONA
WHERE SERVICE_ZONE IN ('Airports', 'EWR')
ORDER BY SERVICE_ZONE, ZONA;                                           -- Airports: JFK Airport, LaGuardia Airport · EWR: Newark Airport


-- =====================================================================
-- DEMO 10 · Una fila del hecho y los festivos (slides 17 y 20)
-- Resultado esperado: la fila de Lyft en JFK, 2024-01-24: 1965 viajes e ingreso 153097.03; el
--   grano fecha × zona × empresa da 15909 filas en enero. De enero a marzo hay 3 festivos
--   federales: 1 y 15 de enero y 19 de febrero, los tres lunes.
-- =====================================================================
SELECT * FROM CURSO.LAB4.DAILY_ZONE_METRICS
WHERE ZONA = 'JFK Airport' AND FECHA = '2024-01-24'
ORDER BY EMPRESA;
SELECT COUNT(*) AS FILAS_ENERO
FROM CURSO.LAB4.DAILY_ZONE_METRICS
WHERE FECHA < '2024-02-01';                                            -- 15909
SELECT FECHA, DAYNAME(FECHA) AS DIA, NOMBRE
FROM CURSO.LAB4.FESTIVOS_2024
WHERE FECHA < '2024-04-01'
ORDER BY FECHA;                                                        -- 2024-01-01, 2024-01-15, 2024-02-19 (lunes)


-- =====================================================================
-- LIMPIEZA (después de la clase)
-- =====================================================================
-- DROP SCHEMA IF EXISTS CURSO.DEMO4;     -- borra ENERO_DOBLE, DAILY_ZONE_METRICS y LAKE_DEMO de las demos
