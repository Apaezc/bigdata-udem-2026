-- =====================================================================
-- CLASE 3 · Guion de demos en vivo del instructor (Snowsight)
-- =====================================================================
--
-- Numeración de slides: la del storyboard corregido de la clase 3 (38 slides).
-- Fuente de cifras: validacion/contenido/clase03_medidas.md (M1 a M18). «M2» = esa medición.
-- Las cifras del Lab 3C vienen de lab3c_solucion.sql, probado el 8 nov. 2026.
--
-- PREPARACIÓN (antes de la clase, no en pantalla)
--   USE ROLE ACCOUNTADMIN;
--   USE WAREHOUSE COMPUTE_WH;      -- XSMALL, AUTO_SUSPEND = 60
--   ALTER SESSION SET USE_CACHED_RESULT = FALSE;
--   Corre la DEMO 0 completa: crea el esquema CURSO.DEMO3 con DIM_CLIENTE, DIM_FECHA y
--   FACT_LINEITEM (el mismo SQL que C1 a C3 del Lab 3C). Las demos 18, 26 a 29, 31 a 33
--   las usan. Tarda unos 5 s.
--   Para las demos de las slides 11, 21 y 26 (TPC-H SF10) deja COMPUTE_WH en XSMALL y
--   la caché de resultados desactivada.
--
-- LECTURA DEL QUERY PROFILE
--   En el panel de resultados, Query Details > botón de tres puntos > View Query Profile; o
--   Monitoring > Query History > consulta > pestaña Query Profile. Para releer el perfil de
--   una consulta ya ejecutada: ALTER SESSION SET USE_CACHED_RESULT = FALSE; y volver a correrla.
--
-- PLAN B: si Snowsight no responde o una cifra se desvía mucho, muestra la tabla medida (slides
--   y notas) y di que se midió el 8 de noviembre de 2026 en X-Small. Los tiempos varían entre
--   corridas; los conteos y las sumas, no.
--
-- ERRORES ESPERADOS: la demo 10 (slide 18) termina en error a propósito (código 002063).
--
-- DEMOS DE LECTURA SOBRE LA CUENTA: la demo 19 (slide 30) y la 25 (slide 37) leen
--   BIGDATA.DEV.DAILY_ZONE_METRICS (el gold de enero 2024). Si esa tabla no está en tu
--   cuenta, muestra las cifras de la slide.
-- =====================================================================


-- =====================================================================
-- DEMO 0 · Preparación de la estrella de demo (antes de la clase; slides 20, 28 a 31, 33 a 36)
-- Qué se muestra: nada; deja listas DIM_CLIENTE, DIM_FECHA y FACT_LINEITEM en CURSO.DEMO3.
-- Resultado esperado: 150 000, 2 406 y 6 001 215 filas.
-- =====================================================================
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
CREATE DATABASE IF NOT EXISTS SNOWFLAKE_SAMPLE_DATA FROM SHARE SFC_SAMPLES.SAMPLE_DATA;
CREATE DATABASE IF NOT EXISTS CURSO;
CREATE SCHEMA IF NOT EXISTS CURSO.DEMO3;
USE SCHEMA CURSO.DEMO3;

CREATE OR REPLACE TABLE DIM_CLIENTE AS
SELECT C.C_CUSTKEY AS CLIENTE_KEY, C.C_NAME, C.C_MKTSEGMENT, N.N_NAME, R.R_NAME
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER C
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION N ON C.C_NATIONKEY = N.N_NATIONKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION R ON N.N_REGIONKEY = R.R_REGIONKEY;

CREATE OR REPLACE TABLE DIM_FECHA AS
WITH r AS (SELECT MIN(O_ORDERDATE) AS MINF, MAX(O_ORDERDATE) AS MAXF
           FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS)
SELECT FECHA, YEAR(FECHA) AS ANIO, MONTH(FECHA) AS MES
FROM (SELECT DATEADD('day', ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1, MINF) AS FECHA
      FROM r, TABLE(GENERATOR(ROWCOUNT => 3000))
      QUALIFY FECHA <= MAXF);

CREATE OR REPLACE TABLE FACT_LINEITEM AS
SELECT L.L_ORDERKEY, L.L_LINENUMBER,
       O.O_CUSTKEY AS CLIENTE_KEY,
       O.O_ORDERDATE AS FECHA,
       L.L_PARTKEY AS PRODUCTO_KEY,
       L.L_QUANTITY, L.L_EXTENDEDPRICE, L.L_DISCOUNT,
       L.L_EXTENDEDPRICE * (1 - L.L_DISCOUNT) AS INGRESO
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM L
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O ON L.L_ORDERKEY = O.O_ORDERKEY;

SELECT (SELECT COUNT(*) FROM DIM_CLIENTE)   AS DIM_CLIENTE,
       (SELECT COUNT(*) FROM DIM_FECHA)     AS DIM_FECHA,
       (SELECT COUNT(*) FROM FACT_LINEITEM) AS FACT_LINEITEM;


-- =====================================================================
-- DEMO 1 · Slide 2 (y slide 31) · Un JOIN sin error infla una suma 5 veces
-- Qué se muestra: ORDERS tiene 1 500 000 pedidos; unido a LINEITEM devuelve 6 001 215 filas y
--   SUM(O_TOTALPRICE) se multiplica por 5. El motor no marca error.
-- Resultado esperado (medido, SF1; clase 2, demo 11; M13):
--   sin JOIN: 1 500 000 filas y 226 829 306 447.46;
--   con JOIN: 6 001 215 filas, 1 500 000 pedidos distintos y 1 134 436 101 880.19 (5.0 veces).
-- =====================================================================
USE WAREHOUSE COMPUTE_WH;
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT COUNT(*) AS FILAS, SUM(O_TOTALPRICE) AS SUMA_PEDIDOS
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS;

SELECT COUNT(*) AS FILAS, COUNT(DISTINCT O.O_ORDERKEY) AS PEDIDOS,
       SUM(O.O_TOTALPRICE) AS SUMA_INFLADA,
       ROUND(SUM(O.O_TOTALPRICE) / 226829306447.46, 1) AS VECES
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM L ON O.O_ORDERKEY = L.L_ORDERKEY;


