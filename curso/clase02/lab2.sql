-- =====================================================================
-- LAB 2 · Agregaciones y JOIN sobre TPC-H (Big Data UdeM · Clase 2)
-- =====================================================================
--
-- OBJETIVO
--   Agregar con GROUP BY, HAVING y funciones (COUNT, SUM, AVG, MIN, MAX, ROUND), combinar tablas
--   con INNER JOIN y LEFT JOIN, y detectar el error silencioso más común: el JOIN que duplica
--   filas y infla un total sin producir ningún mensaje de error.
--
-- GLOSARIO (solo lo nuevo respecto del Lab 1)
--   grupo        filas que comparten el valor de la columna de GROUP BY.
--   agregación   función que resume un grupo en un valor: COUNT, SUM, AVG, MIN, MAX.
--   HAVING       filtra grupos después de agregar (WHERE filtra filas antes de agrupar).
--   JOIN         combina filas de dos tablas cuando se cumple la condición ON.
--   alias de tabla  nombre corto para una tabla dentro de la consulta (C, O, L, N, R).
--   NULL         valor ausente. No es 0 ni texto vacío: se compara con IS NULL.
--   cardinalidad cuántas filas de una tabla corresponden a una fila de otra (1 pedido : n líneas).
--
-- CÓMO COPIAR ESTE ARCHIVO A SNOWSIGHT (solo navegador, sin terminal)
--   1. En tu fork: carpeta curso > clase02 > lab2.sql.
--   2. Arriba a la derecha del contenido, el ícono de dos cuadritos es "Copy raw file"
--      (no el de la flecha hacia abajo).
--   3. En Snowsight: Projects > Worksheets > botón + (SQL Worksheet). Si tu Snowsight muestra
--      "Workspaces", usa + > SQL File.
--   4. Pega todo (Ctrl/Cmd + V). No elijas rol ni warehouse: el Paso 0 los fija.
--   5. Si no ves el archivo: botón "Sync fork" > "Update branch".
--
-- CÓMO CORRER
--   Paso 0: selecciona de USE ROLE a USE SCHEMA CURSO.LAB2; y pulsa ▶.
--   Ejercicios: bloque a bloque con Cmd/Ctrl+Enter (corre la consulta donde está el cursor).
--   Run All corre todo el archivo: en este archivo NO lo uses.
--
-- TIEMPO: 24 min en clase. Orden: EJ1 a EJ6 (★, núcleo), luego EJ7 y EJ8 (★★) juntos
--   (error y corrección). EJ9 (★★) y EJ10 (★★★) son opcionales.
--
-- NIVELES
--   ★    núcleo: seis ejercicios; la verificación exige los seis
--   ★★   si queda tiempo
--   ★★★  reto
--
-- DICCIONARIO RÁPIDO (TPC-H, factor de escala 1: 1 500 000 pedidos, 6 001 215 líneas)
--   CUSTOMER  C_CUSTKEY, C_NAME, C_NATIONKEY, C_ACCTBAL, C_MKTSEGMENT
--   ORDERS    O_ORDERKEY, O_CUSTKEY, O_ORDERSTATUS, O_TOTALPRICE, O_ORDERDATE, O_ORDERPRIORITY
--   LINEITEM  L_ORDERKEY, L_QUANTITY, L_EXTENDEDPRICE, L_DISCOUNT, L_TAX, L_SHIPDATE, L_SHIPMODE
--   NATION    N_NATIONKEY, N_NAME, N_REGIONKEY
--   REGION    R_REGIONKEY, R_NAME
--   Las tablas viven en SNOWFLAKE_SAMPLE_DATA.TPCH_SF1 (solo lectura). Escribe siempre la ruta
--   completa, por ejemplo SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER.
--
-- RELEER UN PERFIL YA EJECUTADO
--   Snowflake responde una consulta repetida desde la caché de resultados y no genera un perfil
--   nuevo. Para ver el perfil de una consulta que ya corriste, desactiva la caché en la sesión:
--     ALTER SESSION SET USE_CACHED_RESULT = FALSE;
--
-- =====================================================================
-- CÓMO ESCRIBIR CADA EJERCICIO (la misma plantilla en los 10)
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
--     SELECT R_NAME, COUNT(*) AS NACIONES
--     FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION N JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION R
--       ON N.N_REGIONKEY = R.R_REGIONKEY
--     GROUP BY R_NAME
--     -- ▲▲ hasta aquí ▲▲
--     ;
--     SELECT * FROM EJ1;  -- mira tu resultado
--
-- Ejecuta los dos bloques con Cmd/Ctrl+Enter. Debes ver "View EJ1 successfully created" y luego tu
-- resultado. Si ves un mensaje rojo, el CREATE falló: lee el mensaje y consulta la tabla de
-- errores comunes al final. Los nombres de las columnas de salida son parte del ejercicio y deben
-- coincidir (mayúsculas o minúsculas no importan). Cada columna calculada (COUNT, SUM, AVG...)
-- necesita AS NOMBRE; si no, la vista falla con "Missing column specification".
--
-- Cada ejercicio es una vista: una consulta guardada con nombre. La vista no guarda datos, guarda
-- la consulta; por eso la verificación puede leer EJ1, EJ2... sin preguntarte nada.
-- =====================================================================


