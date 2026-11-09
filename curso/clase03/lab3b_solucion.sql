-- =====================================================================
-- LAB 3B · SOLUCIÓN DE REFERENCIA (Big Data UdeM · Clase 3)
-- =====================================================================
--
-- Para contrastar tu trabajo después de intentarlo (lab3b.sql). Mismas vistas B1 a B5 con la
-- respuesta escrita. Corre el Paso 0 y luego cada bloque, o compara tu resultado con la línea
-- "Debes ver" de lab3b.sql. Después corre lab3b_verificacion.sql: debe dar OK en los cinco
-- ejercicios y RESUMEN "4 de 4".
--
-- =====================================================================
-- PASO 0 · PREPARACIÓN (igual que en lab3b.sql)
-- QUÉ HACER: selecciona desde USE ROLE hasta USE SCHEMA CURSO.LAB3B; y pulsa ▶. No uses Run All
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

-- TU BASE DE TRABAJO: CURSO es la base de datos y LAB3B el esquema donde se guardan tus objetos.
CREATE DATABASE IF NOT EXISTS CURSO;
CREATE SCHEMA IF NOT EXISTS CURSO.LAB3B;
USE SCHEMA CURSO.LAB3B;


-- =====================================================================
-- EJERCICIO B1 ★ · QUALIFY: el top-N sin subconsulta
-- =====================================================================
-- Columnas: O_ORDERPRIORITY, O_ORDERKEY, O_TOTALPRICE, RN

CREATE OR REPLACE VIEW B1 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT O_ORDERPRIORITY, O_ORDERKEY, O_TOTALPRICE,
       ROW_NUMBER() OVER (PARTITION BY O_ORDERPRIORITY
                          ORDER BY O_TOTALPRICE DESC, O_ORDERKEY) AS RN
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
QUALIFY RN <= 3
ORDER BY O_ORDERPRIORITY, RN
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM B1;  -- mira tu resultado


-- =====================================================================
-- EJERCICIO B2 ★ · QUALIFY con la ventana dentro de la condición
-- =====================================================================
-- Columnas: O_CUSTKEY, O_ORDERKEY, O_ORDERDATE

CREATE OR REPLACE VIEW B2 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT O_CUSTKEY, O_ORDERKEY, O_ORDERDATE
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
QUALIFY ROW_NUMBER() OVER (PARTITION BY O_CUSTKEY
                           ORDER BY O_ORDERDATE DESC, O_ORDERKEY DESC) = 1
ORDER BY O_CUSTKEY
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM B2 ORDER BY 1 LIMIT 20;  -- mira tu resultado (la vista tiene 99996 filas)


-- =====================================================================
-- EJERCICIO B3 ★ · QUALIFY con GROUP BY: LAG sobre una suma
-- =====================================================================
-- Columnas: MES, MONTO, MONTO_ANTERIOR, VARIACION_PCT

CREATE OR REPLACE VIEW B3 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT DATE_TRUNC('month', O_ORDERDATE) AS MES,
       SUM(O_TOTALPRICE) AS MONTO,
       LAG(SUM(O_TOTALPRICE)) OVER (ORDER BY DATE_TRUNC('month', O_ORDERDATE)) AS MONTO_ANTERIOR,
       ROUND((MONTO - MONTO_ANTERIOR) / MONTO_ANTERIOR * 100, 2) AS VARIACION_PCT
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_ORDERDATE >= '1995-01-01' AND O_ORDERDATE < '1996-01-01'
GROUP BY DATE_TRUNC('month', O_ORDERDATE)
QUALIFY MONTO < MONTO_ANTERIOR
ORDER BY MES
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM B3;  -- mira tu resultado


-- =====================================================================
-- EJERCICIO B4 ★ · Promedio ponderado: el promedio de promedios se desvía
-- =====================================================================
-- Columnas: PROM_DE_PROMEDIOS, PROM_DIRECTO, PROM_PONDERADO, DIFERENCIA_PCT

CREATE OR REPLACE VIEW B4 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
WITH POR_ESTADO AS (SELECT O_ORDERSTATUS, COUNT(*) AS PEDIDOS, AVG(O_TOTALPRICE) AS PROM
                    FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
                    GROUP BY O_ORDERSTATUS)
SELECT ROUND(AVG(PROM), 2) AS PROM_DE_PROMEDIOS,
       ROUND((SELECT AVG(O_TOTALPRICE) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS), 2) AS PROM_DIRECTO,
       ROUND(SUM(PEDIDOS * PROM) / SUM(PEDIDOS), 2) AS PROM_PONDERADO,
       ROUND((AVG(PROM) - (SELECT AVG(O_TOTALPRICE) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS))
             / (SELECT AVG(O_TOTALPRICE) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS) * 100, 2) AS DIFERENCIA_PCT
FROM POR_ESTADO
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM B4;  -- mira tu resultado


-- =====================================================================
-- EJERCICIO B5 ★★ · CTE: agregar antes de unir y contar las uniones
-- =====================================================================
-- Columnas: R_NAME, INGRESO
-- JOIN usados: 4 (ING con ORDERS, ORDERS con CUSTOMER, CUSTOMER con NATION, NATION con REGION).

CREATE OR REPLACE VIEW B5 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
WITH ING AS (SELECT L_ORDERKEY, SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT)) AS INGRESO_PEDIDO
             FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM
             GROUP BY L_ORDERKEY)
SELECT R.R_NAME, ROUND(SUM(I.INGRESO_PEDIDO), 2) AS INGRESO
FROM ING I
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O ON I.L_ORDERKEY = O.O_ORDERKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER C ON O.O_CUSTKEY = C.C_CUSTKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION N ON C.C_NATIONKEY = N.N_NATIONKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION R ON N.N_REGIONKEY = R.R_REGIONKEY
GROUP BY R.R_NAME
ORDER BY R.R_NAME
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM B5;  -- mira tu resultado

