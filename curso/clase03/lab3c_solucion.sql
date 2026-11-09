-- =====================================================================
-- LAB 3C · SOLUCIÓN DE REFERENCIA (Big Data UdeM · Clase 3)
-- =====================================================================
--
-- Para contrastar tu trabajo después de intentarlo (lab3c.sql). Mismos objetos C1 a C8 con la
-- respuesta escrita. Corre el Paso 0, el Paso 1 y luego cada bloque. Después corre
-- lab3c_verificacion.sql: debe dar OK en los ocho ejercicios, MARCA en OK y RESUMEN "5 de 5".
--
-- =====================================================================
-- PASO 0 · PREPARACIÓN (igual que en lab3c.sql)
-- QUÉ HACER: selecciona desde USE ROLE hasta USE SCHEMA CURSO.LAB3C; y pulsa ▶. No uses Run All
-- en la parte de ejercicios.
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

-- BASE DE EJEMPLO TPC-H: si ya existe, este comando no hace nada.
CREATE DATABASE IF NOT EXISTS SNOWFLAKE_SAMPLE_DATA FROM SHARE SFC_SAMPLES.SAMPLE_DATA;

-- TU BASE DE TRABAJO: CURSO es la base de datos y LAB3C el esquema donde se guardan tus objetos.
CREATE DATABASE IF NOT EXISTS CURSO;
CREATE SCHEMA IF NOT EXISTS CURSO.LAB3C;
USE SCHEMA CURSO.LAB3C;


-- =====================================================================
-- PASO 1 · MARCA DE LA CARGA (igual que en lab3c.sql)
-- =====================================================================

ALTER SESSION SET QUERY_TAG = 'LAB3C';


-- =====================================================================
-- EJERCICIO C1 ★ · Dimensión de cliente: nación y región en la misma fila
-- =====================================================================
-- Columnas: CLIENTE_KEY, C_NAME, C_MKTSEGMENT, N_NAME, R_NAME

CREATE OR REPLACE TABLE DIM_CLIENTE AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT C.C_CUSTKEY AS CLIENTE_KEY, C.C_NAME, C.C_MKTSEGMENT, N.N_NAME, R.R_NAME
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER C
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION N ON C.C_NATIONKEY = N.N_NATIONKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION R ON N.N_REGIONKEY = R.R_REGIONKEY
-- ▲▲ hasta aquí ▲▲
;
SELECT COUNT(*) AS FILAS FROM DIM_CLIENTE;
SELECT * FROM DIM_CLIENTE LIMIT 5;  -- mira tu resultado


-- =====================================================================
-- EJERCICIO C2 ★ · Dimensión de fechas (ya resuelta)
-- =====================================================================
-- Columnas: FECHA, ANIO, MES

CREATE OR REPLACE TABLE DIM_FECHA AS
WITH r AS (SELECT MIN(O_ORDERDATE) AS MINF, MAX(O_ORDERDATE) AS MAXF
           FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS)
SELECT FECHA, YEAR(FECHA) AS ANIO, MONTH(FECHA) AS MES
FROM (SELECT DATEADD('day', ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1, MINF) AS FECHA
      FROM r, TABLE(GENERATOR(ROWCOUNT => 3000))
      QUALIFY FECHA <= MAXF);
SELECT COUNT(*) AS FILAS, MIN(FECHA) AS PRIMERA, MAX(FECHA) AS ULTIMA FROM DIM_FECHA;
SELECT * FROM DIM_FECHA ORDER BY FECHA LIMIT 5;  -- mira tu resultado


-- =====================================================================
-- EJERCICIO C3 ★ · Tabla de hechos con el grano declarado
-- =====================================================================
-- Columnas: L_ORDERKEY, L_LINENUMBER, CLIENTE_KEY, FECHA, PRODUCTO_KEY, L_QUANTITY, L_EXTENDEDPRICE, L_DISCOUNT, INGRESO

