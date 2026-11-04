-- =====================================================================
-- MINI-CASO · Negocio sobre TPC-H y lectura del Query Profile (Big Data UdeM · Clase 2)
-- =====================================================================
--
-- CONTEXTO
--   La dirección comercial de un mayorista (TPC-H, factor de escala 10: 15 000 000 de pedidos y
--   59 986 052 líneas) plantea cuatro preguntas. Cada una es una vista (Q1 a Q4) en CURSO.CASO.
--   Cada pregunta usa una pieza del día: Q1 filtro de fecha y tres uniones; Q2 HAVING; Q3 LEFT JOIN;
--   Q4 cinco tablas. Al final se lee el Query Profile de la consulta más pesada (Q4).
--
-- QUÉ HACER Y CUÁNDO
--   En clase: Q1 y Q4, y la lectura del perfil de Q4.   Después de clase: Q2 y Q3.
--   La verificación cuenta las cuatro: la meta es RESUMEN = OK y "4 de 4".
--   El mini-caso reutiliza las piezas del Lab 2 (GROUP BY, HAVING, JOIN, LEFT JOIN); no usa
--   subconsultas, CTE ni ventanas.
--
-- CÓMO COPIAR ESTE ARCHIVO A SNOWSIGHT (solo navegador, sin terminal)
--   1. En tu fork: carpeta curso > clase02 > caso.sql. Ícono de dos cuadritos = "Copy raw file".
--   2. En Snowsight: Projects > Worksheets > + (SQL Worksheet), o + > SQL File en "Workspaces".
--   3. Pega todo. No elijas rol ni warehouse: el Paso 0 los fija. Si falta el archivo: "Sync fork".
--
-- CÓMO CORRER
--   Paso 0: selecciona de USE ROLE a ALTER SESSION SET USE_CACHED_RESULT = FALSE; y pulsa ▶.
--   Vistas: bloque a bloque con Cmd/Ctrl+Enter. Run All no: en este archivo NO lo uses.
--   Q4 corre sobre 59 986 052 líneas: en X-Small tarda unos segundos; espera el resultado.
--
-- DICCIONARIO RÁPIDO (SNOWFLAKE_SAMPLE_DATA.TPCH_SF10; escribe la ruta completa)
--   CUSTOMER  C_CUSTKEY, C_NATIONKEY          NATION  N_NATIONKEY, N_NAME, N_REGIONKEY
--   ORDERS    O_ORDERKEY, O_CUSTKEY, O_TOTALPRICE, O_ORDERDATE
--   LINEITEM  L_ORDERKEY, L_EXTENDEDPRICE, L_SHIPMODE, L_SHIPDATE
--   REGION    R_REGIONKEY, R_NAME
--
-- PLANTILLA (la misma de los Labs): escribes solo en lugar del marcador SELECT NULL AS PENDIENTE,
-- sin punto y coma al final del SELECT. Cada columna calculada lleva AS. Los nombres de las columnas
-- de salida son parte del enunciado.
--   ANTES:   SELECT NULL AS PENDIENTE
--   DESPUÉS: SELECT R_NAME AS REGION FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.REGION
--
-- =====================================================================
-- PASO 0 · PREPARACIÓN (ya resuelto: no lo cambies; es idempotente)
-- QUÉ HACER: selecciona con el mouse desde USE ROLE hasta ALTER SESSION SET USE_CACHED_RESULT = FALSE;
-- y pulsa ▶.
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
-- Pregunta de negocio: ¿cuánto vendió cada región en 1995?
-- Pedidos con O_ORDERDATE en 1995 (>= '1995-01-01' y < '1996-01-01'); la región del pedido es la
-- de su cliente (ORDERS > CUSTOMER > NATION > REGION). Monto = SUM(O_TOTALPRICE).
-- Ordena por MONTO_TOTAL de mayor a menor y por REGION.
--
-- DEFINICIÓN:
--   Cuatro tablas encadenadas, cada una con su ON. El filtro de fecha va en WHERE (filtra filas),
--   no en HAVING. Cada pedido tiene un solo cliente: la cardinalidad es n a 1 y el conteo no se infla.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter; otra tabla que la tuya):
SELECT O_ORDERSTATUS, COUNT(*) AS PEDIDOS
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS
WHERE O_ORDERDATE >= '1995-01-01' AND O_ORDERDATE < '1996-01-01'
GROUP BY O_ORDERSTATUS
ORDER BY O_ORDERSTATUS;
-- Debes ver en el ejemplo: 3 filas: F 475422, O 1416801, P 383352.
--
--   Columnas de salida (en este orden): REGION, PEDIDOS, MONTO_TOTAL

