-- =====================================================================
-- LAB 3A · Ventanas sobre ORDERS (Big Data UdeM · Clase 3)
-- =====================================================================
--
-- OBJETIVO
--   Calcular sin perder filas: top-N por grupo, último pedido, variación contra el periodo anterior
--   con LAG, acumulado y participación dentro del total. Para quien termine: media móvil, RANK
--   frente a DENSE_RANK, acumulado por año y rachas de meses.
--
-- GLOSARIO (solo lo nuevo respecto del Lab 2)
--   ventana      conjunto de filas que mira una función para cada fila, sin colapsarlas.
--   partición    grupo de la ventana (PARTITION BY).
--   marco        filas de la partición que entran en cada cálculo (ROWS BETWEEN ...).
--   posición     número de orden de una fila en su partición (ranking).
--   acumulado    suma desde la primera fila hasta la actual.
--   media móvil  promedio de las últimas N filas.
--   empate       dos filas con el mismo valor de orden.
--
-- CÓMO COPIAR ESTE ARCHIVO A SNOWSIGHT (solo navegador, sin terminal)
--   1. En tu fork: carpeta curso > clase03 > lab3a.sql.
--   2. Arriba a la derecha del contenido, el ícono de dos cuadritos es "Copy raw file"
--      (no el de la flecha hacia abajo).
--   3. En Snowsight: Projects > Worksheets > botón + (SQL Worksheet). Si tu Snowsight muestra
--      "Workspaces", usa + > SQL File.
--   4. Pega todo (Ctrl/Cmd + V). No elijas rol ni warehouse: el Paso 0 los fija.
--   5. Si no ves el archivo: botón "Sync fork" > "Update branch".
--
-- CÓMO CORRER
--   Paso 0: selecciona de USE ROLE a USE SCHEMA CURSO.LAB3A; y pulsa ▶.
--   Vista entregada: corre el bloque CREATE OR REPLACE VIEW MENSUAL_1995 (ya está escrito).
--   Ejercicios: bloque a bloque con Cmd/Ctrl+Enter (corre la consulta donde está el cursor).
--   Run All corre todo el archivo: en este archivo NO lo uses.
--   Si ya hiciste el bootstrap de AWS en la clase 2, abre ahora SageMaker Studio y pulsa
--   Run space (paso 5.2 de docs/guia.md): tarda 3-5 min y el Code Editor queda listo para la
--   parada de AWS de después de este lab.
--
-- TIEMPO: 27 min en clase. Orden: EJ1 a EJ5 (★, núcleo; la verificación exige los cinco).
--   EJ6 a EJ8 (★★) y EJ9 (★★★) son opcionales.
--
-- NIVELES
--   ★    núcleo: cinco ejercicios; la verificación exige los cinco
--   ★★   si queda tiempo
--   ★★★  reto
--
-- REGLA DEL LAB
--   ROW_NUMBER no tiene orden garantizado entre empates: todo ranking lleva una columna de
--   desempate. EJ1 a EJ3 se resuelven con subconsulta (QUALIFY es del Lab 3B). Observa en esos
--   tres ejercicios que, para filtrar por el resultado de una ventana, la consulta queda
--   anidada: anótalo, porque se resuelve después del descanso.
--
-- DICCIONARIO RÁPIDO (TPC-H, factor de escala 1: 1 500 000 pedidos)
--   ORDERS    O_ORDERKEY, O_CUSTKEY, O_ORDERSTATUS, O_TOTALPRICE, O_ORDERDATE, O_ORDERPRIORITY
--   Las tablas viven en SNOWFLAKE_SAMPLE_DATA.TPCH_SF1 (solo lectura). Escribe siempre la ruta
--   completa, por ejemplo SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS.
--
-- TIPOS DE LAS COLUMNAS
--   MES en EJ3 es una fecha (el primer día del mes). En EJ8, MES es el número de mes,
--   MONTH(O_ORDERDATE), de 1 a 12, y ANIO es YEAR(O_ORDERDATE).
--
-- =====================================================================
-- CÓMO ESCRIBIR CADA EJERCICIO (la misma plantilla en todos)
-- =====================================================================
-- Escribes solo en el lugar del marcador (la línea SELECT NULL AS PENDIENTE):
--
--   ANTES (así llega el archivo):
--     CREATE OR REPLACE VIEW EJ1 AS
--     -- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
--     SELECT NULL AS PENDIENTE
--     -- ▲▲ hasta aquí ▲▲
--     ;
--     SELECT * FROM EJ1;  -- mira tu resultado
--
--   DESPUÉS (reemplazas el marcador por tu SELECT, sin ; al final del SELECT):
--     CREATE OR REPLACE VIEW EJ1 AS
--     -- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
--     SELECT R_NAME, ROW_NUMBER() OVER (ORDER BY R_NAME) AS RN
--     FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION
--     -- ▲▲ hasta aquí ▲▲
--     ;
--     SELECT * FROM EJ1;  -- mira tu resultado
--
-- Ejecuta los dos bloques con Cmd/Ctrl+Enter. Debes ver "View EJ1 successfully created" y
-- luego tu resultado. Si ves un mensaje rojo, el CREATE falló: lee el mensaje y consulta la
-- tabla de errores comunes al final. Los nombres de las columnas de salida son parte del
-- ejercicio y deben coincidir (mayúsculas o minúsculas no importan). Cada columna calculada
-- (COUNT, SUM, AVG, ROW_NUMBER...) necesita AS NOMBRE; si no, la vista falla con
-- "Missing column specification".
--
-- Cada ejercicio es una vista: una consulta guardada con nombre. La vista no guarda datos,
-- guarda la consulta; por eso la verificación puede leer EJ1, EJ2... sin preguntarte nada.
-- =====================================================================


