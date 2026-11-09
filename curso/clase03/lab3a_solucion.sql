-- =====================================================================
-- LAB 3A · SOLUCIÓN DE REFERENCIA (Big Data UdeM · Clase 3)
-- =====================================================================
--
-- Para contrastar tu trabajo después de intentarlo (lab3a.sql). Mismas vistas EJ1 a EJ9 con la
-- respuesta escrita. Corre el Paso 0, la vista MENSUAL_1995 y luego cada bloque, o compara tu
-- resultado con la línea "Debes ver" de lab3a.sql. Después corre lab3a_verificacion.sql: debe dar
-- OK en los nueve ejercicios y RESUMEN "5 de 5".
--
-- =====================================================================
-- PASO 0 · PREPARACIÓN (igual que en lab3a.sql)
-- QUÉ HACER: selecciona desde USE ROLE hasta USE SCHEMA CURSO.LAB3A; y pulsa ▶. No uses Run All
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

-- TU BASE DE TRABAJO: CURSO es la base de datos y LAB3A el esquema donde se guardan tus objetos.
CREATE DATABASE IF NOT EXISTS CURSO;
CREATE SCHEMA IF NOT EXISTS CURSO.LAB3A;
USE SCHEMA CURSO.LAB3A;


-- =====================================================================
-- VISTA ENTREGADA · MENSUAL_1995 (igual que en lab3a.sql)
-- =====================================================================

CREATE OR REPLACE VIEW MENSUAL_1995 AS
SELECT DATE_TRUNC('month', O_ORDERDATE) AS MES, SUM(O_TOTALPRICE) AS MONTO
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_ORDERDATE >= '1995-01-01' AND O_ORDERDATE < '1996-01-01'
GROUP BY DATE_TRUNC('month', O_ORDERDATE);

-- =====================================================================
-- EJERCICIO 1 ★ · ROW_NUMBER y PARTITION BY: top-N por grupo
-- =====================================================================
-- Columnas: O_ORDERPRIORITY, O_ORDERKEY, O_TOTALPRICE, RN

CREATE OR REPLACE VIEW EJ1 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT O_ORDERPRIORITY, O_ORDERKEY, O_TOTALPRICE, RN
FROM (SELECT O_ORDERPRIORITY, O_ORDERKEY, O_TOTALPRICE,
             ROW_NUMBER() OVER (PARTITION BY O_ORDERPRIORITY
                                ORDER BY O_TOTALPRICE DESC, O_ORDERKEY) AS RN
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS)
WHERE RN <= 3
ORDER BY O_ORDERPRIORITY, RN
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ1;  -- mira tu resultado


-- =====================================================================
-- EJERCICIO 2 ★ · El último de cada grupo
-- =====================================================================
-- Columnas: O_CUSTKEY, O_ORDERKEY, O_ORDERDATE

CREATE OR REPLACE VIEW EJ2 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT O_CUSTKEY, O_ORDERKEY, O_ORDERDATE
FROM (SELECT O_CUSTKEY, O_ORDERKEY, O_ORDERDATE,
             ROW_NUMBER() OVER (PARTITION BY O_CUSTKEY
                                ORDER BY O_ORDERDATE DESC, O_ORDERKEY DESC) AS RN
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS)
WHERE RN = 1
ORDER BY O_CUSTKEY
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ2 ORDER BY 1 LIMIT 20;  -- mira tu resultado (la vista tiene 99996 filas)


-- =====================================================================
-- EJERCICIO 3 ★ · LAG: comparar con la fila anterior
-- =====================================================================
-- Columnas: MES, MONTO, MONTO_ANTERIOR, VARIACION_PCT

CREATE OR REPLACE VIEW EJ3 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT MES, MONTO, MONTO_ANTERIOR, VARIACION_PCT
FROM (SELECT MES, MONTO,
             LAG(MONTO) OVER (ORDER BY MES) AS MONTO_ANTERIOR,
             ROUND((MONTO - LAG(MONTO) OVER (ORDER BY MES))
                   / LAG(MONTO) OVER (ORDER BY MES) * 100, 2) AS VARIACION_PCT
      FROM MENSUAL_1995)
WHERE VARIACION_PCT < 0
ORDER BY MES
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ3;  -- mira tu resultado


