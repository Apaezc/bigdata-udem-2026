-- =====================================================================
-- LAB 1 · Tu primer SQL sobre TPC-H (Big Data UdeM · Clase 2)
-- =====================================================================
--
-- OBJETIVO
--   Escribir tus primeras consultas en SQL: SELECT, WHERE, ORDER BY,
--   LIMIT, COUNT(*) y SUM. Y mirar por primera vez el Query Profile
--   (el registro de cómo Snowflake ejecutó tu consulta, paso a paso).
--
-- GLOSARIO (6 palabras que verás en este archivo)
--   *fork*: tu copia personal del repositorio del curso, en tu cuenta de GitHub.
--   *raw*: el texto puro del archivo; "Copy raw file" copia solo el código.
--   rol: los permisos con los que trabajas en Snowflake (aquí, ACCOUNTADMIN).
--   *warehouse*: el motor que ejecuta tus consultas; cobra mientras está encendido.
--   base de datos / esquema: CURSO es la base de datos y LAB1 es un esquema dentro de ella.
--   vista: una consulta guardada con nombre. Cada ejercicio es una vista (EJ1, EJ2...).
--
-- CÓMO COPIAR ESTE ARCHIVO A SNOWSIGHT (solo navegador, sin terminal)
--   Snowsight es la interfaz web de Snowflake.
--   1. Entra a tu fork > carpeta curso > clase02 > lab1.sql.
--   2. Arriba a la derecha del contenido, el ícono de dos cuadritos es
--      "Copy raw file" (no el de la flecha hacia abajo).
--   3. En Snowsight: menú izquierdo Projects > Worksheets > botón + (SQL Worksheet).
--      Si tu Snowsight muestra "Workspaces", usa + > SQL File.
--   4. Pega todo (Ctrl/Cmd + V). No elijas rol ni warehouse en el selector:
--      el Paso 0 lo hace por ti.
--   5. Si no ves un archivo en tu fork: botón "Sync fork" > "Update branch".
--
-- CÓMO CORRER
--   Paso 0: selecciona y ▶. Ejercicios: bloque a bloque con Cmd/Ctrl+Enter.
--   Ctrl/Cmd + Enter corre solo la consulta donde está el cursor.
--   Run All corre todo el archivo: en este archivo NO lo uses.
--
-- TIEMPO: 33 min en clase.
--   Orden sugerido: ★ (6 ejercicios, núcleo) > ★★ si te sobra tiempo
--   > ★★★ reto. Al final corre la verificación (ver "PASO FINAL").
--
-- NIVELES
--   ★    núcleo: todos
--   ★★   si te sobra tiempo
--   ★★★  reto
--
-- DICCIONARIO RÁPIDO (datos de ejemplo TPC-H: un mayorista)
--   CUSTOMER  (clientes)  C_CUSTKEY, C_NAME, C_NATIONKEY, C_ACCTBAL, C_MKTSEGMENT
--   ORDERS    (pedidos)   O_ORDERKEY, O_CUSTKEY, O_ORDERSTATUS, O_TOTALPRICE,
--                         O_ORDERDATE, O_ORDERPRIORITY
--   NATION    (países)    N_NATIONKEY, N_NAME, N_REGIONKEY
--   REGION    (regiones)  R_REGIONKEY, R_NAME
--   Las tablas viven en SNOWFLAKE_SAMPLE_DATA.TPCH_SF1. Escribe siempre
--   la ruta completa, por ejemplo: SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER
--   (la base de ejemplo es de solo lectura: no puedes crear nada ahí).
--   Para ver cómo luce una tabla: mira la sección TABLAS, después del PASO 0.
--
-- =====================================================================
-- CÓMO ESCRIBIR CADA EJERCICIO (la MISMA plantilla en los 10)
-- =====================================================================
-- Cada ejercicio trae esta plantilla. Tú solo escribes en el lugar del
-- marcador (la línea SELECT NULL AS PENDIENTE):
--
--   CREATE OR REPLACE VIEW EJ1 AS
--   -- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
--   SELECT NULL AS PENDIENTE
--   -- ▲▲ hasta aquí ▲▲
--   ;
--   SELECT * FROM EJ1;  -- mira tu resultado
--
-- EJEMPLO ANTES / DESPUÉS (con un ejercicio de práctica, no se entrega)
--
--   ANTES (así llega el archivo):
--     CREATE OR REPLACE VIEW EJ1 AS
--     -- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
--     SELECT NULL AS PENDIENTE
--     -- ▲▲ hasta aquí ▲▲
--     ;
--     SELECT * FROM EJ1;  -- mira tu resultado
--
--   DESPUÉS (borras el marcador y escribes tu SELECT, sin ; antes del ;):
--     CREATE OR REPLACE VIEW EJ1 AS
--     -- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
--     SELECT R_REGIONKEY, R_NAME
--     FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION
--     ORDER BY R_REGIONKEY
--     LIMIT 2
--     -- ▲▲ hasta aquí ▲▲
--     ;
--     SELECT * FROM EJ1;  -- mira tu resultado
--
-- QUÉ HACER, PASO A PASO
--   1. Un "bloque" es todo lo que va desde CREATE hasta el ; de abajo.
--   2. Ejecuta los dos bloques con el cursor dentro de cada uno y Cmd/Ctrl+Enter.
--      Debes ver 'View EJ1 successfully created' y luego tu resultado.
--   3. Si ves un mensaje rojo, tu CREATE falló: léelo y corrige tu SELECT.
--   4. Al final de cada ejercicio hay una línea ✅ "Debes ver": compárala con
--      tu resultado (número de filas y nombres de columnas).
--
-- Los nombres de las columnas de salida son parte del ejercicio. Deben
-- coincidir exactamente (mayúsculas o minúsculas no importan).
-- =====================================================================