-- =====================================================================
-- PASO 0 · PREPARACIÓN (ya resuelto: no lo cambies)
-- QUÉ HACER: selecciona con el mouse desde USE ROLE hasta USE SCHEMA CURSO.LAB3A; y pulsa ▶.
-- Es idempotente: puedes correrlo más de una vez.
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
-- VISTA ENTREGADA · MENSUAL_1995 (ya resuelta: corre el bloque tal como está)
-- =====================================================================
-- Una fila por mes de 1995: MES es el primer día del mes y MONTO, la suma de O_TOTALPRICE de ese
-- mes. La usa EJ3. Es una vista: guarda la consulta, no los datos.

CREATE OR REPLACE VIEW MENSUAL_1995 AS
SELECT DATE_TRUNC('month', O_ORDERDATE) AS MES, SUM(O_TOTALPRICE) AS MONTO
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_ORDERDATE >= '1995-01-01' AND O_ORDERDATE < '1996-01-01'
GROUP BY DATE_TRUNC('month', O_ORDERDATE);
SELECT * FROM MENSUAL_1995 ORDER BY MES LIMIT 3;
-- Debes ver: 3 filas: 1995-01-01 con 2946587345.85, 1995-02-01 con 2689142056.26 y 1995-03-01 con 2910048327.04.


-- =====================================================================
-- ASÍ LUCE UNA VENTANA (corre este bloque después del Paso 0)
-- =====================================================================
-- Cada pedido del cliente 102022 conserva su fila y recibe el total de su cliente.
SELECT O_ORDERKEY, O_ORDERDATE, O_TOTALPRICE,
       SUM(O_TOTALPRICE) OVER (PARTITION BY O_CUSTKEY) AS TOTAL_CLIENTE
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_CUSTKEY = 102022
ORDER BY O_ORDERDATE, O_ORDERKEY
LIMIT 3;
-- Debes ver: 3 filas con TOTAL_CLIENTE = 6273788.41 en cada una (144930.46, 111485.66 y 63555.44 son los montos).
-- Un GROUP BY por cliente habría devuelto una sola fila y habría borrado los pedidos.