-- =====================================================================
-- DEMO 2 · Slide 3 · GROUP BY borra los pedidos a comparar
-- Qué se muestra: 1 500 000 pedidos quedan en 99 996 filas, una por cliente; la fecha y el monto
--   de cada pedido ya no están.
-- Resultado esperado (M10): 99 996 filas; primeros: 3451, 102004 y 102022 con 41 pedidos.
-- =====================================================================
SELECT O_CUSTKEY, COUNT(*) AS PEDIDOS
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
GROUP BY O_CUSTKEY
ORDER BY PEDIDOS DESC, O_CUSTKEY;


-- =====================================================================
-- DEMO 3 · Slide 5 · Las ocho tablas de TPC-H y sus filas
-- Qué se muestra: filas de las ocho tablas en SF1 y de LINEITEM en SF1, SF10 y SF100. COUNT(*)
--   sin filtro se responde con los metadatos: no lee datos.
-- Resultado esperado (M1): REGION 5; NATION 25; CUSTOMER 150 000; ORDERS 1 500 000;
--   LINEITEM 6 001 215; PART 200 000; SUPPLIER 10 000; PARTSUPP 800 000;
--   LINEITEM SF10 59 986 052; LINEITEM SF100 600 037 902.
-- =====================================================================
SELECT 'REGION' AS TABLA, COUNT(*) AS FILAS FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION
UNION ALL SELECT 'NATION',   COUNT(*) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION
UNION ALL SELECT 'CUSTOMER', COUNT(*) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER
UNION ALL SELECT 'ORDERS',   COUNT(*) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
UNION ALL SELECT 'LINEITEM', COUNT(*) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM
UNION ALL SELECT 'PART',     COUNT(*) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.PART
UNION ALL SELECT 'SUPPLIER', COUNT(*) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.SUPPLIER
UNION ALL SELECT 'PARTSUPP', COUNT(*) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.PARTSUPP
UNION ALL SELECT 'LINEITEM SF10',  COUNT(*) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM
UNION ALL SELECT 'LINEITEM SF100', COUNT(*) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.LINEITEM;


-- =====================================================================
-- DEMO 4 · Slide 6 · Una ventana calcula sobre un grupo sin borrar filas
-- Qué se muestra: las 41 filas del cliente 102022 siguen ahí, cada una con el total del cliente.
-- Resultado esperado (M9): 41 filas; TOTAL_CLIENTE = 6 273 788.41 en todas; la primera
--   (1992-01-05, pedido 1066817) es 144 930.46, es decir 2.31 % del total.
-- =====================================================================
SELECT O_ORDERKEY, O_ORDERDATE, O_TOTALPRICE,
       SUM(O_TOTALPRICE) OVER (PARTITION BY O_CUSTKEY) AS TOTAL_CLIENTE
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_CUSTKEY = 102022
ORDER BY O_ORDERDATE, O_ORDERKEY;


-- =====================================================================
-- DEMO 5 · Slide 7 · PARTITION BY agrupa; ORDER BY convierte el total en acumulado
-- Qué se muestra: la misma SUM da el total del grupo sin ORDER BY y el acumulado con ORDER BY.
--   El ORDER BY de OVER no ordena la salida: eso lo hace el ORDER BY final.
-- Resultado esperado (M9): tres primeros pedidos del cliente 102022:
--   144 930.46 con total 6 273 788.41 y acumulado 144 930.46;
--   111 485.66 con total 6 273 788.41 y acumulado 256 416.12;
--    63 555.44 con total 6 273 788.41 y acumulado 319 971.56.
-- =====================================================================
SELECT O_ORDERKEY, O_ORDERDATE, O_TOTALPRICE,
       SUM(O_TOTALPRICE) OVER (PARTITION BY O_CUSTKEY) AS SIN_ORDER_BY,
       SUM(O_TOTALPRICE) OVER (PARTITION BY O_CUSTKEY
                               ORDER BY O_ORDERDATE, O_ORDERKEY) AS CON_ORDER_BY
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_CUSTKEY = 102022
ORDER BY O_ORDERDATE, O_ORDERKEY
LIMIT 3;


-- =====================================================================
-- DEMO 6 · Slide 8 · ROW_NUMBER, RANK y DENSE_RANK con empates reales
-- Qué se muestra: tres clientes con 41 pedidos y tres con 40. ROW_NUMBER no repite, RANK salta,
--   DENSE_RANK no salta. La primera versión no desempata (el orden entre iguales puede variar
--   entre corridas); la segunda añade O_CUSTKEY y queda reproducible; es la que muestra la slide 8.
-- Resultado esperado (M3): RK 1, 1, 1, 4, 4, 4 y DR 1, 1, 1, 2, 2, 2 en las dos versiones.
--   Con desempate, ROW_NUMBER es 1 a 6 con los clientes 3451, 102004, 102022, 79300, 117082, 122623.
--   Con DENSE_RANK <= 2 salen 6 clientes.
-- =====================================================================
WITH c AS (SELECT O_CUSTKEY, COUNT(*) AS PEDIDOS
           FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
           GROUP BY O_CUSTKEY)
SELECT O_CUSTKEY, PEDIDOS,
       ROW_NUMBER() OVER (ORDER BY PEDIDOS DESC) AS RN,
       RANK() OVER (ORDER BY PEDIDOS DESC) AS RK,
       DENSE_RANK() OVER (ORDER BY PEDIDOS DESC) AS DR
FROM c
ORDER BY PEDIDOS DESC
LIMIT 6;

WITH c AS (SELECT O_CUSTKEY, COUNT(*) AS PEDIDOS
           FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
           GROUP BY O_CUSTKEY)
SELECT O_CUSTKEY, PEDIDOS,
       ROW_NUMBER() OVER (ORDER BY PEDIDOS DESC, O_CUSTKEY) AS RN,
       RANK() OVER (ORDER BY PEDIDOS DESC) AS RK,
       DENSE_RANK() OVER (ORDER BY PEDIDOS DESC) AS DR
FROM c
ORDER BY RN
LIMIT 6;