CREATE OR REPLACE TABLE FACT_LINEITEM AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT L.L_ORDERKEY, L.L_LINENUMBER,
       O.O_CUSTKEY AS CLIENTE_KEY,
       O.O_ORDERDATE AS FECHA,
       L.L_PARTKEY AS PRODUCTO_KEY,
       L.L_QUANTITY, L.L_EXTENDEDPRICE, L.L_DISCOUNT,
       L.L_EXTENDEDPRICE * (1 - L.L_DISCOUNT) AS INGRESO
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM L
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O ON L.L_ORDERKEY = O.O_ORDERKEY
-- ▲▲ hasta aquí ▲▲
;
SELECT COUNT(*) AS FILAS FROM FACT_LINEITEM;
SELECT * FROM FACT_LINEITEM LIMIT 5;  -- mira tu resultado


-- =====================================================================
-- LECTURA DEL COSTO · respuesta de referencia (no se califica)
-- =====================================================================
WITH H AS (
  SELECT REGEXP_SUBSTR(TRIM(REGEXP_REPLACE(REGEXP_REPLACE(QUERY_TEXT, $$--[^\n]*$$, ''), $$\s+$$, ' ')),
                       $$CREATE (OR REPLACE )?TABLE [\w.]+$$, 1, 1, 'i') AS PASO,
         ROUND(EXECUTION_TIME / 1000, 2) AS SEGUNDOS,
         QUERY_ID,
         START_TIME
  FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY(RESULT_LIMIT => 1000,
             END_TIME_RANGE_START => DATEADD('hour', -3, CURRENT_TIMESTAMP())))
  WHERE QUERY_TAG = 'LAB3C'
    AND QUERY_TYPE = 'CREATE_TABLE_AS_SELECT'
    AND DATABASE_NAME = CURRENT_DATABASE()
    AND SCHEMA_NAME = 'LAB3C'
)
SELECT PASO, SEGUNDOS, QUERY_ID
FROM H
QUALIFY ROW_NUMBER() OVER (PARTITION BY PASO ORDER BY START_TIME DESC) = 1
ORDER BY SEGUNDOS DESC, PASO;

-- Paso más caro: FACT_LINEITEM, unos 2 s en X-Small (3 corridas de prueba, 8 nov. 2026: 2.0 s);
--   los demás pasos tardan entre 0.5 y 1.5 s.
-- Operador que concentra el tiempo: CreateTableAsSelect, entre 71 y 98 % del tiempo de ejecución
--   (8 nov.: 93 a 98 % en 3 corridas; 9 nov.: 71 % y 92 %; evidencia.sql, bloque 35): es la escritura de las 6001215 filas del hecho. El Join pesa
--   entre 0 y 5 % y los dos TableScan casi nada.
-- Decisión (una respuesta defendible; otras también valen si se apoyan en el perfil): dejarlo
--   así. El hecho se carga una vez y el costo está en escribir, no en unir. Para cargas
--   posteriores, INSERT INTO ... SELECT solo del rango nuevo (por fecha) en lugar de recrear la
--   tabla. Con SF10 (59986052 filas) la misma carga tardó de 19.8 a 21.4 s (clase03_medidas.md,
--   M5 y M15); es una señal de cómo escala, no una tarifa.


-- =====================================================================
-- EJERCICIO C4 ★ · Ingreso por región y año con dos uniones
-- =====================================================================
-- Columnas: R_NAME, ANIO, INGRESO

CREATE OR REPLACE VIEW C4 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT D.R_NAME, T.ANIO, ROUND(SUM(F.INGRESO), 2) AS INGRESO
FROM FACT_LINEITEM F
JOIN DIM_CLIENTE D ON F.CLIENTE_KEY = D.CLIENTE_KEY
JOIN DIM_FECHA T ON F.FECHA = T.FECHA
GROUP BY D.R_NAME, T.ANIO
ORDER BY D.R_NAME, T.ANIO
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM C4;  -- mira tu resultado