-- =====================================================================
-- EJERCICIO 1 ★ · ROW_NUMBER y PARTITION BY: top-N por grupo
-- =====================================================================
-- DEFINICIÓN:
--   Una VENTANA calcula para cada fila mirando un conjunto de filas relacionadas, sin colapsarlas.
--   OVER (...) define la ventana. PARTITION BY la divide en grupos, uno por valor de la columna.
--   ROW_NUMBER() numera las filas de cada grupo según el ORDER BY de la ventana. Con empates el
--   orden no está garantizado: añade siempre una columna de desempate (por ejemplo una clave).
--   La ventana no se puede filtrar en WHERE (se evalúa antes): se calcula en una subconsulta y se
--   filtra afuera. En el Lab 3B verás cómo evitar el anidado.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT C_MKTSEGMENT, C_CUSTKEY, C_ACCTBAL, RN
FROM (SELECT C_MKTSEGMENT, C_CUSTKEY, C_ACCTBAL,
             ROW_NUMBER() OVER (PARTITION BY C_MKTSEGMENT
                                ORDER BY C_ACCTBAL DESC, C_CUSTKEY) AS RN
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER)
WHERE RN = 1
ORDER BY C_MKTSEGMENT;
-- Debes ver en el ejemplo: 5 filas, el cliente de mayor saldo de cada segmento: AUTOMOBILE 69321 (9999.96), BUILDING 61453 (9999.99), FURNITURE 144232 (9999.74), HOUSEHOLD 76146 (9999.23), MACHINERY 23828 (9999.64).
--
-- TU TURNO:
--   De ORDERS, los 3 pedidos más caros (O_TOTALPRICE) de cada prioridad (O_ORDERPRIORITY).
--   Desempata por O_ORDERKEY ascendente. Ordena por O_ORDERPRIORITY y RN.
--   Columnas de salida (en este orden): O_ORDERPRIORITY, O_ORDERKEY, O_TOTALPRICE, RN

CREATE OR REPLACE VIEW EJ1 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ1;  -- mira tu resultado

-- ✅ Debes ver: 15 filas. Primera: 1-URGENT, 4722021, 544089.09, 1. Última: 5-LOW, 631651, 504509.06, 3.


-- =====================================================================
-- EJERCICIO 2 ★ · El último de cada grupo
-- =====================================================================
-- DEFINICIÓN:
--   El último elemento de cada grupo es el primero del orden inverso: ROW_NUMBER con
--   ORDER BY ... DESC y el filtro RN = 1. El desempate también va en sentido descendente.
--   El filtro por la ventana se hace afuera de la consulta que la calcula.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT O_CUSTKEY, O_ORDERKEY, O_ORDERDATE
FROM (SELECT O_CUSTKEY, O_ORDERKEY, O_ORDERDATE,
             ROW_NUMBER() OVER (PARTITION BY O_CUSTKEY
                                ORDER BY O_ORDERDATE, O_ORDERKEY) AS RN
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
      WHERE O_CUSTKEY <= 5)
WHERE RN = 1
ORDER BY O_CUSTKEY;
-- Debes ver en el ejemplo: 4 filas, el primer pedido de cada cliente (el 3 no tiene pedidos): 1 pedido 454791 (1992-04-19), 2 pedido 1374019 (1992-04-05), 4 pedido 164711 (1992-04-26), 5 pedido 2630562 (1993-06-27).
--
-- TU TURNO:
--   De ORDERS, el pedido más reciente de cada cliente (por O_ORDERDATE).
--   Desempata por O_ORDERKEY descendente. Ordena por O_CUSTKEY.
--   Columnas de salida (en este orden): O_CUSTKEY, O_ORDERKEY, O_ORDERDATE

CREATE OR REPLACE VIEW EJ2 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ2 ORDER BY 1 LIMIT 20;  -- mira tu resultado (la vista tiene 99996 filas)

-- ✅ Debes ver: 99996 filas. Primera: cliente 1, pedido 4273923, 1997-03-23.


