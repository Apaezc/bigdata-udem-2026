-- =====================================================================
-- LAB 4 · SOLUCIÓN DE REFERENCIA (Big Data UdeM · Clase 4)
-- =====================================================================
--
-- Para contrastar tu trabajo después de intentarlo (lab4.sql). Mismos objetos (el stage, la
-- tabla y las vistas EJ2 a EJ7) con la respuesta escrita. Corre el Paso 0 y luego cada bloque.
-- Antes del bloque de E6, corre datos/dim_zona.sql y datos/festivos_2024.sql en el esquema
-- CURSO.LAB4 (instrucciones en E6 de lab4.sql). Después corre lab4_verificacion.sql: debe dar OK
-- en los seis ejercicios ★ y RESUMEN "6 de 6 ★ en OK". E7 da OK con los valores medidos en
-- Athena (abajo, los del ensayo de prueba: 46715 filas, 0 KB, 10 MB).
--
-- Ejecuta esta solución con Cmd/Ctrl+Enter, bloque a bloque, o con Run All en una hoja nueva.
-- Cada sentencia es idempotente salvo el segundo COPY INTO (E5), que debe responder
-- "Copy executed with 0 files processed.".
--
-- =====================================================================
-- PASO 0 · PREPARACIÓN (igual que en lab4.sql)
-- =====================================================================

USE ROLE ACCOUNTADMIN;

-- WAREHOUSE: el cómputo que ejecuta las consultas; se factura por segundo mientras está
-- encendido. AUTO_SUSPEND = 60 lo apaga tras 60 s sin uso y AUTO_RESUME lo enciende al consultar.
CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH
  WAREHOUSE_SIZE = XSMALL
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;
-- Si COMPUTE_WH ya existía (trial), se deja con suspensión a los 60 s.
ALTER WAREHOUSE COMPUTE_WH SET AUTO_SUSPEND = 60;
ALTER WAREHOUSE COMPUTE_WH SET AUTO_RESUME = TRUE;

USE WAREHOUSE COMPUTE_WH;

CREATE DATABASE IF NOT EXISTS CURSO;
CREATE SCHEMA IF NOT EXISTS CURSO.LAB4;
USE SCHEMA CURSO.LAB4;

-- =====================================================================
-- EJERCICIO 1 ★ · Formato de archivo y stage sobre el bucket público
-- =====================================================================
-- Objeto: stage LAKE_PUBLICO (tipo EXTERNAL, URL del paquete)

CREATE OR REPLACE FILE FORMAT PARQUET_PUB TYPE = PARQUET;
CREATE OR REPLACE STAGE LAKE_PUBLICO
  URL = 's3://bigdata-udem-2026-publico/paquete/gold/daily_zone_metrics/'
  FILE_FORMAT = PARQUET_PUB;

-- =====================================================================
-- EJERCICIO 2 ★ · Leer los archivos en el lugar con $1
-- =====================================================================
-- Columnas: FECHA, ZONA, EMPRESA, VIAJES

LIST @LAKE_PUBLICO;
SELECT $1 FROM @LAKE_PUBLICO (PATTERN => '.*mes=2024-01/.*[.]parquet') LIMIT 5;

CREATE OR REPLACE VIEW EJ2 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT $1:fecha::DATE AS FECHA, $1:zona::VARCHAR AS ZONA,
       $1:empresa::VARCHAR AS EMPRESA, $1:viajes::NUMBER AS VIAJES
FROM @LAKE_PUBLICO (PATTERN => '.*mes=2024-01/.*[.]parquet')
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ2 LIMIT 5;
SELECT COUNT(*) AS FILAS, SUM(VIAJES) AS VIAJES FROM EJ2;

-- =====================================================================
-- EJERCICIO 3 ★ · Tabla y un solo COPY INTO
-- =====================================================================
-- Objeto: tabla DAILY_ZONE_METRICS (8 columnas)

CREATE OR REPLACE TABLE DAILY_ZONE_METRICS (
  FECHA DATE, ZONA VARCHAR, EMPRESA VARCHAR, VIAJES NUMBER(38,0),
  INGRESO_TOTAL FLOAT, PROPINA_PROMEDIO FLOAT, DISTANCIA_PROMEDIO FLOAT, LLUVIA_MM FLOAT);

COPY INTO DAILY_ZONE_METRICS FROM @LAKE_PUBLICO
  PATTERN = '.*[.]parquet' MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;

SELECT COUNT(*) AS FILAS FROM DAILY_ZONE_METRICS;

-- =====================================================================
-- EJERCICIO 4 ★ · Conteos de control por mes
-- =====================================================================
-- Columnas: MES, FILAS, VIAJES

CREATE OR REPLACE VIEW EJ4 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT TO_CHAR(FECHA, 'YYYY-MM') AS MES, COUNT(*) AS FILAS, SUM(VIAJES) AS VIAJES
FROM DAILY_ZONE_METRICS
GROUP BY 1
ORDER BY 1
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ4;

-- =====================================================================
-- EJERCICIO 5 ★ · Repetir el COPY INTO no duplica
-- =====================================================================
-- Columnas: FILAS, ARCHIVOS_CARGADOS
-- La segunda ejecución, igual que la primera y sin FORCE, responde "Copy executed with 0 files processed."

COPY INTO DAILY_ZONE_METRICS FROM @LAKE_PUBLICO
  PATTERN = '.*[.]parquet' MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;

CREATE OR REPLACE VIEW EJ5 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT (SELECT COUNT(*) FROM DAILY_ZONE_METRICS) AS FILAS,
       (SELECT COUNT(DISTINCT FILE_NAME) FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
          TABLE_NAME => 'DAILY_ZONE_METRICS',
          START_TIME => DATEADD('hour', -24, CURRENT_TIMESTAMP())))) AS ARCHIVOS_CARGADOS
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ5;

-- =====================================================================
-- EJERCICIO 6 ★ · Controles de las tablas auxiliares
-- =====================================================================
-- Antes: corre datos/dim_zona.sql y datos/festivos_2024.sql en el esquema CURSO.LAB4.
-- Columnas: CONTROL, VALOR

CREATE OR REPLACE VIEW EJ6 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT 'zonas' AS CONTROL, COUNT(*) AS VALOR FROM DIM_ZONA
UNION ALL
SELECT 'festivos', COUNT(*) FROM FESTIVOS_2024
UNION ALL
SELECT 'nombres_repetidos', COUNT(*)
FROM (SELECT ZONA FROM DIM_ZONA GROUP BY ZONA HAVING COUNT(*) > 1)
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ6;

-- =====================================================================
-- EJERCICIO 7 ★★ · Reto de Athena (valores medidos en el ensayo de prueba)
-- =====================================================================
-- Columnas: FILAS_ATHENA, KB_ESCANEADOS, MB_FACTURADOS
-- Los tres números vienen de Athena (workgroup bigdata-wg, SELECT COUNT(*) sobre gold_publico):
-- 46715 filas; Data scanned = 0 bytes (así lo informó Athena en el ensayo de prueba para este
-- conteo); facturado = el mayor entre 10 MB y 0 MB redondeado = 10 MB.

CREATE OR REPLACE VIEW EJ7 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT 46715 AS FILAS_ATHENA, 0 AS KB_ESCANEADOS, 10 AS MB_FACTURADOS
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ7;