-- =====================================================================
-- EJERCICIO C5 ★ · Controles de filas y de grano
-- =====================================================================
-- Columnas: CONTROL, VALOR

CREATE OR REPLACE VIEW C5 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT 'filas' AS CONTROL, COUNT(*) AS VALOR
FROM FACT_LINEITEM
UNION ALL
SELECT 'grano', COUNT(DISTINCT L_ORDERKEY * 10 + L_LINENUMBER)
FROM FACT_LINEITEM
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM C5;  -- mira tu resultado


-- =====================================================================
-- EJERCICIO C6 ★★ · Dimensión de producto y las marcas con más ingreso
-- =====================================================================
-- Columnas: PRODUCTO_KEY, P_NAME, P_BRAND, P_TYPE | P_BRAND, INGRESO

CREATE OR REPLACE TABLE DIM_PRODUCTO AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT P_PARTKEY AS PRODUCTO_KEY, P_NAME, P_BRAND, P_TYPE
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.PART
-- ▲▲ hasta aquí ▲▲
;
SELECT COUNT(*) AS FILAS FROM DIM_PRODUCTO;
SELECT * FROM DIM_PRODUCTO LIMIT 5;  -- mira tu resultado

CREATE OR REPLACE VIEW C6 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT P.P_BRAND, ROUND(SUM(F.INGRESO), 2) AS INGRESO
FROM FACT_LINEITEM F
JOIN DIM_PRODUCTO P ON F.PRODUCTO_KEY = P.PRODUCTO_KEY
GROUP BY P.P_BRAND
ORDER BY INGRESO DESC
LIMIT 5
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM C6;  -- mira tu resultado


-- =====================================================================
-- EJERCICIO C7 ★★ · Grano mezclado: la medida del pedido infla la suma
-- =====================================================================
-- Columnas: SUMA_PEDIDOS, SUMA_INFLADA, VECES

CREATE OR REPLACE VIEW C7 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT (SELECT SUM(O_TOTALPRICE) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS) AS SUMA_PEDIDOS,
       SUM(O.O_TOTALPRICE) AS SUMA_INFLADA,
       ROUND(SUM(O.O_TOTALPRICE) / (SELECT SUM(O_TOTALPRICE) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS), 1) AS VECES
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM L
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O ON L.L_ORDERKEY = O.O_ORDERKEY
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM C7;  -- mira tu resultado


-- =====================================================================
-- EJERCICIO C8 ★★★ · SCD tipo 2: la dimensión conserva la historia
-- =====================================================================
-- Columnas: R_NAME, PEDIDOS, INGRESO

CREATE OR REPLACE TABLE DIM_CLIENTE_SCD2 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT *
FROM VALUES
  (1, 102022, 'INDONESIA', 'ASIA',   '1992-01-01'::DATE, '1995-05-31'::DATE, FALSE),
  (2, 102022, 'FRANCE',    'EUROPE', '1995-06-01'::DATE, '9999-12-31'::DATE, TRUE)
  AS V(SK, CLIENTE_KEY, N_NAME, R_NAME, DESDE, HASTA, ES_ACTUAL)
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM DIM_CLIENTE_SCD2;

CREATE OR REPLACE VIEW C8 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT D.R_NAME, COUNT(DISTINCT F.L_ORDERKEY) AS PEDIDOS, ROUND(SUM(F.INGRESO), 2) AS INGRESO
FROM FACT_LINEITEM F
JOIN DIM_CLIENTE_SCD2 D ON F.CLIENTE_KEY = D.CLIENTE_KEY
                       AND F.FECHA BETWEEN D.DESDE AND D.HASTA
GROUP BY D.R_NAME
ORDER BY D.R_NAME
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM C8;  -- mira tu resultado


ALTER SESSION UNSET QUERY_TAG;