-- =====================================================================
-- EJERCICIO 4 ★ · Acumulado con marco ROWS
-- =====================================================================
-- Columnas: O_ORDERKEY, O_ORDERDATE, O_TOTALPRICE, ACUMULADO

CREATE OR REPLACE VIEW EJ4 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT O_ORDERKEY, O_ORDERDATE, O_TOTALPRICE,
       SUM(O_TOTALPRICE) OVER (ORDER BY O_ORDERDATE, O_ORDERKEY
                               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS ACUMULADO
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_CUSTKEY = 102022
ORDER BY O_ORDERDATE, O_ORDERKEY
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ4;  -- mira tu resultado


-- =====================================================================
-- EJERCICIO 5 ★ · Participación: una ventana sobre una agregación
-- =====================================================================
-- Columnas: O_ORDERSTATUS, PEDIDOS, PCT

CREATE OR REPLACE VIEW EJ5 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT O_ORDERSTATUS, COUNT(*) AS PEDIDOS,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS PCT
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
GROUP BY O_ORDERSTATUS
ORDER BY O_ORDERSTATUS
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ5;  -- mira tu resultado


-- =====================================================================
-- EJERCICIO 6 ★★ · Media móvil
-- =====================================================================
-- Columnas: O_ORDERKEY, O_ORDERDATE, O_TOTALPRICE, MEDIA_MOVIL_3

CREATE OR REPLACE VIEW EJ6 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT O_ORDERKEY, O_ORDERDATE, O_TOTALPRICE,
       ROUND(AVG(O_TOTALPRICE) OVER (ORDER BY O_ORDERDATE, O_ORDERKEY
                                     ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS MEDIA_MOVIL_3
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_CUSTKEY = 102022
ORDER BY O_ORDERDATE, O_ORDERKEY
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ6;  -- mira tu resultado


-- =====================================================================
-- EJERCICIO 7 ★★ · RANK contra DENSE_RANK
-- =====================================================================
-- Columnas: O_CUSTKEY, PEDIDOS, RK, DR

CREATE OR REPLACE VIEW EJ7 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT O_CUSTKEY, PEDIDOS, RK, DR
FROM (SELECT O_CUSTKEY, COUNT(*) AS PEDIDOS,
             RANK() OVER (ORDER BY COUNT(*) DESC) AS RK,
             DENSE_RANK() OVER (ORDER BY COUNT(*) DESC) AS DR
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
      GROUP BY O_CUSTKEY)
WHERE DR <= 2
ORDER BY PEDIDOS DESC, O_CUSTKEY
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ7;  -- mira tu resultado


-- =====================================================================
-- EJERCICIO 8 ★★ · Acumulado que se reinicia por grupo
-- =====================================================================
-- Columnas: ANIO, MES, MONTO, ACUM_ANIO

CREATE OR REPLACE VIEW EJ8 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT ANIO, MES, MONTO,
       SUM(MONTO) OVER (PARTITION BY ANIO ORDER BY MES
                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS ACUM_ANIO
FROM (SELECT YEAR(O_ORDERDATE) AS ANIO, MONTH(O_ORDERDATE) AS MES, SUM(O_TOTALPRICE) AS MONTO
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
      WHERE O_ORDERDATE >= '1995-01-01' AND O_ORDERDATE < '1997-01-01'
      GROUP BY YEAR(O_ORDERDATE), MONTH(O_ORDERDATE))
ORDER BY ANIO, MES
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ8;  -- mira tu resultado


-- =====================================================================
-- EJERCICIO 9 ★★★ · Rachas de meses consecutivos (gaps and islands)
-- =====================================================================
-- Columnas: INICIO, FIN, MESES

CREATE OR REPLACE VIEW EJ9 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
WITH M AS (SELECT DISTINCT DATE_TRUNC('month', O_ORDERDATE) AS MES
           FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
           WHERE O_CUSTKEY = 102022),
G AS (SELECT MES, DATEADD('month', -ROW_NUMBER() OVER (ORDER BY MES), MES) AS GRUPO
      FROM M)
SELECT MIN(MES) AS INICIO, MAX(MES) AS FIN, COUNT(*) AS MESES
FROM G
GROUP BY GRUPO
ORDER BY INICIO
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ9;  -- mira tu resultado

