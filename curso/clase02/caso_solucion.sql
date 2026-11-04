-- =====================================================================
-- MINI-CASO · SOLUCIÓN DE REFERENCIA (Big Data UdeM · Clase 2)
-- =====================================================================
--
-- Para contrastar tu trabajo después de intentarlo (caso.sql). Mismas vistas Q1 a Q4 con la
-- respuesta escrita. Después corre caso_verificacion.sql: debe dar OK en las cuatro y RESUMEN
-- "4 de 4". La lectura del perfil de Q4 no tiene una solución única: ver la rúbrica al final.
--
-- =====================================================================
-- PASO 0 · PREPARACIÓN (igual que en caso.sql)
-- QUÉ HACER: selecciona desde USE ROLE hasta ALTER SESSION SET USE_CACHED_RESULT = FALSE; y pulsa ▶.
-- =====================================================================

USE ROLE ACCOUNTADMIN;

-- WAREHOUSE: el cómputo que ejecuta las consultas; se factura por segundo mientras está encendido.
-- AUTO_SUSPEND = 60 lo apaga tras 60 s sin uso y AUTO_RESUME lo enciende al consultar.
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

-- TU BASE DE TRABAJO: CURSO es la base de datos y CASO el esquema donde se guardan Q1 a Q4.
CREATE DATABASE IF NOT EXISTS CURSO;
CREATE SCHEMA IF NOT EXISTS CURSO.CASO;
USE SCHEMA CURSO.CASO;

-- Sin caché de resultados en esta sesión: cada corrida genera su propio Query Profile.
-- Para releer el perfil de una consulta ya ejecutada, repite esta línea y vuelve a correrla.
ALTER SESSION SET USE_CACHED_RESULT = FALSE;


-- =====================================================================
-- Q1 · ¿Cuánto vendió cada región en 1995?  (en clase)
-- =====================================================================
-- Columnas: REGION, PEDIDOS, MONTO_TOTAL

CREATE OR REPLACE VIEW Q1 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT R.R_NAME AS REGION, COUNT(*) AS PEDIDOS, SUM(O.O_TOTALPRICE) AS MONTO_TOTAL
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS O JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.CUSTOMER C ON O.O_CUSTKEY = C.C_CUSTKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.NATION N ON C.C_NATIONKEY = N.N_NATIONKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.REGION R ON N.N_REGIONKEY = R.R_REGIONKEY
WHERE O.O_ORDERDATE >= '1995-01-01' AND O.O_ORDERDATE < '1996-01-01'
GROUP BY R.R_NAME
ORDER BY MONTO_TOTAL DESC, REGION
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM Q1;  -- mira tu resultado


-- =====================================================================
-- Q2 · ¿Qué naciones superan 600 000 pedidos?  (después de clase)
-- =====================================================================
-- Columnas: NACION, PEDIDOS, MONTO_TOTAL

CREATE OR REPLACE VIEW Q2 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT N.N_NAME AS NACION, COUNT(*) AS PEDIDOS, SUM(O.O_TOTALPRICE) AS MONTO_TOTAL
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS O JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.CUSTOMER C ON O.O_CUSTKEY = C.C_CUSTKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.NATION N ON C.C_NATIONKEY = N.N_NATIONKEY
GROUP BY N.N_NAME
HAVING COUNT(*) > 600000
ORDER BY PEDIDOS DESC, NACION
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM Q2;  -- mira tu resultado


-- =====================================================================
-- Q3 · ¿Cuántos clientes de cada región nunca hicieron un pedido?  (después de clase)
-- =====================================================================
-- Columnas: REGION, CLIENTES_SIN_PEDIDOS

CREATE OR REPLACE VIEW Q3 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT R.R_NAME AS REGION, COUNT(*) AS CLIENTES_SIN_PEDIDOS
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.CUSTOMER C JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.NATION N ON C.C_NATIONKEY = N.N_NATIONKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.REGION R ON N.N_REGIONKEY = R.R_REGIONKEY
LEFT JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS O ON C.C_CUSTKEY = O.O_CUSTKEY
WHERE O.O_ORDERKEY IS NULL
GROUP BY R.R_NAME
ORDER BY CLIENTES_SIN_PEDIDOS DESC, REGION
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM Q3;  -- mira tu resultado


-- =====================================================================
-- Q4 · ¿Qué modo de envío mueve más importe en cada región?  (en clase)
-- =====================================================================
-- Columnas: REGION, MODO_ENVIO, LINEAS, IMPORTE_LINEAS

CREATE OR REPLACE VIEW Q4 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT R.R_NAME AS REGION, L.L_SHIPMODE AS MODO_ENVIO, COUNT(*) AS LINEAS,
       SUM(L.L_EXTENDEDPRICE) AS IMPORTE_LINEAS
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM L JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS O ON L.L_ORDERKEY = O.O_ORDERKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.CUSTOMER C ON O.O_CUSTKEY = C.C_CUSTKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.NATION N ON C.C_NATIONKEY = N.N_NATIONKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.REGION R ON N.N_REGIONKEY = R.R_REGIONKEY
GROUP BY R.R_NAME, L.L_SHIPMODE
ORDER BY REGION, IMPORTE_LINEAS DESC, MODO_ENVIO
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM Q4;  -- mira tu resultado


-- =====================================================================
-- LECTURA DEL PERFIL DE Q4 · rúbrica (no se verifica)
-- =====================================================================
-- Datos de referencia (SF10, X-Small, 3 ejecuciones consecutivas; tus cifras variarán un poco):
--   TableScan LINEITEM: 393 581 216 bytes (0.39 GB), 116 de 116 micro-particiones; 60.6 % del
--   tiempo en la primera ejecución (lectura desde almacenamiento remoto), 8.9 % y 6.7 % en la
--   segunda y tercera (datos en el caché del warehouse).
--   TableScan ORDERS: 91 621 504 bytes, 32 de 32.  TableScan CUSTOMER: 5 546 752 bytes, 16 de 16.
--   Tiempo total: 5.69, 5.90 y 2.66 s. Operador dominante en las ejecuciones 2 y 3: Aggregate o
--   Join (26.8 % a 31.7 %).
-- Rúbrica: no hay un único operador correcto. Es válida cualquier respuesta que cite el porcentaje
-- que se ve en pantalla y distinga si el dato venía del caché del warehouse (estadística
-- "Percentage scanned from cache" del TableScan). Costo de la corrida: créditos = segundos x
-- créditos por hora / 3600 (X-Small = 1 crédito/h; 5.69 s son 0.0016 créditos).
-- Propuestas válidas para leer menos: filtrar por una columna agrupada (en SF10, L_ORDERKEY;
-- L_SHIPDATE no poda: 116 de 116), leer menos columnas, agregar antes de unir (clase 3).