-- =====================================================================
-- PASO 0 · PREPARACIÓN (ya resuelto: no lo cambies)
-- =====================================================================
-- QUÉ HACER: selecciona con el mouse desde USE ROLE hasta USE SCHEMA
-- CURSO.LAB1; y pulsa ▶ (Run). No uses Run All en este archivo.
-- El Paso 0 elige el rol y el warehouse por ti.

-- ROL: los permisos con los que trabajas. ACCOUNTADMIN es el
-- administrador de tu cuenta de prueba: puede hacer todo.
USE ROLE ACCOUNTADMIN;

-- WAREHOUSE: el cómputo (CPU y memoria) que ejecuta tus consultas.
-- Se cobra por el tiempo encendido. Se apaga solo tras
-- 60 segundos sin uso (AUTO_SUSPEND = 60) y se prende solo al consultar.
CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH
  WAREHOUSE_SIZE = XSMALL
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;
-- Si COMPUTE_WH ya existía (trial), lo dejamos con apagado a los 60 s.
ALTER WAREHOUSE COMPUTE_WH SET AUTO_SUSPEND = 60 AUTO_RESUME = TRUE;

-- Ahora que el warehouse existe, lo usamos.
USE WAREHOUSE COMPUTE_WH;

-- BASE DE EJEMPLO: los datos TPC-H. Si ya existe, este comando no hace nada.
CREATE DATABASE IF NOT EXISTS SNOWFLAKE_SAMPLE_DATA FROM SHARE SFC_SAMPLES.SAMPLE_DATA;

-- TU BASE DE TRABAJO: CURSO es tu base de datos y LAB1 es tu esquema dentro de ella.
-- Aquí se guardan tus respuestas (las vistas) y nada se mezcla con los datos de ejemplo.
CREATE DATABASE IF NOT EXISTS CURSO;
CREATE SCHEMA IF NOT EXISTS CURSO.LAB1;
USE SCHEMA CURSO.LAB1;


-- =====================================================================
-- TABLAS: así luce una tabla (corre esta línea después del PASO 0)
-- =====================================================================
-- Pon el cursor en la línea y pulsa Cmd/Ctrl+Enter:
SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION LIMIT 5;
--
-- Reglas que verás en todo el lab:
--   · Números sin comas: 300000 (no 300,000).
--   · Texto entre comillas simples y en MAYÚSCULAS exactas: 'BUILDING', '1-URGENT'.


-- =====================================================================
-- ¿POR QUÉ CADA EJERCICIO ES UNA VISTA (view)?
-- =====================================================================
-- Cada vista tiene un nombre fijo (EJ1, EJ2, ...). La verificación
-- abre cada una por ese nombre y compara su resultado.
--
-- Una vista es una consulta guardada con nombre. No guarda datos: guarda
-- la consulta. Por eso cada ejercicio empieza con CREATE OR REPLACE VIEW.