CREATE OR REPLACE VIEW Q1 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM Q1;  -- mira tu resultado

-- ✅ Debes ver: 5 filas: ASIA 456009 y 68967100592.50; EUROPE 455641 y 68799982358.42; AFRICA 454932 y 68762858194.19; AMERICA 454468 y 68654772243.31; MIDDLE EAST 454525 y 68586549319.07


-- =====================================================================
-- Q2 · ¿Qué naciones superan 600 000 pedidos?  (después de clase)
-- =====================================================================
-- Pregunta de negocio: ¿qué naciones superan 600 000 pedidos?
-- Pedidos por nación del cliente (ORDERS > CUSTOMER > NATION), sin filtro de fecha; monto =
-- SUM(O_TOTALPRICE). Solo naciones con más de 600000 pedidos.
-- Ordena por PEDIDOS de mayor a menor y por NACION.
--
-- DEFINICIÓN:
--   La condición sobre un conteo por grupo va en HAVING; WHERE no puede usar COUNT(*).
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter; otra tabla que la tuya):
SELECT C.C_MKTSEGMENT, COUNT(*) AS PEDIDOS
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS O JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.CUSTOMER C ON O.O_CUSTKEY = C.C_CUSTKEY
GROUP BY C.C_MKTSEGMENT
HAVING COUNT(*) > 3000000
ORDER BY C.C_MKTSEGMENT;
-- Debes ver en el ejemplo: 4 filas: AUTOMOBILE 3000540, BUILDING 3004382, FURNITURE 3001268, MACHINERY 3002982 (HOUSEHOLD, con 2990828, queda fuera).
--
--   Columnas de salida (en este orden): NACION, PEDIDOS, MONTO_TOTAL

CREATE OR REPLACE VIEW Q2 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM Q2;  -- mira tu resultado

-- ✅ Debes ver: 13 filas, de ETHIOPIA 605659 y 91522998800.14 a VIETNAM 600059 y 90644727428.25


-- =====================================================================
-- Q3 · ¿Cuántos clientes de cada región nunca hicieron un pedido?  (después de clase)
-- =====================================================================
-- Pregunta de negocio: ¿cuántos clientes de cada región nunca hicieron un pedido?
-- Clientes (CUSTOMER) sin ninguna fila en ORDERS, por región (CUSTOMER > NATION > REGION).
-- Ordena por CLIENTES_SIN_PEDIDOS de mayor a menor y por REGION.
--
-- DEFINICIÓN:
--   LEFT JOIN desde CUSTOMER hacia ORDERS y filtro IS NULL sobre la clave de ORDERS. Con INNER JOIN
--   los clientes sin pedidos desaparecen y el resultado queda vacío.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter; otra tabla que la tuya):
SELECT COUNT(*) AS CLIENTES_NACION_0_SIN_PEDIDOS
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.CUSTOMER C LEFT JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS O ON C.C_CUSTKEY = O.O_CUSTKEY
WHERE C.C_NATIONKEY = 0 AND O.O_ORDERKEY IS NULL;
-- Debes ver en el ejemplo: 1 fila: 20022.
--
--   Columnas de salida (en este orden): REGION, CLIENTES_SIN_PEDIDOS

CREATE OR REPLACE VIEW Q3 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM Q3;  -- mira tu resultado

-- ✅ Debes ver: 5 filas: EUROPE 100392, MIDDLE EAST 100109, ASIA 100003, AFRICA 99758, AMERICA 99756