-- =====================================================================
-- EJERCICIO 3 ★ · LAG: comparar con la fila anterior
-- =====================================================================
-- DEFINICIÓN:
--   LAG(columna) devuelve el valor de la fila anterior según el ORDER BY de la ventana; LEAD, el
--   de la siguiente. La primera fila no tiene anterior: LAG da NULL. Una variación porcentual
--   es (actual - anterior) / anterior * 100.
--   Después del Paso 0, este archivo crea la vista MENSUAL_1995 (ya resuelta): una fila por mes de
--   1995 con MES (el primer día del mes) y MONTO (la suma de O_TOTALPRICE del mes). Tu trabajo es el
--   LAG y el filtro.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT N_NATIONKEY, N_NAME,
       LAG(N_NAME) OVER (ORDER BY N_NATIONKEY) AS NACION_ANTERIOR
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION
ORDER BY N_NATIONKEY
LIMIT 3;
-- Debes ver en el ejemplo: 3 filas: 0 ALGERIA NULL, 1 ARGENTINA ALGERIA, 2 BRAZIL ARGENTINA.
--
-- TU TURNO:
--   Con la vista MENSUAL_1995, los meses cuyo monto cayó frente al mes anterior.
--   VARIACION_PCT = (MONTO - MONTO_ANTERIOR) / MONTO_ANTERIOR * 100, redondeada a 2 decimales.
--   Enero no tiene mes anterior: LAG da NULL y el filtro lo descarta. Ordena por MES.
--   Columnas de salida (en este orden): MES, MONTO, MONTO_ANTERIOR, VARIACION_PCT

CREATE OR REPLACE VIEW EJ3 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ3;  -- mira tu resultado

-- ✅ Debes ver: 6 filas: feb (-8.74), abr (-1.95), jun (-1.46), ago (-0.16), sep (-4.35), nov (-3.96). Primera: 1995-02-01, 2689142056.26, 2946587345.85, -8.74.