-- =====================================================================
-- PASO 0 · PREPARACIÓN (ya resuelto: no lo cambies)
-- QUÉ HACER: selecciona con el mouse desde USE ROLE hasta USE SCHEMA CURSO.LAB2; y pulsa ▶.
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

-- TU BASE DE TRABAJO: CURSO es la base de datos y LAB2 el esquema donde se guardan tus vistas.
CREATE DATABASE IF NOT EXISTS CURSO;
CREATE SCHEMA IF NOT EXISTS CURSO.LAB2;
USE SCHEMA CURSO.LAB2;


-- =====================================================================
-- TABLAS: así luce una tabla (corre esta línea después del Paso 0)
-- =====================================================================
SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION LIMIT 5;
--
-- Reglas de todo el lab: números sin comas (60000), texto entre comillas simples y en
-- mayúsculas exactas ('1-URGENT'), fechas entre comillas ('1995-01-01').


-- =====================================================================
-- EJERCICIO 1 ★ · GROUP BY y COUNT(*)
-- =====================================================================
-- DEFINICIÓN:
--   GROUP BY columna forma un grupo por cada valor distinto de la columna.
--   COUNT(*) cuenta las filas de cada grupo. Toda columna del SELECT que no
--   sea una agregación debe estar en el GROUP BY.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT L_SHIPMODE, COUNT(*) AS LINEAS
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM
GROUP BY L_SHIPMODE
ORDER BY L_SHIPMODE;
-- Debes ver en el ejemplo: 7 filas: AIR 858104, FOB 857324, MAIL 857401, RAIL 856484, REG AIR 856868, SHIP 858036, TRUCK 856998.
--
-- TU TURNO:
--   De ORDERS cuenta los pedidos por estado (O_ORDERSTATUS).
--   Ordena por O_ORDERSTATUS.
--   Columnas de salida (en este orden): O_ORDERSTATUS, PEDIDOS

CREATE OR REPLACE VIEW EJ1 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ1;  -- mira tu resultado

-- ✅ Debes ver: 3 filas: F 729413, O 732044, P 38543. Columnas O_ORDERSTATUS, PEDIDOS


-- =====================================================================
-- EJERCICIO 2 ★ · WHERE, GROUP BY y SUM
-- =====================================================================
-- DEFINICIÓN:
--   WHERE filtra filas antes de agrupar. SUM(columna) suma la columna dentro de cada
--   grupo. Un año completo se filtra con >= inicio y < inicio del año siguiente.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT L_RETURNFLAG, SUM(L_QUANTITY) AS CANTIDAD
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM
WHERE L_SHIPDATE >= '1995-01-01' AND L_SHIPDATE < '1996-01-01'
GROUP BY L_RETURNFLAG
ORDER BY L_RETURNFLAG;
-- Debes ver en el ejemplo: 3 filas: A 4879553, N 13569211, R 4895107.
--
-- TU TURNO:
--   De ORDERS, solo los pedidos de 1995 (O_ORDERDATE >= '1995-01-01' y < '1996-01-01'),
--   por O_ORDERPRIORITY: cuántos pedidos y la suma de O_TOTALPRICE.
--   Ordena por O_ORDERPRIORITY.
--   Columnas de salida (en este orden): O_ORDERPRIORITY, PEDIDOS, MONTO_TOTAL