-- =====================================================================
-- EJERCICIO 1 ★ · SELECT, ORDER BY y LIMIT
-- =====================================================================
-- SELECT elige las columnas de salida. ORDER BY ordena las filas por
-- una o más columnas. LIMIT devuelve como máximo N filas.
--
-- DEFINICIÓN:
--   SELECT columnas FROM tabla ORDER BY columna LIMIT n;
--   ORDER BY ordena de menor a mayor (ASC es lo normal).
--   ORDER BY columna DESC lo ordena de mayor a menor.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT R_REGIONKEY, R_NAME
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION
ORDER BY R_REGIONKEY
LIMIT 2;
--
-- TU TURNO:
--   De CUSTOMER muestra C_CUSTKEY, C_NAME y C_ACCTBAL. Ordena por
--   C_CUSTKEY de menor a mayor y deja solo 5 filas.
--   Columnas de salida (en este orden): C_CUSTKEY, C_NAME, C_ACCTBAL

CREATE OR REPLACE VIEW EJ1 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ1;  -- mira tu resultado

-- ✅ Debes ver: 5 filas, columnas C_CUSTKEY, C_NAME, C_ACCTBAL


-- =====================================================================
-- PRÁCTICA ANTES DE EJ2 · AS para nombrar columnas
-- =====================================================================
-- AS asigna un alias (nombre) a una columna de salida.
--
-- DEFINICIÓN:
--   SELECT columna AS NOMBRE  -> la columna de salida se llama NOMBRE.
--   Sin AS, la columna se llama como en la tabla (N_NAME).
--
--   OJO: en el ejercicio hay DOS AS distintos:
--     · CREATE OR REPLACE VIEW EJ1 AS  -> une el nombre de la vista con la
--       consulta que guarda. No es un nombre de columna.
--     · SELECT ... AS NOMBRE           -> pone nombre a una columna de salida.
--
--   ❌ Si olvidas el AS en un COUNT(*) o un SUM(...) dentro de la vista,
--   Snowflake responde en rojo:  "Missing column specification".
--   Significa: "esta columna no tiene nombre". Agrega AS NOMBRE y vuelve a correr.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT N_NAME AS NOMBRE_PAIS
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION
WHERE N_REGIONKEY = 1
ORDER BY N_NAME
LIMIT 3;


-- =====================================================================
-- EJERCICIO 2 ★ · WHERE y COUNT(*)
-- =====================================================================
-- WHERE conserva solo las filas que cumplen la condición.
-- COUNT(*) cuenta cuántas filas quedan.
--
-- DEFINICIÓN:
--   WHERE columna = 'valor' filtra filas. El texto va entre comillas
--   simples ('así').
--   COUNT(*) devuelve cuántas filas quedan.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT COUNT(*) AS TOTAL_ASIA
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION
WHERE N_REGIONKEY = 2;
--
-- TU TURNO:
--   ¿Cuántos clientes (CUSTOMER) están en el segmento de mercado
--   'BUILDING'? Usa la columna C_MKTSEGMENT.
--   Columna de salida: TOTAL_BUILDING (una sola fila).
--   La columna debe llamarse exactamente TOTAL_BUILDING: usa COUNT(*) AS TOTAL_BUILDING.

CREATE OR REPLACE VIEW EJ2 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ2;  -- mira tu resultado

-- ✅ Debes ver: 1 fila, columna TOTAL_BUILDING


-- =====================================================================
-- EJERCICIO 3 ★ · WHERE con dos condiciones (AND)
-- =====================================================================
-- AND exige que la fila cumpla las dos condiciones a la vez.
--
-- DEFINICIÓN:
--   WHERE condición1 AND condición2
--   Los números van sin comillas: O_TOTALPRICE > 300000.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT N_NATIONKEY, N_NAME
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION
WHERE N_REGIONKEY = 3 AND N_NATIONKEY > 10
ORDER BY N_NATIONKEY
LIMIT 3;
--
-- TU TURNO:
--   De ORDERS muestra O_ORDERKEY, O_ORDERSTATUS y O_TOTALPRICE de los
--   pedidos con O_ORDERSTATUS = 'F' Y O_TOTALPRICE mayor a 300000.
--   Ordena por O_ORDERKEY de menor a mayor y deja solo 5 filas.
--   Columnas de salida (en este orden): O_ORDERKEY, O_ORDERSTATUS, O_TOTALPRICE