-- =====================================================================
-- Q4 · ¿Qué modo de envío mueve más importe en cada región?  (en clase)
-- =====================================================================
-- Pregunta de negocio: ¿qué modo de envío mueve más importe en cada región?
-- Todas las combinaciones región x modo de envío (no se pide el máximo por región: eso requiere
-- funciones de ventana, clase 3; aquí se ordena y se lee). Une LINEITEM > ORDERS > CUSTOMER >
-- NATION > REGION. LINEAS = COUNT(*), IMPORTE_LINEAS = SUM(L_EXTENDEDPRICE) (importe de las líneas).
-- Ordena por REGION, IMPORTE_LINEAS de mayor a menor y MODO_ENVIO (L_SHIPMODE).
--
-- DEFINICIÓN:
--   Cinco tablas y la tabla más grande del esquema: LINEITEM tiene 59 986 052 filas en SF10. Es la
--   consulta que se perfila al final. El importe sale de las líneas (L_EXTENDEDPRICE), no de
--   O_TOTALPRICE: sumar la columna del pedido después de unir con LINEITEM repite el total de
--   cada pedido una vez por línea (el error del EJ7 del Lab 2).
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter; otra tabla que la tuya):
SELECT R.R_NAME, COUNT(*) AS CLIENTES
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.CUSTOMER C JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.NATION N ON C.C_NATIONKEY = N.N_NATIONKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.REGION R ON N.N_REGIONKEY = R.R_REGIONKEY
GROUP BY R.R_NAME
ORDER BY R.R_NAME;
-- Debes ver en el ejemplo: 5 filas, una por región.
--
--   Columnas de salida (en este orden): REGION, MODO_ENVIO, LINEAS, IMPORTE_LINEAS

CREATE OR REPLACE VIEW Q4 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM Q4;  -- mira tu resultado

-- ✅ Debes ver: 35 filas (5 regiones x 7 modos de envío), ordenadas por región y, dentro de cada región, por IMPORTE_LINEAS de mayor a menor