CREATE OR REPLACE VIEW EJ2 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ2;  -- mira tu resultado

-- ✅ Debes ver: 5 filas; la primera, 1-URGENT: PEDIDOS 45445 y MONTO_TOTAL 6858584755.04


-- =====================================================================
-- EJERCICIO 3 ★ · HAVING
-- =====================================================================
-- DEFINICIÓN:
--   HAVING filtra grupos después de agregar; WHERE no puede usar COUNT, SUM ni AVG
--   porque las agregaciones aún no existen cuando WHERE se evalúa.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT C_NATIONKEY, COUNT(*) AS CLIENTES
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER
GROUP BY C_NATIONKEY
HAVING COUNT(*) > 6100
ORDER BY C_NATIONKEY;
-- Debes ver en el ejemplo: 1 fila: C_NATIONKEY 9 con 6161 clientes.
--
-- TU TURNO:
--   De ORDERS, clientes (agrupa por O_CUSTKEY) con 39 o más pedidos.
--   Ordena por PEDIDOS de mayor a menor y, si empatan, por O_CUSTKEY. Sin LIMIT.
--   Columnas de salida (en este orden): O_CUSTKEY, PEDIDOS

CREATE OR REPLACE VIEW EJ3 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ3;  -- mira tu resultado

-- ✅ Debes ver: 8 filas: 3451 (41), 102004 (41), 102022 (41), 79300 (40), 117082 (40), 122623 (40), 69682 (39), 143500 (39)


-- =====================================================================
-- EJERCICIO 4 ★ · AVG, MAX y ROUND
-- =====================================================================
-- DEFINICIÓN:
--   AVG promedia, MAX y MIN toman el extremo del grupo. ROUND(valor, 2) redondea a
--   2 decimales; AVG devuelve más decimales de los que conviene comparar.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT O_ORDERSTATUS, MIN(O_TOTALPRICE) AS PRECIO_MIN, MAX(O_TOTALPRICE) AS PRECIO_MAX
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
GROUP BY O_ORDERSTATUS
ORDER BY O_ORDERSTATUS;
-- Debes ver en el ejemplo: 3 filas: F 866.90 y 555285.16; O 857.71 y 530604.44; P 2933.43 y 491549.57.
--
-- TU TURNO:
--   De CUSTOMER, por segmento (C_MKTSEGMENT): cuántos clientes, el saldo promedio
--   (C_ACCTBAL) redondeado a 2 decimales y el saldo máximo. Ordena por C_MKTSEGMENT.
--   Columnas de salida (en este orden): C_MKTSEGMENT, CLIENTES, SALDO_PROMEDIO, SALDO_MAXIMO

CREATE OR REPLACE VIEW EJ4 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ4;  -- mira tu resultado

-- ✅ Debes ver: 5 filas; la primera, AUTOMOBILE: 29752 clientes, 4499.42 y 9999.96


-- =====================================================================
-- EJERCICIO 5 ★ · INNER JOIN
-- =====================================================================
-- DEFINICIÓN:
--   JOIN combina filas de dos tablas cuando se cumple la condición ON. INNER JOIN deja solo
--   las filas con pareja en ambas tablas. Cada tabla lleva un alias (C, N) y cada columna
--   se escribe con su alias cuando hay JOIN. Sin ON el resultado es un producto cartesiano.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT N.N_NAME, R.R_NAME
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION N JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION R ON N.N_REGIONKEY = R.R_REGIONKEY
ORDER BY N.N_NATIONKEY
LIMIT 3;
-- Debes ver en el ejemplo: 3 filas: ALGERIA AFRICA, ARGENTINA AMERICA, BRAZIL AMERICA.
--
-- TU TURNO:
--   Une CUSTOMER (alias C) con NATION (alias N) por C_NATIONKEY = N_NATIONKEY. Muestra
--   C_CUSTKEY, C_NAME y N_NAME de los 5 primeros clientes por C_CUSTKEY.
--   Columnas de salida (en este orden): C_CUSTKEY, C_NAME, N_NAME

CREATE OR REPLACE VIEW EJ5 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ5;  -- mira tu resultado

-- ✅ Debes ver: 5 filas; el cliente 1 es de MOROCCO. Columnas C_CUSTKEY, C_NAME, N_NAME