-- =====================================================================
-- EJERCICIO 4 ★ · Acumulado con marco ROWS
-- =====================================================================
-- DEFINICIÓN:
--   El MARCO limita qué filas de la partición entran en el cálculo de cada fila. ROWS BETWEEN
--   UNBOUNDED PRECEDING AND CURRENT ROW cuenta filas desde la primera hasta la actual: es el
--   ACUMULADO. Sin marco explícito, con ORDER BY el marco agrupa por VALOR de la columna de orden
--   (RANGE) y dos pedidos del mismo día reciben el mismo acumulado. Declara ROWS y desempata.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT C_CUSTKEY, C_ACCTBAL,
       SUM(C_ACCTBAL) OVER (ORDER BY C_CUSTKEY
                            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS ACUMULADO
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER
WHERE C_NATIONKEY = 0
ORDER BY C_CUSTKEY
LIMIT 3;
-- Debes ver en el ejemplo: 3 filas: 29 con 7618.27 y acumulado 7618.27; 48 con 3792.50 y 11410.77; 73 con 4288.50 y 15699.27.
--
-- TU TURNO:
--   Del cliente 102022, el acumulado del monto (O_TOTALPRICE) por orden de fecha, con desempate por
--   O_ORDERKEY, contando filas (ROWS) y no valores de fecha. Ordena por O_ORDERDATE y O_ORDERKEY.
--   Columnas de salida (en este orden): O_ORDERKEY, O_ORDERDATE, O_TOTALPRICE, ACUMULADO

CREATE OR REPLACE VIEW EJ4 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ4;  -- mira tu resultado

-- ✅ Debes ver: 41 filas. El pedido 562371 (1994-12-15) acumula 2359717.42; la última fila, 6273788.41.


-- =====================================================================
-- EJERCICIO 5 ★ · Participación: una ventana sobre una agregación
-- =====================================================================
-- DEFINICIÓN:
--   Una ventana puede calcularse sobre el resultado de un GROUP BY. SUM(COUNT(*)) OVER () suma los
--   conteos de todos los grupos (OVER () sin PARTITION BY: la ventana es toda la salida). Así cada
--   grupo conserva su fila y recibe el total contra el cual se compara. Participación =
--   100 * parte / total.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT L_RETURNFLAG, COUNT(*) AS LINEAS,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS PCT
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM
GROUP BY L_RETURNFLAG
ORDER BY L_RETURNFLAG;
-- Debes ver en el ejemplo: 3 filas: A 1478493 24.64; N 3043852 50.72; R 1478870 24.64.
--
-- TU TURNO:
--   Cuántos pedidos tiene cada estado (O_ORDERSTATUS) en ORDERS y qué porcentaje del total de
--   pedidos es (PCT = 100 * PEDIDOS / total de pedidos), con 2 decimales. Ordena por O_ORDERSTATUS.
--   Columnas de salida (en este orden): O_ORDERSTATUS, PEDIDOS, PCT

CREATE OR REPLACE VIEW EJ5 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ5;  -- mira tu resultado

-- ✅ Debes ver: 3 filas: F 729413 48.63; O 732044 48.80; P 38543 2.57.


-- =====================================================================
-- EJERCICIO 6 ★★ · Media móvil
-- =====================================================================
-- DEFINICIÓN:
--   Una media móvil promedia las últimas N filas: AVG con el marco ROWS BETWEEN (N-1) PRECEDING AND
--   CURRENT ROW. Las primeras filas promedian menos de N valores. La media móvil de este ejercicio
--   es de tres PEDIDOS, no de tres días: si faltan días, no es una media de periodo fijo.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT C_CUSTKEY, C_ACCTBAL,
       ROUND(AVG(C_ACCTBAL) OVER (ORDER BY C_CUSTKEY
                                  ROWS BETWEEN 1 PRECEDING AND CURRENT ROW), 2) AS MEDIA_MOVIL_2
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER
WHERE C_NATIONKEY = 0
ORDER BY C_CUSTKEY
LIMIT 4;
-- Debes ver en el ejemplo: 4 filas: 29 con 7618.27 y 7618.27; 48 con 3792.50 y 5705.39; 73 con 4288.50 y 4040.50; 76 con 5745.33 y 5016.92.
--
-- TU TURNO:
--   Del cliente 102022, la media móvil del monto (O_TOTALPRICE) de los 3 últimos pedidos (el actual y
--   2 anteriores), por orden de fecha y O_ORDERKEY, redondeada a 2 decimales.
--   Columnas de salida (en este orden): O_ORDERKEY, O_ORDERDATE, O_TOTALPRICE, MEDIA_MOVIL_3

CREATE OR REPLACE VIEW EJ6 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ6;  -- mira tu resultado

-- ✅ Debes ver: 41 filas. Segunda: 128208.06; tercera: 106657.19; última: 140269.87.


-- =====================================================================
-- EJERCICIO 7 ★★ · RANK contra DENSE_RANK
-- =====================================================================
-- DEFINICIÓN:
--   Con empates, ROW_NUMBER no repite (1, 2, 3...), RANK repite y salta (1, 1, 1, 4...) y
--   DENSE_RANK repite sin saltar (1, 1, 1, 2...). RANK sirve cuando los empatados comparten puesto;
--   DENSE_RANK, cuando se piden los N valores más altos.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT N.N_NAME, COUNT(*) AS CLIENTES,
       RANK() OVER (ORDER BY COUNT(*) DESC) AS RK,
       DENSE_RANK() OVER (ORDER BY COUNT(*) DESC) AS DR
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER C JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION N ON C.C_NATIONKEY = N.N_NATIONKEY
GROUP BY N.N_NAME
ORDER BY CLIENTES DESC, N.N_NAME
LIMIT 5;
-- Debes ver en el ejemplo: 5 filas: INDONESIA 6161 (RK 1, DR 1); FRANCE 6100 y ROMANIA 6100 (RK 2, DR 2); RUSSIA 6078 (RK 4, DR 3); INDIA 6042 (RK 5, DR 4).
--
-- TU TURNO:
--   Los clientes de ORDERS (O_CUSTKEY) cuyo DENSE_RANK por número de pedidos (de más a menos) sea 1 o 2,
--   con su RANK. PEDIDOS es el conteo; RK, el RANK; DR, el DENSE_RANK.
--   Ordena por PEDIDOS descendente y O_CUSTKEY.
--   Columnas de salida (en este orden): O_CUSTKEY, PEDIDOS, RK, DR

CREATE OR REPLACE VIEW EJ7 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ7;  -- mira tu resultado

-- ✅ Debes ver: 6 filas: 3451, 102004 y 102022 con 41 pedidos (RK 1, DR 1); 79300, 117082 y 122623 con 40 (RK 4, DR 2).


-- =====================================================================
-- EJERCICIO 8 ★★ · Acumulado que se reinicia por grupo
-- =====================================================================
-- DEFINICIÓN:
--   PARTITION BY + ORDER BY + marco da un acumulado que se reinicia en cada grupo: aquí, cada año.
--   En este ejercicio ANIO es YEAR(O_ORDERDATE) y MES es MONTH(O_ORDERDATE), un número de 1 a 12.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT N_REGIONKEY, N_NAME,
       COUNT(*) OVER (PARTITION BY N_REGIONKEY ORDER BY N_NATIONKEY
                      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS NUM_EN_REGION
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION
ORDER BY N_REGIONKEY, N_NATIONKEY
LIMIT 7;
-- Debes ver en el ejemplo: 7 filas: región 0 con ALGERIA 1, ETHIOPIA 2, KENYA 3, MOROCCO 4 y MOZAMBIQUE 5; región 1 reinicia: ARGENTINA 1, BRAZIL 2.
--
-- TU TURNO:
--   Monto mensual de 1995 y 1996 (suma de O_TOTALPRICE de ORDERS) con el acumulado que se reinicia
--   cada año. Ordena por ANIO y MES.
--   Columnas de salida (en este orden): ANIO, MES, MONTO, ACUM_ANIO

CREATE OR REPLACE VIEW EJ8 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ8;  -- mira tu resultado

-- ✅ Debes ver: 24 filas. ANIO 1995, MES 12: ACUM_ANIO 34546133183.60. ANIO 1996, MES 1: MONTO y ACUM_ANIO 2903467749.81 (reinicia). ANIO 1996, MES 12: 34609364760.86.


-- =====================================================================
-- EJERCICIO 9 ★★★ · Rachas de meses consecutivos (gaps and islands)
-- =====================================================================
-- DEFINICIÓN:
--   Para encontrar rachas: numera los valores con ROW_NUMBER y resta ese número a cada valor. Los valores
--   consecutivos dan la misma resta, y esa resta identifica la racha. Después se agrupa por ella.
--   Con meses, la resta es DATEADD('month', -ROW_NUMBER() OVER (ORDER BY MES), MES).
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT MIN(N) AS INICIO, MAX(N) AS FIN, COUNT(*) AS VALORES
FROM (SELECT N, N - ROW_NUMBER() OVER (ORDER BY N) AS GRUPO
      FROM VALUES (1), (2), (3), (5), (6), (9) T(N))
GROUP BY GRUPO
ORDER BY INICIO;
-- Debes ver en el ejemplo: 3 filas: 1 a 3 (3 valores), 5 a 6 (2 valores), 9 a 9 (1 valor).
--
-- TU TURNO:
--   Del cliente 102022, las rachas de meses consecutivos con al menos un pedido: cada racha con su
--   primer mes (INICIO), su último mes (FIN, ambos como primer día del mes) y cuántos meses dura
--   (MESES). Ordena por INICIO.
--   Columnas de salida (en este orden): INICIO, FIN, MESES

CREATE OR REPLACE VIEW EJ9 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ9;  -- mira tu resultado

-- ✅ Debes ver: 21 filas; la suma de MESES es 33. Primera: 1992-01-01, 1992-02-01, 2. La más larga: 1992-04-01, 1992-07-01, 4.



-- =====================================================================
-- PASO FINAL · Corre la verificación
-- =====================================================================
-- 1. Copia lab3a_verificacion.sql igual que copiaste este archivo.
-- 2. En Snowsight abre OTRA hoja nueva (+ SQL Worksheet o + > SQL File), pega todo y pulsa Run All.
-- 3. Busca la tabla final: EJERCICIO, NIVEL, RESULTADO, PISTA.
--
-- Una fila por ejercicio:
--   OK         = correcto.
--   REVISAR    = la vista existe pero no coincide. Lee la PISTA y compara TUS_COLUMNAS con
--                COLUMNAS_ESPERADAS.
--   PENDIENTE  = la vista todavía tiene el marcador SELECT NULL AS PENDIENTE.
-- La última fila es el resumen: cuántos de los 5 ★ están en OK. META: RESUMEN = OK y "5 de 5".
-- PENDIENTE en EJ6 a EJ9 es normal si no llegaste a los ★★. Si dice PENDIENTE pero escribiste tu
-- SELECT, el CREATE falló: busca el mensaje rojo.


-- =====================================================================
-- QUÉ APRENDISTE
-- =====================================================================
-- - Una ventana calcula sobre un grupo de filas sin borrarlas: el detalle y el resumen quedan en
--   la misma fila (GROUP BY devuelve una fila por grupo).
-- - PARTITION BY decide qué filas se miran juntas; ORDER BY, en qué orden; el marco (ROWS ...)
--   decide cuántas filas entran en cada cálculo.
-- - Los empates exigen una columna de desempate: ROW_NUMBER no fija su orden. RANK salta y
--   DENSE_RANK no.
-- - LAG mira la fila anterior, no el día anterior: si faltan días, la fila anterior puede estar
--   lejos.
-- - Para filtrar por una ventana hubo que anidar la consulta: EJ1 a EJ3.
--
-- Siguiente: estas consultas se vuelven código de un pipeline en la clase 5, y para eso se deja
-- listo el Code Editor en la parada de AWS; tras el descanso, EJ1 a EJ3 se reescriben sin
-- anidar (Lab 3B).


-- =====================================================================
-- ERRORES COMUNES
-- =====================================================================
-- Mensaje o síntoma                             | Causa                          | Cómo evitarlo
-- ---------------------------------------------|--------------------------------|---------------------------
-- Window function [...] appears outside of     | Filtraste con WHERE el         | Calcula la ventana en una
--   SELECT, QUALIFY, and ORDER BY clauses      | resultado de una ventana       | subconsulta y filtra afuera
--                                              |                                | (en el Lab 3B, con QUALIFY)
-- El acumulado de dos pedidos del mismo día es | Sin marco ROWS, el marco       | Escribe ROWS BETWEEN
--   igual                                      | agrupa por valor de fecha      | UNBOUNDED PRECEDING AND
--                                              |                                | CURRENT ROW y desempata
-- REVISAR en EJ1 con la clave correcta         | Falta el desempate; con        | Añade O_ORDERKEY al ORDER BY
--                                              | empates ROW_NUMBER cambia      | de la ventana
-- 'X' in select clause is neither an aggregate | Mezclaste columnas sin agregar | Agrega al GROUP BY o aplica
--   nor in the group by clause (EJ3, EJ5)      | con una agregación             | la ventana sobre la agregación
-- El primer mes de EJ3 trae NULL               | LAG no tiene mes anterior      | Es lo esperado; el filtro de
--                                              |                                | caída lo descarta
-- This session does not have a current         | No se corrió el Paso 0 en esa  | Selecciona de USE ROLE a
--   database                                   | hoja                           | USE SCHEMA CURSO.LAB3A; y
--                                              |                                | pulsa ▶
-- Object 'MENSUAL_1995' does not exist (EJ3)   | No corriste el bloque de la    | Corre el CREATE OR REPLACE
--                                              | vista entregada                | VIEW MENSUAL_1995
-- REVISAR con columnas distintas               | El alias de salida no coincide | Compara TUS_COLUMNAS con
--                                              |                                | COLUMNAS_ESPERADAS