CREATE OR REPLACE VIEW EJ3 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ3;  -- mira tu resultado

-- ✅ Debes ver: 5 filas, columnas O_ORDERKEY, O_ORDERSTATUS, O_TOTALPRICE


-- =====================================================================
-- EJERCICIO 4 ★ · Fechas en WHERE y COUNT(*)
-- =====================================================================
-- CONCEPTO: un periodo es un intervalo [inicio, fin): el inicio se
-- incluye y el fin se excluye.
--
-- DEFINICIÓN:
--   Las fechas van entre comillas: '1995-01-01'.
--   Para un año completo usa >= inicio y < inicio del año siguiente.
--   Usar < (y no <=) evita contar por error el 1 de enero siguiente.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT COUNT(*) AS PEDIDOS_1995_S1
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_ORDERDATE >= '1995-01-01' AND O_ORDERDATE < '1995-07-01';
--
-- TU TURNO:
--   ¿Cuántos pedidos (ORDERS) tienen O_ORDERDATE durante todo 1996?
--   Columna de salida: PEDIDOS_1996 (una sola fila).
--   La columna debe llamarse exactamente PEDIDOS_1996: usa COUNT(*) AS PEDIDOS_1996.

CREATE OR REPLACE VIEW EJ4 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ4;  -- mira tu resultado

-- ✅ Debes ver: 1 fila, columna PEDIDOS_1996


-- =====================================================================
-- EJERCICIO 5 ★ · SUM (sumar una columna)
-- =====================================================================
-- SUM es una función de agregación: reduce los valores de las filas
-- que pasan el WHERE a un solo número.
--
-- DEFINICIÓN:
--   SUM(columna) suma los valores de todas las filas que pasan el WHERE.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT SUM(C_ACCTBAL) AS SALDO_TOTAL
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER
WHERE C_NATIONKEY = 0;
--
-- TU TURNO:
--   Suma O_TOTALPRICE de los pedidos (ORDERS) con
--   O_ORDERPRIORITY = '1-URGENT'.
--   Columna de salida: TOTAL_URGENTE (una sola fila).
--   La columna debe llamarse exactamente TOTAL_URGENTE: usa SUM(...) AS TOTAL_URGENTE.

CREATE OR REPLACE VIEW EJ5 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ5;  -- mira tu resultado

-- ✅ Debes ver: 1 fila, columna TOTAL_URGENTE


-- =====================================================================
-- EJERCICIO 6 ★ · Query Profile (la parte del Query Profile NO se verifica)
-- =====================================================================
-- El Query Profile es el registro de ejecución de tu consulta: por cada
-- paso (operador) muestra cuántas filas leyó y pasó a la siguiente
-- etapa, y cuánto tiempo tomó. Así se ve por qué una consulta tarda o cuesta.
--
-- DEFINICIÓN:
--   Después de correr una consulta, abre su Query Profile:
--   1. Corre la consulta con Cmd/Ctrl+Enter.
--   2. Abre el Query Profile: en el panel de resultados, Query Details > botón de tres
--      puntos > View Query Profile; o Monitoring > Query History > consulta > pestaña
--      Query Profile.
--   3. Busca el nodo TableScan (la lectura de la tabla) de ORDERS. El número
--      de filas leídas está en "Statistics" o en la flecha que sale del nodo.
--   OJO: si repites la misma consulta, Snowflake la responde desde la caché
--   y no verás las filas leídas. Cambia algo (por ejemplo, el número del
--   filtro) y vuelve a correrla.
--
-- EJEMPLO RESUELTO (ejecútalo y abre su Query Profile):
SELECT COUNT(*) AS PEDIDOS_EJEMPLO
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_TOTALPRICE > 500000;
--
-- TU TURNO:
--   a) Escribe la vista: pedidos (ORDERS) con O_TOTALPRICE mayor a 400000,
--      contados con COUNT(*). Columna de salida: PEDIDOS_CAROS.
--      La columna debe llamarse exactamente PEDIDOS_CAROS: usa COUNT(*) AS PEDIDOS_CAROS.
--   b) Después de crear la vista, la línea SELECT * FROM EJ6; (de la plantilla)
--      te muestra el resultado. Abre su Query Profile.
--   c) ANOTA aquí cuántas filas leyó el nodo TableScan de ORDERS
--      (esto NO lo verifica el sistema; es para que lo mires):
--      FILAS LEÍDAS = ____________