-- =====================================================================
-- EJERCICIO 6 ★ · JOIN y GROUP BY
-- =====================================================================
-- DEFINICIÓN:
--   Se unen las tablas primero y se agrupa después: GROUP BY opera sobre las filas que
--   produce el JOIN. La cardinalidad (cuántas filas de una tabla corresponden a una fila
--   de la otra) decide si el conteo se mantiene o se infla.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT R.R_NAME, COUNT(*) AS NACIONES
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION N JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION R ON N.N_REGIONKEY = R.R_REGIONKEY
GROUP BY R.R_NAME
ORDER BY R.R_NAME;
-- Debes ver en el ejemplo: 5 filas, 5 naciones por región (AFRICA, AMERICA, ASIA, EUROPE, MIDDLE EAST).
--
-- TU TURNO:
--   Cuenta los clientes por nación (N_NAME) uniendo CUSTOMER con NATION.
--   Ordena por CLIENTES de mayor a menor y por N_NAME. LIMIT 5.
--   Columnas de salida (en este orden): N_NAME, CLIENTES

CREATE OR REPLACE VIEW EJ6 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ6;  -- mira tu resultado

-- ✅ Debes ver: 5 filas: INDONESIA 6161, FRANCE 6100, ROMANIA 6100, RUSSIA 6078, INDIA 6042


-- =====================================================================
-- EJERCICIO 7 ★★ · El JOIN que duplica
-- =====================================================================
-- DEFINICIÓN:
--   Un JOIN de uno a muchos repite la fila del lado "uno" una vez por cada pareja. Un pedido
--   (ORDERS) tiene varias líneas (LINEITEM): si sumas O_TOTALPRICE después de unir, el total
--   del pedido se suma una vez por línea. No hay error; el resultado es otro número.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT COUNT(*) AS FILAS_JOIN
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM L ON O.O_ORDERKEY = L.L_ORDERKEY;
-- Debes ver en el ejemplo: 6001215 filas, contra 1500000 de ORDERS.
--
-- TU TURNO:
--   Une ORDERS (O) con LINEITEM (L) por O_ORDERKEY = L_ORDERKEY, solo pedidos de 1995, por
--   O_ORDERPRIORITY: cuántas filas produce el JOIN (FILAS_JOIN) y SUM(O_TOTALPRICE)
--   (MONTO_INFLADO). Ordena por O_ORDERPRIORITY. Compara con el EJ2.
--   Pregunta: ¿por qué FILAS_JOIN es 4 veces PEDIDOS del EJ2 y MONTO_INFLADO casi 5 veces
--   MONTO_TOTAL? (Pista: los pedidos grandes tienen más líneas.)
--   Columnas de salida (en este orden): O_ORDERPRIORITY, FILAS_JOIN, MONTO_INFLADO

CREATE OR REPLACE VIEW EJ7 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ7;  -- mira tu resultado

-- ✅ Debes ver: 5 filas; 1-URGENT: FILAS_JOIN 181290 y MONTO_INFLADO 34218904136.19 (el EJ2 da 45445 y 6858584755.04)


-- =====================================================================
-- EJERCICIO 8 ★★ · Corrección: contar sin repetir y elegir la medida
-- =====================================================================
-- DEFINICIÓN:
--   Con el mismo JOIN hay dos remedios: contar con COUNT(DISTINCT clave) y sumar una medida
--   del lado de las líneas en lugar de la del pedido. SUM(L_EXTENDEDPRICE) es el precio de
--   lista (sin descuento ni impuesto); L_EXTENDEDPRICE*(1-L_DISCOUNT)*(1+L_TAX) es el importe
--   neto con descuento e impuesto, y equivale a O_TOTALPRICE salvo 0.00002 %.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT COUNT(DISTINCT O.O_ORDERKEY) AS PEDIDOS
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM L ON O.O_ORDERKEY = L.L_ORDERKEY;
-- Debes ver en el ejemplo: 1500000, igual que COUNT(*) de ORDERS.
--
-- TU TURNO:
--   Mismo JOIN y mismo filtro de 1995 del EJ7, por O_ORDERPRIORITY: pedidos sin repetir
--   (COUNT DISTINCT de O_ORDERKEY) e importe de las líneas con la medida
--   L_EXTENDEDPRICE*(1-L_DISCOUNT)*(1+L_TAX), SUM redondeado a 2 decimales. PEDIDOS debe
--   coincidir con el EJ2 y el importe con su MONTO_TOTAL. Ordena por O_ORDERPRIORITY.
--   Pregunta: ¿por qué SUM(L_EXTENDEDPRICE) da 1.21 % más que SUM(O_TOTALPRICE) y la
--   expresión con descuento e impuesto no? (El precio de lista no descuenta ni grava.)
--   Columnas de salida (en este orden): O_ORDERPRIORITY, PEDIDOS, IMPORTE_LINEAS