-- =====================================================================
-- DEMO 7 · Slide 9 · LAG: los días entre pedidos son una resta
-- Qué se muestra: el primer pedido da NULL; los siguientes, 49, 44 y 32 días; la mayor pausa,
--   227 días. Dos pedidos del mismo día dan 0.
-- Resultado esperado (M9, M17): 41 filas; NULL, 49, 44, 32; mayor pausa 227 días (pedido
--   1804518, 1993-12-24); dos filas con 0 (1994-12-15 y 1997-03-12).
-- =====================================================================
SELECT O_ORDERKEY, O_ORDERDATE,
       DATEDIFF('day',
                LAG(O_ORDERDATE) OVER (ORDER BY O_ORDERDATE, O_ORDERKEY),
                O_ORDERDATE) AS DIAS_DESDE_ANTERIOR
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_CUSTKEY = 102022
ORDER BY O_ORDERDATE, O_ORDERKEY;


-- =====================================================================
-- DEMO 8 · Slide 10 · El marco: media móvil de tres pedidos y ROWS contra RANGE
-- Qué se muestra: (a) media móvil de tres pedidos con ROWS; (b) con ORDER BY y sin marco, dos
--   pedidos del mismo día comparten acumulado (RANGE); con ROWS y desempate no.
-- Resultado esperado (M9): (a) 144 930.46; 128 208.06; 106 657.19; 100 712.37 en las cuatro
--   primeras filas. (b) pedidos 562371 y 3008738 (1994-12-15): sin marco, 2 377 593.85 en los
--   dos; con ROWS, 2 359 717.42 y 2 377 593.85.
-- =====================================================================
SELECT O_ORDERKEY, O_ORDERDATE, O_TOTALPRICE,
       AVG(O_TOTALPRICE) OVER (
         ORDER BY O_ORDERDATE, O_ORDERKEY
         ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS MEDIA_MOVIL_3
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_CUSTKEY = 102022
ORDER BY O_ORDERDATE, O_ORDERKEY;

SELECT O_ORDERKEY, O_ORDERDATE, ACUM_SIN_MARCO, ACUM_ROWS
FROM (SELECT O_ORDERKEY, O_ORDERDATE,
             SUM(O_TOTALPRICE) OVER (ORDER BY O_ORDERDATE) AS ACUM_SIN_MARCO,
             SUM(O_TOTALPRICE) OVER (ORDER BY O_ORDERDATE, O_ORDERKEY
                                     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS ACUM_ROWS
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
      WHERE O_CUSTKEY = 102022)
WHERE O_ORDERKEY IN (562371, 3008738)
ORDER BY O_ORDERKEY;


-- =====================================================================
-- DEMO 9 · Slide 11 · Toda ventana tiene costo: Query Profile con derrame a disco
-- Qué se muestra: tres consultas sobre ORDERS de TPC-H SF10 (15 000 000 filas): GROUP BY, ventana
--   sin ORDER BY y ventana con ORDER BY. En el perfil de la tercera, el operador
--   WindowFunction concentra el tiempo y aparece derrame a almacenamiento local.
--   Envueltas en un agregado exterior para no devolver 15 M de filas.
-- Resultado esperado (M2, X-Small, caché desactivada, 3 corridas):
--   (a) GROUP BY: 999 982 filas; ejecución 270 a 293 ms; sin derrame.
--   (b) OVER (PARTITION BY): 15 000 000 filas; ejecución 389 a 454 ms; sin derrame.
--   (c) OVER (PARTITION BY ... ORDER BY): ejecución 1 719 a 1 868 ms; derrame de unos 215 MB
--       (214 941 696 a 215 179 264 bytes). La suma de (c) es acumulada: su CHECK_SUMA difiere.
-- Corre cada consulta tres veces y abre el perfil de la (c). El tiempo de compilación varía.
-- =====================================================================
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT COUNT(*) AS FILAS_SALIDA, SUM(S) AS CHECK_SUMA
FROM (SELECT O_CUSTKEY, SUM(O_TOTALPRICE) AS S
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS
      GROUP BY O_CUSTKEY);

SELECT COUNT(*) AS FILAS_SALIDA, SUM(W) AS CHECK_SUMA
FROM (SELECT SUM(O_TOTALPRICE) OVER (PARTITION BY O_CUSTKEY) AS W
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS);

SELECT COUNT(*) AS FILAS_SALIDA, SUM(W) AS CHECK_SUMA
FROM (SELECT SUM(O_TOTALPRICE) OVER (PARTITION BY O_CUSTKEY ORDER BY O_ORDERDATE) AS W
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS);

-- Derrame de la tercera consulta (la que acabas de correr): operador WindowFunction.
-- Debes ver: WindowFunction con bytes_spilled_local_storage de unos 215 MB (215 191 552 en la prueba).
SET QID = LAST_QUERY_ID();
SELECT OPERATOR_TYPE,
       ROUND(EXECUTION_TIME_BREAKDOWN:overall_percentage::FLOAT * 100, 1) AS PCT_DEL_TIEMPO,
       OPERATOR_STATISTICS:spilling:bytes_spilled_local_storage::NUMBER AS DERRAME_LOCAL_BYTES
FROM TABLE(GET_QUERY_OPERATOR_STATS($QID))
WHERE OPERATOR_TYPE = 'WindowFunction';


-- =====================================================================
-- DEMO 10 · Slide 18 · WHERE no filtra ventanas (error esperado)
-- Qué se muestra: WHERE se evalúa antes que la ventana; RN no existe todavía.
-- Resultado esperado (M10): error 002063 (SQL compilation error, estado 42601):
--   Window function [ROW_NUMBER() OVER (...)] appears outside of SELECT, QUALIFY, and ORDER BY
--   clauses.
-- Este bloque termina en error a propósito.
-- =====================================================================
SELECT O_CUSTKEY, O_ORDERKEY, O_TOTALPRICE,
       ROW_NUMBER() OVER (PARTITION BY O_CUSTKEY
                          ORDER BY O_TOTALPRICE DESC) AS RN
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE RN <= 3;


-- =====================================================================
-- DEMO 11 · Slide 19 · QUALIFY filtra después de calcular la ventana
-- Qué se muestra: el top-3 por cliente en un solo nivel. Hasta 3 pedidos por cliente (algunos
--   clientes tienen menos).
-- Resultado esperado (M10): 299 831 filas de 99 996 clientes. Segunda consulta: los meses de
--   1995 que cayeron frente al mes anterior (QUALIFY con GROUP BY), 6 filas (M13).
-- =====================================================================
SELECT O_CUSTKEY, O_ORDERKEY, O_TOTALPRICE
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
QUALIFY ROW_NUMBER() OVER (
           PARTITION BY O_CUSTKEY
           ORDER BY O_TOTALPRICE DESC, O_ORDERKEY) <= 3
ORDER BY O_CUSTKEY, O_TOTALPRICE DESC;

-- Para contar sin listar:
SELECT COUNT(*) AS FILAS, COUNT(DISTINCT O_CUSTKEY) AS CLIENTES
FROM (SELECT O_CUSTKEY, O_ORDERKEY, O_TOTALPRICE
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
      QUALIFY ROW_NUMBER() OVER (PARTITION BY O_CUSTKEY
                                 ORDER BY O_TOTALPRICE DESC, O_ORDERKEY) <= 3);

SELECT DATE_TRUNC('month', O_ORDERDATE) AS MES, SUM(O_TOTALPRICE) AS MONTO
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_ORDERDATE >= '1995-01-01' AND O_ORDERDATE < '1996-01-01'
GROUP BY DATE_TRUNC('month', O_ORDERDATE)
QUALIFY SUM(O_TOTALPRICE) < LAG(SUM(O_TOTALPRICE)) OVER (ORDER BY DATE_TRUNC('month', O_ORDERDATE))
ORDER BY MES;


-- =====================================================================
-- DEMO 12 · Slide 20 · Una CTE nombra cada paso y se lee de arriba abajo
-- Qué se muestra: por_cliente deja 99 996 filas; la unión con CUSTOMER suma PEDIDOS por segmento.
--   Se puede probar cada paso por separado.
-- Resultado esperado (M10): AUTOMOBILE 297 453; BUILDING 303 959; FURNITURE 299 461;
--   HOUSEHOLD 300 147; MACHINERY 298 980 (suman 1 500 000).
-- =====================================================================
WITH por_cliente AS (
  SELECT O_CUSTKEY, COUNT(*) AS PEDIDOS
  FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
  GROUP BY O_CUSTKEY)
SELECT C.C_MKTSEGMENT, SUM(P.PEDIDOS) AS PEDIDOS
FROM por_cliente P JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER C
  ON C.C_CUSTKEY = P.O_CUSTKEY
GROUP BY C.C_MKTSEGMENT
ORDER BY C.C_MKTSEGMENT;

-- Probar un paso por separado (esperado: 99 996):
WITH por_cliente AS (
  SELECT O_CUSTKEY, COUNT(*) AS PEDIDOS
  FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
  GROUP BY O_CUSTKEY)
SELECT COUNT(*) AS FILAS FROM por_cliente;


-- =====================================================================
-- DEMO 13 · Slide 21 · Agregar antes de unir no infla la medida del pedido
-- Qué se muestra: (a) SF1, la suma del pedido con y sin agregación previa; (b) SF10, por cliente y
--   con dos medidas a la vez, el operador Join recibe 59 986 052 filas al unir primero y
--   15 000 000 al agregar primero (se ve en el Query Profile). La ejecución casi no cambia.
-- Resultado esperado (M14):
--   (a) unir primero: 6 001 215 filas y 1 134 436 101 880.19; agregar primero: 1 500 000 filas
--       y 226 829 306 447.46.
--   (b) 999 982 clientes y SUM(L_EXTENDEDPRICE) = 2 293 813 156 773.36 en las dos formas;
--       SUM(O_TOTALPRICE) = 11 329 533 808 416.01 al unir primero y 2 266 298 190 748.43 al
--       agregar primero (el valor real). Ejecución: 947 a 1 305 ms contra 1 132 a 1 164 ms.
-- =====================================================================
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

-- (a) SF1, unir primero y agregar primero
SELECT COUNT(*) AS FILAS, SUM(O.O_TOTALPRICE) AS S
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM L ON O.O_ORDERKEY = L.L_ORDERKEY;

WITH L AS (SELECT L_ORDERKEY FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM GROUP BY 1)
SELECT COUNT(*) AS FILAS, SUM(O.O_TOTALPRICE) AS S
FROM L JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O ON O.O_ORDERKEY = L.L_ORDERKEY;

-- (b) SF10, por cliente, unir y agregar (abre el perfil: el Join entrega 59 986 052 filas)
SELECT COUNT(*) AS CLIENTES, SUM(S_LINEAS) AS SUMA_LINEAS, SUM(S_PEDIDO) AS SUMA_PEDIDO
FROM (SELECT O.O_CUSTKEY, SUM(L.L_EXTENDEDPRICE) AS S_LINEAS, SUM(O.O_TOTALPRICE) AS S_PEDIDO
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS O
      JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM L ON O.O_ORDERKEY = L.L_ORDERKEY
      GROUP BY O.O_CUSTKEY);

-- (b) SF10, por cliente, agregar y unir (abre el perfil: el Join entrega 15 000 000 filas)
SELECT COUNT(*) AS CLIENTES, SUM(S_LINEAS) AS SUMA_LINEAS, SUM(S_PEDIDO) AS SUMA_PEDIDO
FROM (WITH L AS (SELECT L_ORDERKEY, SUM(L_EXTENDEDPRICE) AS S_LINEAS
                 FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM
                 GROUP BY L_ORDERKEY)
      SELECT O.O_CUSTKEY, SUM(L.S_LINEAS) AS S_LINEAS, SUM(O.O_TOTALPRICE) AS S_PEDIDO
      FROM L JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS O ON O.O_ORDERKEY = L.L_ORDERKEY
      GROUP BY O.O_CUSTKEY);


-- =====================================================================
-- DEMO 14 · Slide 22 · El promedio de promedios se desvía 6.9 %
-- Qué se muestra: por estado del pedido, los grupos son muy desiguales (F y O, unos 730 000;
--   P, 38 543) y sus medias difieren. El promedio de promedios pesa a P un tercio; el promedio
--   directo, 2.57 %. El promedio ponderado SUM(n * promedio) / SUM(n) iguala al directo.
-- Resultado esperado (M8): F 729 413 y 150 398.22; O 732 044 y 150 288.47; P 38 543 y 184 446.39;
--   PROM_DE_PROMEDIOS 161 711.03; PROM_DIRECTO 151 219.54; PROM_PONDERADO 151 219.54;
--   diferencia de 10 491.49 (6.94 %).
-- =====================================================================
SELECT O_ORDERSTATUS AS ESTADO, COUNT(*) AS PEDIDOS, ROUND(AVG(O_TOTALPRICE), 2) AS PROMEDIO
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
GROUP BY O_ORDERSTATUS
ORDER BY O_ORDERSTATUS;

WITH g AS (SELECT O_ORDERSTATUS AS ESTADO, COUNT(*) AS PEDIDOS, AVG(O_TOTALPRICE) AS PROM
           FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
           GROUP BY 1)
SELECT ROUND(AVG(PROM), 2) AS PROM_DE_PROMEDIOS,
       ROUND((SELECT AVG(O_TOTALPRICE) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS), 2) AS PROM_DIRECTO,
       ROUND(SUM(PEDIDOS * PROM) / SUM(PEDIDOS), 2) AS PROM_PONDERADO,
       ROUND((AVG(PROM) - (SELECT AVG(O_TOTALPRICE) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS))
             / (SELECT AVG(O_TOTALPRICE) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS) * 100, 2) AS DIFERENCIA_PCT
FROM g;


-- =====================================================================
-- DEMO 15 · Slide 24 · Preguntar por región pide cuatro uniones
-- Qué se muestra: LINEITEM, ORDERS, CUSTOMER, NATION y REGION, cuatro JOIN, para traer un nombre.
--   Abre el perfil: 4 operadores Join y 5 TableScan.
-- Resultado esperado (M5, M13): 5 regiones: AFRICA 43 488 870 851.69; AMERICA 43 565 312 628.95;
--   ASIA 43 858 010 644.94; EUROPE 44 032 702 326.30; MIDDLE EAST 43 157 327 433.13 (SF1).
-- =====================================================================
SELECT R.R_NAME, ROUND(SUM(L.L_EXTENDEDPRICE * (1 - L.L_DISCOUNT)), 2) AS INGRESO
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM L
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O ON L.L_ORDERKEY = O.O_ORDERKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER C ON O.O_CUSTKEY = C.C_CUSTKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION N ON C.C_NATIONKEY = N.N_NATIONKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION R ON N.N_REGIONKEY = R.R_REGIONKEY
GROUP BY R.R_NAME ORDER BY 1;


-- =====================================================================
-- DEMO 16 · Slides 25 a 27 (cifras de la 26) · Normalizado, hecho + 3 tablas y hecho + dimensión
-- Qué se muestra: la misma pregunta (ingreso por región, SF10) en tres formas: 4, 3 y 1 uniones.
--   Resultado idéntico; ejecución más corta con el hecho; compilación mucho menor con la
--   dimensión desnormalizada. Espacio: la dimensión con N_NAME y R_NAME ocupa 7.0 % más.
--   Crear el hecho en SF10 tarda unos 20 s en X-Small. Usa el esquema CURSO.DEMO3_SF10.
-- Resultado esperado (M5, M6, M15; X-Small, 3 corridas):
--   ingreso por región (SF10): AFRICA 435 475 383 578.07; AMERICA 434 758 267 615.94;
--   ASIA 436 738 690 443.01; EUROPE 436 890 284 129.48; MIDDLE EAST 435 252 080 170.44.
--   ejecución: normalizado 1 164 a 1 328 ms; hecho + 3 tablas 652 a 687 ms; hecho + dimensión
--   604 a 647 ms (en la prueba del 8 nov.: 1 197, 691 y 621 ms; los tiempos varían). Filas
--   distintas entre formas: 0. Bytes: CUSTOMER + NATION + REGION 108 257 280
--   (108 249 088 + 4 096 + 4 096); DIM_CLIENTE_COMPLETA unos 115.9 MB (115 871 744 en M15;
--   115 864 576 en la prueba): +7.0 %.
-- =====================================================================
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
CREATE SCHEMA IF NOT EXISTS CURSO.DEMO3_SF10;
USE SCHEMA CURSO.DEMO3_SF10;

-- El hecho: LINEITEM con O_CUSTKEY copiado en cada línea (59 986 052 filas).
CREATE OR REPLACE TABLE FACT_LINEITEM AS
SELECT L.*, O.O_CUSTKEY
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM L
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS O ON L.L_ORDERKEY = O.O_ORDERKEY;

-- La dimensión: CUSTOMER con N_NAME y R_NAME repetidos (1 500 000 filas).
CREATE OR REPLACE TABLE DIM_CLIENTE_COMPLETA AS
SELECT C.*, N.N_NAME, R.R_NAME
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.CUSTOMER C
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.NATION N ON C.C_NATIONKEY = N.N_NATIONKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.REGION R ON N.N_REGIONKEY = R.R_REGIONKEY;

-- (1) Normalizado: 4 uniones
SELECT R.R_NAME, ROUND(SUM(L.L_EXTENDEDPRICE * (1 - L.L_DISCOUNT)), 2) AS INGRESO
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM L
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS O ON L.L_ORDERKEY = O.O_ORDERKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.CUSTOMER C ON O.O_CUSTKEY = C.C_CUSTKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.NATION N ON C.C_NATIONKEY = N.N_NATIONKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.REGION R ON N.N_REGIONKEY = R.R_REGIONKEY
GROUP BY R.R_NAME ORDER BY 1;

-- (2) Hecho + CUSTOMER, NATION y REGION (copo de nieve): 3 uniones
SELECT R.R_NAME, ROUND(SUM(F.L_EXTENDEDPRICE * (1 - F.L_DISCOUNT)), 2) AS INGRESO
FROM FACT_LINEITEM F
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.CUSTOMER C ON F.O_CUSTKEY = C.C_CUSTKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.NATION N ON C.C_NATIONKEY = N.N_NATIONKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.REGION R ON N.N_REGIONKEY = R.R_REGIONKEY
GROUP BY R.R_NAME ORDER BY 1;

-- (3) Hecho + dimensión (estrella): 1 unión
SELECT D.R_NAME, ROUND(SUM(F.L_EXTENDEDPRICE * (1 - F.L_DISCOUNT)), 2) AS INGRESO
FROM FACT_LINEITEM F
JOIN DIM_CLIENTE_COMPLETA D ON F.O_CUSTKEY = D.C_CUSTKEY
GROUP BY D.R_NAME ORDER BY 1;

-- Comparación: 0 filas distintas entre la forma (1) y la (3).
WITH n AS (SELECT R.R_NAME AS REG, SUM(L.L_EXTENDEDPRICE * (1 - L.L_DISCOUNT)) AS INGRESO
           FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM L
           JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS O ON L.L_ORDERKEY = O.O_ORDERKEY
           JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.CUSTOMER C ON O.O_CUSTKEY = C.C_CUSTKEY
           JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.NATION N ON C.C_NATIONKEY = N.N_NATIONKEY
           JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.REGION R ON N.N_REGIONKEY = R.R_REGIONKEY
           GROUP BY R.R_NAME),
     s AS (SELECT D.R_NAME AS REG, SUM(F.L_EXTENDEDPRICE * (1 - F.L_DISCOUNT)) AS INGRESO
           FROM FACT_LINEITEM F
           JOIN DIM_CLIENTE_COMPLETA D ON F.O_CUSTKEY = D.C_CUSTKEY
           GROUP BY D.R_NAME)
SELECT (SELECT COUNT(*) FROM (SELECT * FROM n EXCEPT SELECT * FROM s))
     + (SELECT COUNT(*) FROM (SELECT * FROM s EXCEPT SELECT * FROM n)) AS FILAS_DIFERENTES,
       (SELECT COUNT(*) FROM n) AS N_REGIONES;

-- Espacio: la dimensión desnormalizada contra CUSTOMER + NATION + REGION (columna bytes).
SHOW TABLES LIKE 'DIM_CLIENTE_COMPLETA' IN SCHEMA CURSO.DEMO3_SF10;
SHOW TABLES IN SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCH_SF10;

-- Tiempos de ejecución y compilación de las tres consultas:
SELECT LEFT(REGEXP_REPLACE(QUERY_TEXT, $$\s+$$, ' '), 70) AS CONSULTA,
       EXECUTION_TIME AS EJECUCION_MS, COMPILATION_TIME AS COMPILACION_MS
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(RESULT_LIMIT => 12))
WHERE QUERY_TEXT ILIKE 'SELECT%R_NAME, ROUND(SUM(%' AND QUERY_TEXT NOT ILIKE '%QUERY_HISTORY%'
ORDER BY START_TIME DESC
LIMIT 3;  -- de la más reciente (estrella) a la más antigua (normalizado)


-- =====================================================================
-- DEMO 17 · Slide 28 · El grano: una fila es una línea de pedido
-- Qué se muestra: 6 001 215 filas y 6 001 215 claves distintas (L_ORDERKEY, L_LINENUMBER);
--   L_LINENUMBER va de 1 a 7. Contra 1 500 000 de ORDERS y 2 406 días.
-- Resultado esperado (M13, M1, M7): 6 001 215; 6 001 215; mínimo 1 y máximo 7; ORDERS 1 500 000;
--   días del rango de pedidos 2 406 (1992-01-01 a 1998-08-02).
-- =====================================================================
USE SCHEMA CURSO.DEMO3;

SELECT COUNT(*) AS FILAS,
       COUNT(DISTINCT L_ORDERKEY * 10 + L_LINENUMBER) AS CLAVES_DEL_GRANO,
       MIN(L_LINENUMBER) AS LINEA_MIN, MAX(L_LINENUMBER) AS LINEA_MAX
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM;

SELECT COUNT(*) AS PEDIDOS,
       MIN(O_ORDERDATE) AS PRIMERA, MAX(O_ORDERDATE) AS ULTIMA,
       DATEDIFF('day', MIN(O_ORDERDATE), MAX(O_ORDERDATE)) + 1 AS DIAS_EN_RANGO
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS;


-- =====================================================================
-- DEMO 18 · Slide 29 · La estrella responde con un hecho y las dimensiones que agrupa
-- Qué se muestra: ingreso por región y año con dos uniones (DIM_CLIENTE y DIM_FECHA), no cuatro.
--   Requiere la DEMO 0.
-- Resultado esperado (Lab 3C, C4): 35 filas (5 regiones por 7 años); primera: AFRICA, 1992,
--   6 608 511 861.49; última: MIDDLE EAST, 1998, 3 869 651 630.83; suma 218 102 223 885.00.
-- =====================================================================
SELECT D.R_NAME, T.ANIO, ROUND(SUM(F.INGRESO), 2) AS INGRESO
FROM CURSO.DEMO3.FACT_LINEITEM F
JOIN CURSO.DEMO3.DIM_CLIENTE D ON F.CLIENTE_KEY = D.CLIENTE_KEY
JOIN CURSO.DEMO3.DIM_FECHA T ON F.FECHA = T.FECHA
GROUP BY D.R_NAME, T.ANIO
ORDER BY D.R_NAME, T.ANIO;


-- =====================================================================
-- DEMO 19 · Slide 30 · Aditividad: LLUVIA_MM no se suma por zona
-- Qué se muestra: el 2024-01-10 la lluvia es una medida del día y está repetida en todas las filas
--   de zona; SUM(LLUVIA_MM) da un número que no es lluvia. INGRESO_TOTAL sí se suma. Los
--   promedios (PROPINA_PROMEDIO, DISTANCIA_PROMEDIO) se ponderan por VIAJES.
-- Resultado esperado (M12, gold de enero 2024): 514 filas el 2024-01-10, LLUVIA_MM 21.7 en todas
--   y SUM(LLUVIA_MM) = 11 153.8.
-- =====================================================================
SELECT COUNT(*) AS FILAS, MIN(LLUVIA_MM) AS LLUVIA_MIN, MAX(LLUVIA_MM) AS LLUVIA_MAX,
       SUM(LLUVIA_MM) AS SUMA_DE_LLUVIA
FROM BIGDATA.DEV.DAILY_ZONE_METRICS
WHERE FECHA = '2024-01-10';


-- =====================================================================
-- DEMO 20 · Slide 31 · Grano mezclado: la misma suma de la slide 2, ahora como error de la tabla
-- Qué se muestra: si un hecho de líneas guardara O_TOTALPRICE, la medida del pedido se repetiría
--   en cada línea y cualquier SUM saldría inflado. Una medida verdadera por línea (INGRESO) no.
-- Resultado esperado (M13, M14): SUM(O_TOTALPRICE) 226 829 306 447.46 en ORDERS contra
--   1 134 436 101 880.19 tras unir con LINEITEM (5.0 veces). INGRESO por línea suma
--   218 102 223 885.00: no reproduce el total del pedido (226 829 306 447.46) porque el pedido
--   incluye impuesto; con (1 + L_TAX) iguala 226 829 357 828.87, 0.00002 % más.
-- =====================================================================
SELECT (SELECT SUM(O_TOTALPRICE) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS) AS SUMA_PEDIDOS,
       SUM(O.O_TOTALPRICE) AS SUMA_INFLADA,
       ROUND(SUM(O.O_TOTALPRICE) / (SELECT SUM(O_TOTALPRICE) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS), 1) AS VECES
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM L
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O ON L.L_ORDERKEY = O.O_ORDERKEY;

SELECT ROUND(SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT)), 2) AS INGRESO_POR_LINEA,
       ROUND(SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT) * (1 + L_TAX)), 2) AS CON_IMPUESTO
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM;