CREATE OR REPLACE VIEW EJ6 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ6;  -- mira tu resultado

-- ✅ Debes ver: 1 fila, columna PEDIDOS_CAROS


-- =====================================================================
-- EJERCICIO 7 ★★ · ORDER BY con desempate
-- =====================================================================
-- Un desempate es una columna secundaria del ORDER BY: solo se usa
-- cuando dos filas empatan en la columna principal (p. ej., dos pedidos
-- con el mismo precio se ordenan por su número de pedido).
--
-- DEFINICIÓN:
--   ORDER BY columna1 DESC, columna2
--   Primero ordena por columna1 (de mayor a menor) y solo si hay empate
--   usa columna2 (de menor a mayor). Con LIMIT, el desempate hace que el
--   resultado siempre sea el mismo.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT N_NATIONKEY, N_REGIONKEY, N_NAME
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION
ORDER BY N_REGIONKEY DESC, N_NATIONKEY
LIMIT 4;
--
-- TU TURNO:
--   De ORDERS, los 5 pedidos más caros: O_ORDERKEY, O_CUSTKEY y
--   O_TOTALPRICE. Ordena por O_TOTALPRICE de mayor a menor y, si
--   empatan, por O_ORDERKEY de menor a mayor. LIMIT 5.
--   Columnas de salida (en este orden): O_ORDERKEY, O_CUSTKEY, O_TOTALPRICE

CREATE OR REPLACE VIEW EJ7 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ7;  -- mira tu resultado

-- ✅ Debes ver: 5 filas, columnas O_ORDERKEY, O_CUSTKEY, O_TOTALPRICE


-- =====================================================================
-- EJERCICIO 8 ★★ · IN y varias condiciones
-- =====================================================================
-- IN compara una columna contra una lista de valores. Equivale a varios
-- OR unidos, pero más corto.
--
-- DEFINICIÓN:
--   WHERE columna IN ('valor1', 'valor2')
--   Puedes combinarlo con AND, como en el ejercicio 3.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT R_REGIONKEY, R_NAME
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION
WHERE R_NAME IN ('ASIA', 'EUROPE')
ORDER BY R_REGIONKEY;
--
-- TU TURNO:
--   De CUSTOMER, clientes cuyo C_MKTSEGMENT sea 'MACHINERY' o
--   'FURNITURE' (usa IN) y cuyo C_ACCTBAL sea mayor a 9000.
--   Ordena por C_ACCTBAL de mayor a menor y luego por C_CUSTKEY.
--   LIMIT 10.
--   Columnas de salida (en este orden): C_CUSTKEY, C_NAME, C_MKTSEGMENT, C_ACCTBAL

CREATE OR REPLACE VIEW EJ8 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ8;  -- mira tu resultado

-- ✅ Debes ver: 10 filas, columnas C_CUSTKEY, C_NAME, C_MKTSEGMENT, C_ACCTBAL


-- =====================================================================
-- EJERCICIO 9 ★★ · Los más recientes primero (ORDER BY DESC con fechas)
-- =====================================================================
-- Con DESC el orden va de mayor a menor. Sobre una columna de fecha,
-- la fila más reciente queda primero.
--
-- DEFINICIÓN:
--   ORDER BY fecha DESC, columna_de_desempate LIMIT n
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT N_NAME, N_NATIONKEY
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION
WHERE N_REGIONKEY = 1
ORDER BY N_NAME DESC
LIMIT 2;
--
-- TU TURNO:
--   De ORDERS, los 5 pedidos más recientes con O_ORDERPRIORITY =
--   '1-URGENT'. Columnas: O_ORDERKEY, O_ORDERDATE, O_ORDERPRIORITY.
--   Ordena por O_ORDERDATE de más reciente a más antiguo y, si empatan,
--   por O_ORDERKEY de menor a mayor. LIMIT 5.
--   Columnas de salida (en este orden): O_ORDERKEY, O_ORDERDATE, O_ORDERPRIORITY