CREATE OR REPLACE VIEW EJ8 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ8;  -- mira tu resultado

-- ✅ Debes ver: 5 filas; 1-URGENT: PEDIDOS 45445 e IMPORTE_LINEAS 6858586305.44 (MONTO_TOTAL del EJ2: 6858584755.04; diferencia de 0.00002 %)


-- =====================================================================
-- EJERCICIO 9 ★★ · LEFT JOIN e IS NULL
-- =====================================================================
-- DEFINICIÓN:
--   LEFT JOIN conserva todas las filas de la tabla izquierda; si no hay pareja, las
--   columnas de la derecha quedan en NULL (valor ausente). Filtrar con IS NULL sobre una
--   columna de la tabla derecha deja solo las filas sin pareja. Un INNER JOIN las descarta.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT COUNT(*) AS SIN_PEDIDOS_NACION_0
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER C LEFT JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O ON C.C_CUSTKEY = O.O_CUSTKEY
WHERE C.C_NATIONKEY = 0 AND O.O_ORDERKEY IS NULL;
-- Debes ver en el ejemplo: 1 fila: 1985 clientes de la nación 0 sin pedidos.
--
-- TU TURNO:
--   Cuenta los clientes que no tienen ningún pedido, por segmento (C_MKTSEGMENT).
--   Ordena por C_MKTSEGMENT.
--   Columnas de salida (en este orden): C_MKTSEGMENT, CLIENTES_SIN_PEDIDOS

CREATE OR REPLACE VIEW EJ9 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ9;  -- mira tu resultado

-- ✅ Debes ver: 5 filas; la suma es 50004: AUTOMOBILE 9876, BUILDING 9965, FURNITURE 10002, HOUSEHOLD 10161, MACHINERY 10000


-- =====================================================================
-- EJERCICIO 10 ★★★ · Tres tablas, LEFT JOIN y HAVING
-- =====================================================================
-- DEFINICIÓN:
--   Con tres tablas se encadenan los JOIN, cada uno con su ON. Con LEFT JOIN a ORDERS,
--   COUNT(*) cuenta una fila por cliente sin pedidos; COUNT(O.O_ORDERKEY) no cuenta los NULL.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT R.R_NAME, COUNT(*) AS CLIENTES
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER C JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION N ON C.C_NATIONKEY = N.N_NATIONKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION R ON N.N_REGIONKEY = R.R_REGIONKEY
GROUP BY R.R_NAME
ORDER BY R.R_NAME;
-- Debes ver en el ejemplo: 5 filas: AFRICA 29764, AMERICA 29952, ASIA 30183, EUROPE 30197, MIDDLE EAST 29904.
--
-- TU TURNO:
--   Por nación (NATION, CUSTOMER y, con LEFT JOIN, ORDERS): clientes distintos
--   (COUNT DISTINCT de C_CUSTKEY) y pedidos (COUNT sobre O_ORDERKEY, no COUNT(*)).
--   Solo naciones con más de 60000 pedidos. Ordena por PEDIDOS de mayor a menor y N_NAME.
--   Sin LIMIT. Pregunta: ¿cuánto daría COUNT(*) en lugar de COUNT(O.O_ORDERKEY)? (FRANCE:
--   63551 filas contra 61600 pedidos, porque cada cliente sin pedidos cuenta como una fila.)
--   Columnas de salida (en este orden): N_NAME, CLIENTES, PEDIDOS

CREATE OR REPLACE VIEW EJ10 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ10;  -- mira tu resultado

-- ✅ Debes ver: 10 filas: FRANCE 6100 61600, RUSSIA 6078 61495, INDONESIA 6161 61377, MOZAMBIQUE 5974 61267, ROMANIA 6100 61012, CHINA 6024 60784, JORDAN 6033 60736, CANADA 6020 60480, VIETNAM 6008 60347, BRAZIL 5999 60137