-- =====================================================================
-- DEMO 21 · Slide 32 · Dimensión de fechas: el cliente 102022 compró en 39 de 2 406 días
-- Qué se muestra: GENERATOR crea 3 000 filas; ROW_NUMBER las numera sin huecos; QUALIFY deja
--   2 406 días; el LEFT JOIN conserva los días sin pedidos. Con todo SF1 no hay huecos; con un
--   solo cliente, sí.
-- Resultado esperado (M7, M16): DIAS 2 406, CON_PEDIDOS 39, SIN_PEDIDOS 2 367 (98.4 %).
-- =====================================================================
WITH r AS (SELECT MIN(O_ORDERDATE) AS MINF, MAX(O_ORDERDATE) AS MAXF
           FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS),
d AS (SELECT DATEADD('day', ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1, MINF)
             AS FECHA, MAXF
      FROM r, TABLE(GENERATOR(ROWCOUNT => 3000))
      QUALIFY FECHA <= MAXF),
p AS (SELECT DISTINCT O_ORDERDATE AS FECHA
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS WHERE O_CUSTKEY = 102022)
SELECT COUNT(*) AS DIAS, COUNT(p.FECHA) AS CON_PEDIDOS,
       COUNT(*) - COUNT(p.FECHA) AS SIN_PEDIDOS
