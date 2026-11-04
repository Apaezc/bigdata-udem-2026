-- =====================================================================
-- LAB 2 · SOLUCIÓN DE REFERENCIA (Big Data UdeM · Clase 2)
-- =====================================================================
--
-- Para contrastar tu trabajo después de intentarlo (lab2.sql). Mismas vistas EJ1 a EJ10 con la
-- respuesta escrita. Corre el Paso 0 y luego cada bloque, o compara tu resultado con la línea
-- "Debes ver" de lab2.sql. Después corre lab2_verificacion.sql: debe dar OK en los diez
-- ejercicios y RESUMEN "6 de 6".
--
-- =====================================================================
-- PASO 0 · PREPARACIÓN (igual que en lab2.sql)
-- QUÉ HACER: selecciona desde USE ROLE hasta USE SCHEMA CURSO.LAB2; y pulsa ▶. No uses Run All
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

-- TU BASE DE TRABAJO: CURSO es la base de datos y LAB2 el esquema donde se guardan tus vistas.
CREATE DATABASE IF NOT EXISTS CURSO;
CREATE SCHEMA IF NOT EXISTS CURSO.LAB2;
USE SCHEMA CURSO.LAB2;


-- =====================================================================
-- EJERCICIO 1 ★ · GROUP BY y COUNT(*)
-- =====================================================================
-- Columnas: O_ORDERSTATUS, PEDIDOS

CREATE OR REPLACE VIEW EJ1 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT O_ORDERSTATUS, COUNT(*) AS PEDIDOS
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
GROUP BY O_ORDERSTATUS
ORDER BY O_ORDERSTATUS
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ1;  -- mira tu resultado


-- =====================================================================
-- EJERCICIO 2 ★ · WHERE, GROUP BY y SUM
-- =====================================================================
-- Columnas: O_ORDERPRIORITY, PEDIDOS, MONTO_TOTAL

CREATE OR REPLACE VIEW EJ2 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT O_ORDERPRIORITY, COUNT(*) AS PEDIDOS, SUM(O_TOTALPRICE) AS MONTO_TOTAL
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_ORDERDATE >= '1995-01-01' AND O_ORDERDATE < '1996-01-01'
GROUP BY O_ORDERPRIORITY
ORDER BY O_ORDERPRIORITY
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ2;  -- mira tu resultado


-- =====================================================================
-- EJERCICIO 3 ★ · HAVING
-- =====================================================================
-- Columnas: O_CUSTKEY, PEDIDOS

CREATE OR REPLACE VIEW EJ3 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT O_CUSTKEY, COUNT(*) AS PEDIDOS
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
GROUP BY O_CUSTKEY
HAVING COUNT(*) >= 39
ORDER BY PEDIDOS DESC, O_CUSTKEY
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ3;  -- mira tu resultado


-- =====================================================================
-- EJERCICIO 4 ★ · AVG, MAX y ROUND
-- =====================================================================
-- Columnas: C_MKTSEGMENT, CLIENTES, SALDO_PROMEDIO, SALDO_MAXIMO

CREATE OR REPLACE VIEW EJ4 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT C_MKTSEGMENT, COUNT(*) AS CLIENTES, ROUND(AVG(C_ACCTBAL), 2) AS SALDO_PROMEDIO,
       MAX(C_ACCTBAL) AS SALDO_MAXIMO
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER
GROUP BY C_MKTSEGMENT
ORDER BY C_MKTSEGMENT
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ4;  -- mira tu resultado


-- =====================================================================
-- EJERCICIO 5 ★ · INNER JOIN
-- =====================================================================
-- Columnas: C_CUSTKEY, C_NAME, N_NAME

CREATE OR REPLACE VIEW EJ5 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT C.C_CUSTKEY, C.C_NAME, N.N_NAME
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER C JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION N ON C.C_NATIONKEY = N.N_NATIONKEY
ORDER BY C.C_CUSTKEY
LIMIT 5
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ5;  -- mira tu resultado


-- =====================================================================
-- EJERCICIO 6 ★ · JOIN y GROUP BY
-- =====================================================================
-- Columnas: N_NAME, CLIENTES

CREATE OR REPLACE VIEW EJ6 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT N.N_NAME, COUNT(*) AS CLIENTES
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER C JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION N ON C.C_NATIONKEY = N.N_NATIONKEY
GROUP BY N.N_NAME
ORDER BY CLIENTES DESC, N.N_NAME
LIMIT 5
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ6;  -- mira tu resultado


-- =====================================================================
-- EJERCICIO 7 ★★ · El JOIN que duplica
-- =====================================================================
-- Columnas: O_ORDERPRIORITY, FILAS_JOIN, MONTO_INFLADO

CREATE OR REPLACE VIEW EJ7 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT O.O_ORDERPRIORITY, COUNT(*) AS FILAS_JOIN, SUM(O.O_TOTALPRICE) AS MONTO_INFLADO
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM L ON O.O_ORDERKEY = L.L_ORDERKEY
WHERE O.O_ORDERDATE >= '1995-01-01' AND O.O_ORDERDATE < '1996-01-01'
GROUP BY O.O_ORDERPRIORITY
ORDER BY O.O_ORDERPRIORITY
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ7;  -- mira tu resultado


-- =====================================================================
-- EJERCICIO 8 ★★ · Corrección: contar sin repetir y elegir la medida
-- =====================================================================
-- Columnas: O_ORDERPRIORITY, PEDIDOS, IMPORTE_LINEAS

CREATE OR REPLACE VIEW EJ8 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT O.O_ORDERPRIORITY, COUNT(DISTINCT O.O_ORDERKEY) AS PEDIDOS,
       ROUND(SUM(L.L_EXTENDEDPRICE*(1-L.L_DISCOUNT)*(1+L.L_TAX)), 2) AS IMPORTE_LINEAS
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM L ON O.O_ORDERKEY = L.L_ORDERKEY
WHERE O.O_ORDERDATE >= '1995-01-01' AND O.O_ORDERDATE < '1996-01-01'
GROUP BY O.O_ORDERPRIORITY
ORDER BY O.O_ORDERPRIORITY
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ8;  -- mira tu resultado


-- =====================================================================
-- EJERCICIO 9 ★★ · LEFT JOIN e IS NULL
-- =====================================================================
-- Columnas: C_MKTSEGMENT, CLIENTES_SIN_PEDIDOS

CREATE OR REPLACE VIEW EJ9 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT C.C_MKTSEGMENT, COUNT(*) AS CLIENTES_SIN_PEDIDOS
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER C LEFT JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O ON C.C_CUSTKEY = O.O_CUSTKEY
WHERE O.O_ORDERKEY IS NULL
GROUP BY C.C_MKTSEGMENT
ORDER BY C.C_MKTSEGMENT
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ9;  -- mira tu resultado


-- =====================================================================
-- EJERCICIO 10 ★★★ · Tres tablas, LEFT JOIN y HAVING
-- =====================================================================
-- Columnas: N_NAME, CLIENTES, PEDIDOS

CREATE OR REPLACE VIEW EJ10 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT N.N_NAME, COUNT(DISTINCT C.C_CUSTKEY) AS CLIENTES, COUNT(O.O_ORDERKEY) AS PEDIDOS
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION N JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER C ON N.N_NATIONKEY = C.C_NATIONKEY
LEFT JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O ON C.C_CUSTKEY = O.O_CUSTKEY
GROUP BY N.N_NAME
HAVING COUNT(O.O_ORDERKEY) > 60000
ORDER BY PEDIDOS DESC, N.N_NAME
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ10;  -- mira tu resultado