-- =====================================================================
-- PASO FINAL · Corre la verificación
-- =====================================================================
-- 1. Copia lab2_verificacion.sql igual que copiaste este archivo.
-- 2. En Snowsight abre OTRA hoja nueva (+ SQL Worksheet o + > SQL File), pega todo y pulsa Run All.
-- 3. Busca la tabla final: EJERCICIO, NIVEL, RESULTADO, PISTA.
--
-- Una fila por ejercicio:
--   OK         = correcto.
--   REVISAR    = la vista existe pero no coincide. Lee la PISTA y compara TUS_COLUMNAS con
--                COLUMNAS_ESPERADAS.
--   PENDIENTE  = la vista todavía tiene el marcador SELECT NULL AS PENDIENTE.
-- La última fila es el resumen: cuántos de los 6 ★ están en OK. META: RESUMEN = OK y "6 de 6".
-- PENDIENTE en EJ7 a EJ10 es normal si no llegaste a los ★★. Si dice PENDIENTE pero escribiste tu
-- SELECT, el CREATE falló: busca el mensaje rojo.


-- =====================================================================
-- QUÉ APRENDISTE
-- =====================================================================
-- - GROUP BY forma grupos; COUNT, SUM, AVG, MIN y MAX los resumen. Toda columna no agregada va
--   en el GROUP BY.
-- - WHERE filtra filas antes de agrupar; HAVING filtra grupos después de agregar.
-- - INNER JOIN descarta filas sin pareja; LEFT JOIN las conserva con NULL; sin ON hay producto
--   cartesiano (25 naciones x 5 regiones = 125 filas).
-- - Un JOIN de uno a muchos repite filas: FILAS_JOIN de EJ7 es 4 veces PEDIDOS y MONTO_INFLADO casi
--   5 veces MONTO_TOTAL, sin ningún error. Compara COUNT(*) antes y después de unir.
-- - Se corrige con COUNT(DISTINCT clave) y con una medida del lado correcto (la de las líneas).
-- - COUNT(*) cuenta filas; COUNT(columna) no cuenta los NULL.
--
-- Siguiente: el mini-caso (caso.sql) aplica estas piezas a TPC-H SF10 y termina con la lectura
-- del Query Profile.


-- =====================================================================
-- ERRORES COMUNES
-- =====================================================================
-- Mensaje o síntoma                             | Causa                          | Cómo evitarlo
-- ---------------------------------------------|--------------------------------|---------------------------
-- 'X' in select clause is neither an aggregate | Una columna del SELECT no está | Agrégala al GROUP BY o
--   nor in the group by clause                 | en GROUP BY ni agregada        | quítala del SELECT
-- Invalid aggregate function in where clause   | Agregación en WHERE: aún no    | Muévela a HAVING
--   [COUNT(*)]                                 | existe al evaluarlo            |
-- Missing column specification (al crear la    | COUNT, SUM o AVG sin AS        | Pon AS NOMBRE en cada
--   vista)                                     |                                | columna calculada
-- El total es mucho mayor que el del ejercicio | Un JOIN de uno a muchos        | Compara COUNT(*) antes y
--   anterior (EJ7) y no hay error              | repitió filas                  | después; usa COUNT(DISTINCT)
--                                              |                                | o suma del lado de las líneas
-- 125 filas al unir NATION con REGION (25 x 5) | JOIN sin ON: producto          | Escribe siempre
--   y no hay error                             | cartesiano                     | ON tabla1.clave = tabla2.clave
-- Faltan clientes en el resultado (EJ9)        | INNER JOIN descarta los que no | Usa LEFT JOIN y filtra con
--                                              | tienen pareja                  | IS NULL en la tabla derecha
-- This session does not have a current         | No se corrió el Paso 0 en esa  | Selecciona de USE ROLE a
--   database, o el esquema no existe           | hoja                           | USE SCHEMA CURSO.LAB2; y
--                                              |                                | pulsa ▶; escribe la ruta
--                                              |                                | completa de cada tabla
-- REVISAR con columnas distintas               | El alias de salida no coincide | Compara TUS_COLUMNAS con
--                                              |                                | COLUMNAS_ESPERADAS