FROM d LEFT JOIN p ON p.FECHA = d.FECHA;


-- =====================================================================
-- DEMO 22 · Slide 33 · SCD tipo 1: sobrescribir borra la historia
-- Qué se muestra: sobre una copia mínima de DIM_CLIENTE (solo el cliente 102022), el ingreso por
--   región antes y después de «mudarlo» a FRANCE (EUROPE). Los 41 pedidos pasan de ASIA a EUROPE,
--   incluidos los 19 anteriores a la mudanza. La mudanza es un supuesto; los pedidos son reales.
--   Requiere la DEMO 0.
-- Resultado esperado (M11, M18): antes, ASIA con 41 pedidos e ingreso 6 039 653.63; después,
--   EUROPE con 41 pedidos e ingreso 6 039 653.63; ASIA pierde 2 951 661.88 de los años 1992 a 1995.
-- =====================================================================
USE SCHEMA CURSO.DEMO3;

CREATE OR REPLACE TABLE DEMO_DIM AS
SELECT * FROM DIM_CLIENTE WHERE CLIENTE_KEY = 102022;

-- Antes
SELECT D.R_NAME, COUNT(DISTINCT F.L_ORDERKEY) AS PEDIDOS, ROUND(SUM(F.INGRESO), 2) AS INGRESO
FROM FACT_LINEITEM F JOIN DEMO_DIM D ON F.CLIENTE_KEY = D.CLIENTE_KEY
GROUP BY D.R_NAME;