-- =====================================================================
-- LECTURA DEL PERFIL DE LA CONSULTA MÁS PESADA (Q4) · no se verifica
-- =====================================================================
-- QUÉ HACER
--   1. Corre la línea de abajo. La caché de resultados está desactivada (Paso 0), así que la
--      consulta se ejecuta de verdad y genera su Query Profile.
--   2. Abre el Query Profile: en el panel de resultados, Query Details > botón de tres puntos >
--      View Query Profile; o Monitoring > Query History > consulta > pestaña Query Profile.
--   3. Selecciona el nodo TableScan de LINEITEM y anota lo que muestra el panel Statistics.
SELECT * FROM Q4;
--
-- ANOTA (en este archivo, no se verifica):
--   (1) Bytes leídos por el TableScan de LINEITEM:                  ______________
--   (2) Micro-particiones leídas / totales de ese TableScan:         ______ / ______
--   (3) Operador con mayor % del tiempo, y ese porcentaje:           ______________
--       Percentage scanned from cache del TableScan de LINEITEM:      ______________
--   (4) Una propuesta para que Q4 lea menos, citando uno de los tres datos anteriores:
--       ______________________________________________________________________
--
-- CÓMO LEER LO QUE ANOTASTE
--   Si repites Q4 (misma sesión, caché de resultados apagada), el porcentaje del TableScan baja
--   porque el dato pasa a venir del caché del warehouse (estadística "Percentage scanned from
--   cache"): el operador dominante cambia, y por eso conviene citar el porcentaje que ves y si
--   el dato venía del caché.
--   Si (2) muestra todas las micro-particiones (116 de 116), el TableScan no podó nada: Q4 no
--   tiene filtro, y aunque lo tuviera, un filtro sobre L_SHIPDATE tampoco podaría en SF10
--   (116 de 116). La propuesta concreta: filtrar por L_ORDERKEY, la columna por la que LINEITEM
--   está agrupada en SF10, para que el TableScan lea menos micro-particiones (medido: con
--   WHERE L.L_ORDERKEY < 6000000 el TableScan lee 19 de 116). Otras salidas:
--   leer menos columnas o agregar antes de unir (clase 3).
--   Para decidir qué hacer según lo que muestra el perfil, usa la tabla de la slide 50 (bloque 47 a 54):
--   particiones leídas = totales, muchos bytes en TableScan, Join que entrega más filas que su
--   entrada mayor, Join o Aggregate dominantes, bytes spilled y Sort dominante apuntan cada uno a una
--   decisión distinta, y no todos se resuelven con un warehouse más grande.
--   Costo de la corrida: créditos = segundos x créditos por hora / 3600 (X-Small = 1 crédito/h).
--   Para releer el perfil de una consulta ya ejecutada: ALTER SESSION SET USE_CACHED_RESULT = FALSE;


-- =====================================================================
-- PASO FINAL · Corre la verificación
-- =====================================================================
-- 1. Copia caso_verificacion.sql igual que este archivo, abre OTRA hoja y pulsa Run All.
-- 2. Una fila por vista: OK, REVISAR (lee la PISTA y compara TUS_COLUMNAS con COLUMNAS_ESPERADAS)
--    o PENDIENTE (la vista conserva el marcador SELECT NULL AS PENDIENTE).
-- 3. META: RESUMEN = OK y "4 de 4". Q1 y Q4 se esperan al terminar la clase; Q2 y Q3 pueden
--    quedar PENDIENTE hasta que las resuelvas después.


-- =====================================================================
-- QUÉ APRENDISTE
-- =====================================================================
-- - Una pregunta de negocio se traduce en grano (qué es una fila), filtros, uniones y medida.
-- - El mismo patrón sirve a escala: de TPC-H SF1 (6 M líneas) a SF10 (60 M) cambia el tiempo, no el SQL.
-- - Un TableScan que lee todas las micro-particiones indica que ningún filtro podó; la decisión
--   depende de la columna de agrupación (L_ORDERKEY poda en SF10; L_SHIPDATE no).
-- - La medida correcta de Q4 sale de las líneas: sumar O_TOTALPRICE tras unir con LINEITEM la
--   repite una vez por línea.


-- =====================================================================
-- ERRORES COMUNES
-- =====================================================================
-- Mensaje o síntoma                             | Causa                          | Cómo evitarlo
-- ---------------------------------------------|--------------------------------|---------------------------
-- Q3 devuelve 0 filas                          | INNER JOIN con ORDERS: descarta| LEFT JOIN y filtro
--                                              | clientes sin pedidos           | O.O_ORDERKEY IS NULL
-- Q2 devuelve las 25 naciones                 | Umbral mal escrito (60000 en   | Escribe 600000 (seis ceros)
--                                              | lugar de 600000)               | y usa HAVING con COUNT(*)
-- Invalid aggregate function in where clause   | COUNT(*) en WHERE              | Muévelo a HAVING
-- Missing column specification                 | Columna calculada sin AS       | AS NOMBRE en cada una
-- Q4 con importes cinco veces mayores y sin    | SUM(O_TOTALPRICE) tras unir    | Suma L_EXTENDEDPRICE
--   error                                      | con LINEITEM: se repite por    |
--                                              | línea                          |
-- Q4 devuelve muchísimas filas o no termina    | JOIN sin ON: producto          | ON tabla1.clave = tabla2.clave
--                                              | cartesiano                     |
-- Q4 tarda más en la primera corrida          | Warehouse suspendido y sin     | Es esperado: la segunda
--                                              | datos en su caché              | corrida lee del caché
-- This session does not have a current         | No se corrió el Paso 0 en esa  | Selecciona de USE ROLE a
--   database, o el esquema no existe           | hoja                           | ALTER SESSION ...; y pulsa ▶
-- REVISAR con columnas distintas               | El alias de salida no coincide | Compara TUS_COLUMNAS con
--                                              | (REGION, NACION, MODO_ENVIO...)| COLUMNAS_ESPERADAS