CREATE OR REPLACE VIEW EJ9 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ9;  -- mira tu resultado

-- ✅ Debes ver: 5 filas, columnas O_ORDERKEY, O_ORDERDATE, O_ORDERPRIORITY


-- =====================================================================
-- EJERCICIO 10 ★★★ · Reto: GROUP BY e INFORMATION_SCHEMA
-- =====================================================================
-- CONCEPTOS:
--   GROUP BY agrupa las filas que comparten el valor de una columna y
--   produce una fila por grupo.
--   INFORMATION_SCHEMA es el esquema de metadatos de Snowflake: contiene
--   vistas con el nombre de cada tabla y de cada columna.
--
-- DEFINICIÓN:
--   SELECT columna, COUNT(*) FROM tabla GROUP BY columna;
--   Con GROUP BY, cada columna del SELECT debe estar en GROUP BY o dentro
--   de una función (COUNT, SUM...).
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT N_REGIONKEY, COUNT(*) AS PAISES
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION
GROUP BY N_REGIONKEY
ORDER BY N_REGIONKEY;
--
-- TU TURNO:
--   Usa SNOWFLAKE_SAMPLE_DATA.INFORMATION_SCHEMA.COLUMNS. Cuenta cuántas
--   columnas tiene cada tabla del esquema TPCH_SF1 (filtra con
--   TABLE_SCHEMA = 'TPCH_SF1').
--   Columnas de salida (en este orden): TABLA_NOMBRE (que sale de
--   TABLE_NAME), NUM_COLUMNAS.
--   Ordena por NUM_COLUMNAS de mayor a menor y luego por TABLA_NOMBRE.
--   LIMIT 3.

CREATE OR REPLACE VIEW EJ10 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ10;  -- mira tu resultado

-- ✅ Debes ver: 3 filas, columnas TABLA_NOMBRE, NUM_COLUMNAS


-- =====================================================================
-- PASO FINAL · Corre la verificación
-- =====================================================================
-- 1. Copia lab1_verificacion.sql igual que copiaste lab1.sql (ver
--    "CÓMO COPIAR ESTE ARCHIVO A SNOWSIGHT" arriba).
-- 2. En Snowsight abre OTRA hoja nueva: + SQL Worksheet (o + > SQL File).
-- 3. Pega todo y pulsa Run All. No hace falta elegir rol ni warehouse.
-- 4. Busca el resultado de la consulta final: la tabla con EJERCICIO,
--    NIVEL, RESULTADO y PISTA.
--
-- Una fila por ejercicio:
--   OK         = bien.
--   REVISAR    = tu consulta existe pero no coincide. Lee la PISTA y compara
--                TUS_COLUMNAS con COLUMNAS_ESPERADAS.
--   PENDIENTE  = todavía no escribiste tu SELECT en esa vista.
-- La última fila es tu resumen: cuántos de los 6 ★ están en OK.
--
-- TU META: la fila RESUMEN dice OK y "6 de 6".
--   PENDIENTE en EJ7–EJ10 es normal si no hiciste los ★★.
--   Si dice PENDIENTE pero sí escribiste tu SELECT, tu CREATE falló:
--   busca el mensaje rojo.
--
-- Puedes correr la verificación cuantas veces quieras. Requisito: haber
-- corrido el PASO 0 de este archivo.


-- =====================================================================
-- QUÉ APRENDISTE
-- =====================================================================
-- - SELECT elige columnas. WHERE filtra filas. ORDER BY ordena. LIMIT corta.
-- - COUNT(*) cuenta filas. SUM(columna) suma valores.
-- - AS pone nombre a una columna. CREATE VIEW ... AS guarda la consulta.
-- - En un top-N, pon siempre un desempate (una columna única como la clave).
-- - Para un año completo: >= 1 de enero y < 1 de enero del año siguiente.
-- - El Query Profile te dice cuántas filas leyó cada paso. Eso explica
--   cuánto tarda y cuánto cuesta una consulta.
-- - Cada ejercicio fue una vista: así el sistema puede revisar tu respuesta.
--
-- Siguiente en esta sesión: GROUP BY, HAVING y JOIN; CTE en la clase 3.