UPDATE DEMO_DIM SET N_NAME = 'FRANCE', R_NAME = 'EUROPE' WHERE CLIENTE_KEY = 102022;

-- Después
SELECT D.R_NAME, COUNT(DISTINCT F.L_ORDERKEY) AS PEDIDOS, ROUND(SUM(F.INGRESO), 2) AS INGRESO
FROM FACT_LINEITEM F JOIN DEMO_DIM D ON F.CLIENTE_KEY = D.CLIENTE_KEY
GROUP BY D.R_NAME;


-- =====================================================================
-- DEMO 23 · Slide 34 · SCD tipo 2: una fila por versión conserva la historia
-- Qué se muestra: se cierra la fila vigente (HASTA = 1995-05-31, ES_ACTUAL = FALSE) y se inserta la
--   versión nueva con otra clave sustituta (SK). La unión con el hecho es por la clave de negocio
--   y FECHA BETWEEN DESDE AND HASTA. Requiere la DEMO 0.
-- Resultado esperado (M11, M18): ASIA con 19 pedidos e ingreso 2 951 661.88; EUROPE con 22
--   pedidos e ingreso 3 087 991.75; suman 6 039 653.63, igual al total.
-- =====================================================================
USE SCHEMA CURSO.DEMO3;

CREATE OR REPLACE TABLE DEMO_DIM_SCD2 AS
SELECT 1 AS SK, CLIENTE_KEY, N_NAME, R_NAME,
       DATE '1992-01-01' AS DESDE, DATE '9999-12-31' AS HASTA, TRUE AS ES_ACTUAL
