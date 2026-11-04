-- =====================================================================
-- LAB 1 · SOLUCIÓN DE REFERENCIA (Big Data UdeM · Clase 2)
-- =====================================================================
-- Para revisar tu trabajo después de intentarlo. Intenta primero el
-- enunciado (lab1.sql). Mismas vistas, con la respuesta escrita.
--
-- Cada vista (EJn) es una consulta guardada con nombre. Compara tu
-- resultado con el de aquí, o corre lab1_verificacion.sql.
-- =====================================================================

-- =====================================================================
-- PASO 0 · PREPARACIÓN (igual que en lab1.sql)
-- QUÉ HACER: selecciona desde USE ROLE hasta USE SCHEMA CURSO.LAB1; y pulsa ▶.
-- No uses Run All en este archivo.
-- =====================================================================

-- ROL: los permisos con los que trabajas.
USE ROLE ACCOUNTADMIN;

-- WAREHOUSE: el motor que ejecuta las consultas. Se apaga solo tras 60 s sin uso.
CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH
  WAREHOUSE_SIZE = XSMALL
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;
-- Si COMPUTE_WH ya existía (trial), lo dejamos con apagado a los 60 s.
ALTER WAREHOUSE COMPUTE_WH SET AUTO_SUSPEND = 60 AUTO_RESUME = TRUE;

USE WAREHOUSE COMPUTE_WH;

-- BASE DE EJEMPLO TPC-H: si ya existe, no hace nada.
CREATE DATABASE IF NOT EXISTS SNOWFLAKE_SAMPLE_DATA FROM SHARE SFC_SAMPLES.SAMPLE_DATA;

-- TU BASE DE TRABAJO: CURSO.LAB1
CREATE DATABASE IF NOT EXISTS CURSO;
CREATE SCHEMA IF NOT EXISTS CURSO.LAB1;
USE SCHEMA CURSO.LAB1;


-- =====================================================================
-- EJERCICIO 1 ★ · SELECT, ORDER BY y LIMIT
-- =====================================================================
CREATE OR REPLACE VIEW EJ1 AS
SELECT C_CUSTKEY, C_NAME, C_ACCTBAL
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER
ORDER BY C_CUSTKEY
LIMIT 5;


-- =====================================================================
-- EJERCICIO 2 ★ · WHERE y COUNT(*)
-- =====================================================================
CREATE OR REPLACE VIEW EJ2 AS
SELECT COUNT(*) AS TOTAL_BUILDING
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER
WHERE C_MKTSEGMENT = 'BUILDING';


-- =====================================================================
-- EJERCICIO 3 ★ · WHERE con dos condiciones (AND)
-- =====================================================================
CREATE OR REPLACE VIEW EJ3 AS
SELECT O_ORDERKEY, O_ORDERSTATUS, O_TOTALPRICE
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_ORDERSTATUS = 'F' AND O_TOTALPRICE > 300000
ORDER BY O_ORDERKEY
LIMIT 5;


-- =====================================================================
-- EJERCICIO 4 ★ · Fechas en WHERE y COUNT(*)
-- =====================================================================
CREATE OR REPLACE VIEW EJ4 AS
SELECT COUNT(*) AS PEDIDOS_1996
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_ORDERDATE >= '1996-01-01' AND O_ORDERDATE < '1997-01-01';


-- =====================================================================
-- EJERCICIO 5 ★ · SUM
-- =====================================================================
CREATE OR REPLACE VIEW EJ5 AS
SELECT SUM(O_TOTALPRICE) AS TOTAL_URGENTE
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_ORDERPRIORITY = '1-URGENT';


-- =====================================================================
-- EJERCICIO 6 ★ · Query Profile (la parte del Query Profile no se verifica)
-- =====================================================================
CREATE OR REPLACE VIEW EJ6 AS
SELECT COUNT(*) AS PEDIDOS_CAROS
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_TOTALPRICE > 400000;

-- Corre esta línea y abre su Query Profile (cómo abrirlo: ver lab1.sql, EJERCICIO 6).
-- Anota las filas leídas del TableScan de ORDERS.
SELECT * FROM EJ6;


-- =====================================================================
-- EJERCICIO 7 ★★ · ORDER BY con desempate
-- =====================================================================
CREATE OR REPLACE VIEW EJ7 AS
SELECT O_ORDERKEY, O_CUSTKEY, O_TOTALPRICE
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
ORDER BY O_TOTALPRICE DESC, O_ORDERKEY
LIMIT 5;


-- =====================================================================
-- EJERCICIO 8 ★★ · IN y varias condiciones
-- =====================================================================
CREATE OR REPLACE VIEW EJ8 AS
SELECT C_CUSTKEY, C_NAME, C_MKTSEGMENT, C_ACCTBAL
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER
WHERE C_MKTSEGMENT IN ('MACHINERY', 'FURNITURE') AND C_ACCTBAL > 9000
ORDER BY C_ACCTBAL DESC, C_CUSTKEY
LIMIT 10;


-- =====================================================================
-- EJERCICIO 9 ★★ · Los más recientes primero
-- =====================================================================
CREATE OR REPLACE VIEW EJ9 AS
SELECT O_ORDERKEY, O_ORDERDATE, O_ORDERPRIORITY
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_ORDERPRIORITY = '1-URGENT'
ORDER BY O_ORDERDATE DESC, O_ORDERKEY
LIMIT 5;


-- =====================================================================
-- EJERCICIO 10 ★★★ · Reto: GROUP BY e INFORMATION_SCHEMA
-- =====================================================================
CREATE OR REPLACE VIEW EJ10 AS
SELECT TABLE_NAME AS TABLA_NOMBRE, COUNT(*) AS NUM_COLUMNAS
FROM SNOWFLAKE_SAMPLE_DATA.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'TPCH_SF1'
GROUP BY TABLE_NAME
ORDER BY NUM_COLUMNAS DESC, TABLA_NOMBRE
LIMIT 3;