FROM DIM_CLIENTE WHERE CLIENTE_KEY = 102022;

-- Cierra la versión vigente
UPDATE DEMO_DIM_SCD2 SET HASTA = DATE '1995-05-31', ES_ACTUAL = FALSE
WHERE CLIENTE_KEY = 102022 AND ES_ACTUAL;

-- Inserta la versión nueva
INSERT INTO DEMO_DIM_SCD2
VALUES (2, 102022, 'FRANCE', 'EUROPE', DATE '1995-06-01', DATE '9999-12-31', TRUE);

SELECT * FROM DEMO_DIM_SCD2 ORDER BY SK;

-- Ingreso por región según la versión vigente a la fecha del pedido
SELECT D.R_NAME, COUNT(DISTINCT F.L_ORDERKEY) AS PEDIDOS, ROUND(SUM(F.INGRESO), 2) AS INGRESO
FROM FACT_LINEITEM F
JOIN DEMO_DIM_SCD2 D ON F.CLIENTE_KEY = D.CLIENTE_KEY
                    AND F.FECHA BETWEEN D.DESDE AND D.HASTA
GROUP BY D.R_NAME
ORDER BY D.R_NAME;


-- =====================================================================
-- DEMO 24 · Slide 36 · Una estrella cuadra cuando pasan cuatro controles
-- Qué se muestra: filas, grano, claves sin pareja e ingreso, contra los valores medidos en el
--   origen. Requiere la DEMO 0.
-- Resultado esperado (M13, M18): filas 6 001 215 (esperado 6 001 215); grano 6 001 215;
--   sin cliente 0; ingreso 218 102 223 885.
-- =====================================================================
USE SCHEMA CURSO.DEMO3;

SELECT 'filas' AS CONTROL, COUNT(*) AS FACT, 6001215 AS ESPERADO
FROM FACT_LINEITEM
UNION ALL
SELECT 'grano', COUNT(DISTINCT L_ORDERKEY * 10 + L_LINENUMBER), 6001215
FROM FACT_LINEITEM
UNION ALL
SELECT 'sin cliente', COUNT(*), 0
FROM FACT_LINEITEM F LEFT JOIN DIM_CLIENTE D USING (CLIENTE_KEY)
WHERE D.C_NAME IS NULL
UNION ALL
SELECT 'ingreso', ROUND(SUM(INGRESO)), 218102223885 FROM FACT_LINEITEM;


-- =====================================================================
-- DEMO 25 · Slide 37 · Caso NYC: la lluvia repetida en cada fila del gold
-- Qué se muestra: el gold de enero 2024 tiene 15 909 filas (fecha, zona, empresa) y repite
--   LLUVIA_MM en 511 a 515 filas por día; la estrella propuesta la guardaría una vez por día.
--   Vista previa, solo enero 2024: es descripción de 31 días, no evidencia de causa.
-- Resultado esperado (M12): 15 909 filas, 31 días, 261 zonas, 2 empresas, 19 650 023 viajes;
--   18 días con lluvia (LLUVIA_MM mayor que 0) con 644 028 viajes por día y 13 sin lluvia con
--   619 809.
-- =====================================================================
SELECT COUNT(*) AS FILAS, COUNT(DISTINCT FECHA) AS DIAS, COUNT(DISTINCT ZONA) AS ZONAS,
       COUNT(DISTINCT EMPRESA) AS EMPRESAS, SUM(VIAJES) AS VIAJES
FROM BIGDATA.DEV.DAILY_ZONE_METRICS;

SELECT MIN(N) AS FILAS_POR_DIA_MIN, MAX(N) AS FILAS_POR_DIA_MAX
FROM (SELECT FECHA, COUNT(*) AS N FROM BIGDATA.DEV.DAILY_ZONE_METRICS GROUP BY FECHA);

WITH dia AS (SELECT FECHA, MAX(LLUVIA_MM) AS LLUVIA_MM, SUM(VIAJES) AS VIAJES
             FROM BIGDATA.DEV.DAILY_ZONE_METRICS
             GROUP BY FECHA)
SELECT IFF(LLUVIA_MM > 0, 'con lluvia', 'sin lluvia') AS DIA, COUNT(*) AS DIAS,
       ROUND(AVG(VIAJES)) AS VIAJES_POR_DIA
FROM dia
GROUP BY 1
ORDER BY 1;


-- =====================================================================
-- DEMO 26 · Slide 35 (Lab 3C) · Leer la carga en el Query Profile
-- Qué se muestra: con la marca LAB3C, la consulta de lectura del lab lista los pasos de mayor a
--   menor tiempo de ejecución; el paso más caro es FACT_LINEITEM y el operador que concentra el
--   tiempo es CreateTableAsSelect. Aquí se repiten dos cargas con la marca en el esquema
--   CURSO.DEMO3 (en el lab, el esquema es CURSO.LAB3C).
-- Resultado esperado (lab3c_solucion.sql, X-Small): FACT_LINEITEM primero, unos 2 s; el resto,
--   entre 0.5 y 1.5 s. En su perfil, CreateTableAsSelect entre 71 y 98 % del tiempo
--   (rango medido en varias corridas; evidencia.sql, bloque 35).
-- =====================================================================
USE SCHEMA CURSO.DEMO3;
ALTER SESSION SET QUERY_TAG = 'LAB3C';

CREATE OR REPLACE TABLE DIM_CLIENTE_L AS
SELECT C.C_CUSTKEY AS CLIENTE_KEY, C.C_NAME, C.C_MKTSEGMENT, N.N_NAME, R.R_NAME
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER C
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION N ON C.C_NATIONKEY = N.N_NATIONKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION R ON N.N_REGIONKEY = R.R_REGIONKEY;

CREATE OR REPLACE TABLE FACT_LINEITEM_L AS
SELECT L.L_ORDERKEY, L.L_LINENUMBER, O.O_CUSTKEY AS CLIENTE_KEY, O.O_ORDERDATE AS FECHA,
       L.L_PARTKEY AS PRODUCTO_KEY, L.L_QUANTITY, L.L_EXTENDEDPRICE, L.L_DISCOUNT,
       L.L_EXTENDEDPRICE * (1 - L.L_DISCOUNT) AS INGRESO
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM L
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O ON L.L_ORDERKEY = O.O_ORDERKEY;

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
    AND SCHEMA_NAME = 'DEMO3'
)
SELECT PASO, SEGUNDOS, QUERY_ID
FROM H
QUALIFY ROW_NUMBER() OVER (PARTITION BY PASO ORDER BY START_TIME DESC) = 1
ORDER BY SEGUNDOS DESC, PASO;

ALTER SESSION UNSET QUERY_TAG;
-- Abre el perfil del primero: Monitoring > Query History > consulta > Query Profile.


-- =====================================================================
-- CIERRE DE LAS DEMOS
-- =====================================================================
-- Si dejaste COMPUTE_WH encendido, se suspende solo a los 60 s. Para suspenderlo ya:
--   ALTER WAREHOUSE COMPUTE_WH SUSPEND;   -- error 090064 si ya estaba suspendido: ignorar.
-- Para borrar los objetos de las demos (opcional, después de la clase):
--   DROP SCHEMA IF EXISTS CURSO.DEMO3;
--   DROP SCHEMA IF EXISTS CURSO.DEMO3_SF10;   -- libera 1.5 GB del hecho de SF10
