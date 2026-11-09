-- =====================================================================
-- LAB 3C · Estrella de TPC-H (Big Data UdeM · Clase 3)
-- =====================================================================
--
-- OBJETIVO
--   Construir una estrella con grano declarado, cargarla con CREATE TABLE ... AS SELECT, leer el
--   costo de la carga en el Query Profile, consultarla y comprobar que sus totales cuadran con el
--   origen.
--
-- GLOSARIO (solo lo nuevo respecto del Lab 3B)
--   tabla de hechos  una fila por evento medible, con llaves hacia las dimensiones y medidas.
--   dimensión        tabla que describe el contexto de la medida (quién, cuándo, qué).
--   grano            qué representa una fila de la tabla de hechos (aquí, una línea de pedido).
--   clave sustituta  identificador propio de una fila de dimensión, distinto de la clave de negocio.
--   huérfano         fila del hecho cuya clave no existe en la dimensión.
--   SCD              dimensión de cambio lento: sus atributos cambian con el tiempo (tipos 1 y 2).
--   marca de sesión  QUERY_TAG: etiqueta que queda en el historial de cada sentencia de la sesión.
--
-- CÓMO COPIAR ESTE ARCHIVO A SNOWSIGHT (solo navegador, sin terminal)
--   1. En tu fork: carpeta curso > clase03 > lab3c.sql.
--   2. Arriba a la derecha del contenido, el ícono de dos cuadritos es "Copy raw file"
--      (no el de la flecha hacia abajo).
--   3. En Snowsight: Projects > Worksheets > botón + (SQL Worksheet). Si tu Snowsight muestra
--      "Workspaces", usa + > SQL File.
--   4. Pega todo (Ctrl/Cmd + V). No elijas rol ni warehouse: el Paso 0 los fija.
--   5. Si no ves el archivo: botón "Sync fork" > "Update branch".
--
-- CÓMO CORRER
--   Paso 0: selecciona de USE ROLE a USE SCHEMA CURSO.LAB3C; y pulsa ▶.
--   Paso 1: corre ALTER SESSION SET QUERY_TAG = 'LAB3C'; antes de cargar cualquier tabla.
--   Ejercicios: bloque a bloque con Cmd/Ctrl+Enter (corre la consulta donde está el cursor).
--   Run All corre todo el archivo: en este archivo NO lo uses.
--
-- TIEMPO: 32 min de trabajo en clase. Orden: C1 a C3, la lectura del costo (4 min, obligatoria),
--   C4 y C5 (★, núcleo; la verificación exige los cinco). C6 y C7 (★★) y C8 (★★★) son opcionales.
--   DIM_FECHA (C2) ya viene resuelta para pagar los minutos de la lectura; el hecho no.
--
-- NIVELES
--   ★    núcleo: cinco ejercicios; la verificación exige los cinco
--   ★★   si queda tiempo
--   ★★★  reto
--
-- REGLAS DEL LAB
--   Todo en TPC-H SF1 (SNOWFLAKE_SAMPLE_DATA.TPCH_SF1, solo lectura, ruta completa) y en el esquema
--   CURSO.LAB3C. Los objetos de C1 a C3, C6 y C8 son TABLAS, no vistas: el hecho se carga una vez.
--   Cada tabla se carga con una sentencia propia. Para cargas posteriores el patrón es
--   INSERT INTO ... SELECT. Grano declarado: una línea de pedido (L_ORDERKEY, L_LINENUMBER).
--
-- DICCIONARIO RÁPIDO (TPC-H, factor de escala 1)
--   CUSTOMER  C_CUSTKEY, C_NAME, C_NATIONKEY, C_MKTSEGMENT
--   NATION    N_NATIONKEY, N_NAME, N_REGIONKEY
--   REGION    R_REGIONKEY, R_NAME
--   ORDERS    O_ORDERKEY, O_CUSTKEY, O_ORDERDATE, O_TOTALPRICE
--   LINEITEM  L_ORDERKEY, L_LINENUMBER, L_PARTKEY, L_QUANTITY, L_EXTENDEDPRICE, L_DISCOUNT
--   PART      P_PARTKEY, P_NAME, P_BRAND, P_TYPE
--
-- CÓMO ESCRIBIR CADA EJERCICIO
--   Igual que en los labs anteriores: escribes solo en el lugar del marcador (la línea
--   SELECT NULL AS PENDIENTE), sin punto y coma al final del SELECT. En C1, C3, C6 y C8 el
--   marcador está dentro de un CREATE OR REPLACE TABLE ... AS; en C4, C5, C6, C7 y C8, dentro de
--   un CREATE OR REPLACE VIEW ... AS. Los nombres de las columnas son parte del ejercicio.
--
--   Ejemplo del marcador en una tabla (reemplazas la línea SELECT NULL AS PENDIENTE por tu SELECT):
--     CREATE OR REPLACE TABLE DIM_CLIENTE AS
--     -- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
--     SELECT NULL AS PENDIENTE
--     -- ▲▲ hasta aquí ▲▲
--     ;
--   Ejecuta los dos bloques de cada ejercicio con Cmd/Ctrl+Enter. Debes ver "Table DIM_CLIENTE
--   successfully created" (o "View ... successfully created") y luego tu resultado. Si ves un
--   mensaje rojo, el CREATE falló: lee el mensaje y consulta la tabla de errores comunes al final.
--   Cada columna calculada necesita AS NOMBRE; si no, la vista falla con "Missing column
--   specification".
--
--   Una vista guarda la consulta, no los datos; una tabla guarda los datos que cargó.
-- =====================================================================


-- =====================================================================
-- PASO 0 · PREPARACIÓN (ya resuelto: no lo cambies)
-- QUÉ HACER: selecciona con el mouse desde USE ROLE hasta USE SCHEMA CURSO.LAB3C; y pulsa ▶.
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

-- TU BASE DE TRABAJO: CURSO es la base de datos y LAB3C el esquema donde se guardan tus objetos.
CREATE DATABASE IF NOT EXISTS CURSO;
CREATE SCHEMA IF NOT EXISTS CURSO.LAB3C;
USE SCHEMA CURSO.LAB3C;


-- =====================================================================
-- PASO 1 · MARCA DE LA CARGA (ya resuelto: córrelo antes de cargar tablas)
-- =====================================================================
-- QUERY_TAG pone una etiqueta a cada sentencia que corras en esta hoja. Todas las cargas de este lab
-- quedan marcadas LAB3C y la consulta de lectura, más abajo, las encuentra por esa marca.
-- La marca vale solo para esta hoja (esta sesión): si cambias de hoja, corre esta línea de nuevo.

ALTER SESSION SET QUERY_TAG = 'LAB3C';
SHOW PARAMETERS LIKE 'QUERY_TAG' IN SESSION;
-- Debes ver: una fila con QUERY_TAG y el valor LAB3C.



-- =====================================================================
-- EJERCICIO 1 ★ · Dimensión de cliente: nación y región en la misma fila
-- =====================================================================
-- DEFINICIÓN:
--   DIMENSIÓN: tabla que describe el contexto de lo que se mide (quién, cuándo, qué), con una llave y
--   atributos descriptivos. DIM_CLIENTE reúne en una fila el cliente, su nación y su región:
--   desnormalizar es repetir N_NAME y R_NAME en cada cliente para que una pregunta por región
--   necesite una sola unión con el hecho, no cuatro. Aquí los objetos son TABLAS (no vistas):
--   el hecho se carga una vez con CREATE TABLE ... AS SELECT. Una tabla nueva por sentencia.
--   CLIENTE_KEY es la llave de la dimensión; aquí coincide con C_CUSTKEY.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT C.C_CUSTKEY, N.N_NAME, R.R_NAME
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER C
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION N ON C.C_NATIONKEY = N.N_NATIONKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION R ON N.N_REGIONKEY = R.R_REGIONKEY
ORDER BY C.C_CUSTKEY
LIMIT 3;
-- Debes ver en el ejemplo: 3 filas: 1 MOROCCO AFRICA; 2 JORDAN MIDDLE EAST; 3 ARGENTINA AMERICA.
--
-- TU TURNO:
--   Crea la tabla DIM_CLIENTE: CUSTOMER con el nombre de su nación y de su región, una fila por
--   cliente (son 150000 clientes; unos 50000 no tienen pedidos y deben estar).
--   Columnas (en este orden): CLIENTE_KEY (= C_CUSTKEY), C_NAME, C_MKTSEGMENT, N_NAME, R_NAME

CREATE OR REPLACE TABLE DIM_CLIENTE AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT COUNT(*) AS FILAS FROM DIM_CLIENTE;
SELECT * FROM DIM_CLIENTE LIMIT 5;  -- mira tu resultado
-- Al terminar, comprueba nación, región y claves (descomenta):
-- SELECT COUNT(DISTINCT CLIENTE_KEY) AS CLAVES, COUNT(DISTINCT N_NAME) AS NACIONES, COUNT(DISTINCT R_NAME) AS REGIONES FROM DIM_CLIENTE;

-- ✅ Debes ver: 150000 filas; 25 naciones y 5 regiones distintas; CLIENTE_KEY sin repetir.


-- =====================================================================
-- EJERCICIO 2 ★ · Dimensión de fechas (ya resuelta)
-- =====================================================================
-- DEFINICIÓN:
--   DIM_FECHA tiene un día por fila, de la fecha mínima a la máxima de O_ORDERDATE. GROUP BY por fecha
--   solo devuelve las fechas que tienen filas; una tabla con todos los días y un LEFT JOIN muestran
--   los días vacíos. GENERATOR crea un número fijo de filas (ROWCOUNT no admite una variable): se
--   generan 3000 y QUALIFY corta en la fecha máxima. ROW_NUMBER numera sin huecos; SEQ4 solo fija el
--   orden (la documentación no garantiza que SEQ4 no tenga huecos).
--   Esta dimensión ya viene resuelta para ganar tiempo: corre el bloque tal como está. Es la plantilla
--   de la slide 32; el hecho NO viene resuelto (C3).
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT MIN(O_ORDERDATE) AS PRIMERA, MAX(O_ORDERDATE) AS ULTIMA,
       DATEDIFF('day', MIN(O_ORDERDATE), MAX(O_ORDERDATE)) + 1 AS DIAS_EN_RANGO
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS;
-- Debes ver en el ejemplo: 1 fila: 1992-01-01, 1998-08-02 y 2406 días en el rango.
--
-- TU TURNO:
--   Corre el bloque de abajo sin cambiarlo: crea la tabla DIM_FECHA (ya resuelta).
--   Columnas (en este orden): FECHA, ANIO (= YEAR(FECHA)), MES (= MONTH(FECHA), número de 1 a 12)

CREATE OR REPLACE TABLE DIM_FECHA AS
WITH r AS (SELECT MIN(O_ORDERDATE) AS MINF, MAX(O_ORDERDATE) AS MAXF
           FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS)
SELECT FECHA, YEAR(FECHA) AS ANIO, MONTH(FECHA) AS MES
FROM (SELECT DATEADD('day', ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1, MINF) AS FECHA
      FROM r, TABLE(GENERATOR(ROWCOUNT => 3000))
      QUALIFY FECHA <= MAXF);
SELECT COUNT(*) AS FILAS, MIN(FECHA) AS PRIMERA, MAX(FECHA) AS ULTIMA FROM DIM_FECHA;
SELECT * FROM DIM_FECHA ORDER BY FECHA LIMIT 5;  -- mira tu resultado

-- ✅ Debes ver: 2406 filas; de 1992-01-01 a 1998-08-02.


-- =====================================================================
-- EJERCICIO 3 ★ · Tabla de hechos con el grano declarado
-- =====================================================================
-- DEFINICIÓN:
--   TABLA DE HECHOS: una fila por evento medible, con llaves hacia las dimensiones y medidas numéricas.
--   GRANO: qué representa una fila. Aquí, una línea de pedido, identificada por L_ORDERKEY y
--   L_LINENUMBER; cada medida y cada llave debe ser verdadera a ese nivel. L_EXTENDEDPRICE y
--   L_QUANTITY lo son; O_TOTALPRICE es del pedido, no de la línea: no va en el hecho (si se guardara,
--   se repetiría en cada línea y cualquier SUM lo inflaría; lo comprobarás en C7).
--   La fecha y el cliente de la línea salen de su pedido (ORDERS): une LINEITEM con ORDERS solo por
--   L_ORDERKEY y comprueba que el conteo no cambia.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT L.L_ORDERKEY, L.L_LINENUMBER, O.O_CUSTKEY, O.O_ORDERDATE
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM L
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O ON L.L_ORDERKEY = O.O_ORDERKEY
WHERE L.L_ORDERKEY = 1
ORDER BY L.L_LINENUMBER;
-- Debes ver en el ejemplo: 6 filas, las líneas 1 a 6 del pedido 1, todas con el cliente 36901 y la fecha 1996-01-02.
--
-- TU TURNO:
--   Crea la tabla FACT_LINEITEM: una fila por línea de pedido, con la fecha y el cliente de su pedido
--   y el ingreso INGRESO = L_EXTENDEDPRICE * (1 - L_DISCOUNT). CLIENTE_KEY sale de O_CUSTKEY, FECHA de
--   O_ORDERDATE y PRODUCTO_KEY de L_PARTKEY.
--   Columnas (en este orden): L_ORDERKEY, L_LINENUMBER, CLIENTE_KEY, FECHA, PRODUCTO_KEY, L_QUANTITY,
--   L_EXTENDEDPRICE, L_DISCOUNT, INGRESO

CREATE OR REPLACE TABLE FACT_LINEITEM AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT COUNT(*) AS FILAS FROM FACT_LINEITEM;
SELECT * FROM FACT_LINEITEM LIMIT 5;  -- mira tu resultado
-- Al terminar, comprueba el ingreso (descomenta):
-- SELECT ROUND(SUM(INGRESO)) AS INGRESO FROM FACT_LINEITEM;  -- 218102223885

-- ✅ Debes ver: 6001215 filas; SUM(INGRESO) redondeada a enteros: 218102223885.


-- =====================================================================
-- LECTURA DEL COSTO · Query Profile del paso más caro (obligatoria, unos 4 min)
-- =====================================================================
-- QUÉ HACER: después de C3 (y antes de C4), lee dónde se fue el tiempo de la carga. La respuesta
-- se escribe en comentarios y NO se califica; lo que la verificación revisa es que las cargas
-- hayan quedado marcadas LAB3C.
--
-- 1. Corre la consulta de abajo (ya está escrita). Lista cada carga marcada LAB3C, una fila por
--    paso (la última vez que la corriste), de mayor a menor tiempo de ejecución: PASO es el
--    texto corto de la sentencia, SEGUNDOS es EXECUTION_TIME / 1000 y QUERY_ID identifica la
--    ejecución.
-- 2. Abre el Query Profile del paso más caro: Monitoring > Query History, busca esa consulta
--    (por su texto o su QUERY_ID) > pestaña Query Profile. Es el mismo perfil de la clase 2.
-- 3. Responde en los comentarios de abajo.

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
    AND SCHEMA_NAME = 'LAB3C'
)
SELECT PASO, SEGUNDOS, QUERY_ID
FROM H
QUALIFY ROW_NUMBER() OVER (PARTITION BY PASO ORDER BY START_TIME DESC) = 1
ORDER BY SEGUNDOS DESC, PASO;
-- Debes ver: una fila por carga: FACT_LINEITEM arriba con unos 2 s (X-Small) y debajo DIM_FECHA,
-- DIM_CLIENTE y las demás con menos de 1.5 s. Los tiempos varían entre corridas; el orden casi no.
-- Si no ves filas: el ALTER SESSION SET QUERY_TAG del Paso 1 se corrió en otra hoja (la marca
-- vale por sesión, es decir, por hoja) o no cargaste ninguna tabla todavía.

-- MIS RESPUESTAS (no se califican; escríbelas aquí):
--   Paso más caro: ____
--   Operador que concentra el tiempo (en el Query Profile): ____
--   Decisión (¿lo cambiarías o lo dejarías así, y por qué?): ____

-- Alternativa en SQL, con el mismo dato que muestra el perfil (opcional): pega el QUERY_ID del paso
-- más caro en lugar de <QUERY_ID> y quita los dos guiones de la línea.
-- SELECT OPERATOR_ID, OPERATOR_TYPE, OPERATOR_STATISTICS:output_rows AS FILAS_SALIDA, EXECUTION_TIME_BREAKDOWN:overall_percentage AS PORCENTAJE FROM TABLE(GET_QUERY_OPERATOR_STATS('<QUERY_ID>')) ORDER BY PORCENTAJE DESC;


-- =====================================================================
-- EJERCICIO 4 ★ · Ingreso por región y año con dos uniones
-- =====================================================================
-- DEFINICIÓN:
--   Con la estrella, una pregunta de negocio se resuelve con el hecho y las dimensiones que filtra o
--   agrupa: ingreso por región y año usa DIM_CLIENTE y DIM_FECHA, dos uniones, no cuatro. Las uniones
--   son por las llaves del hecho (CLIENTE_KEY y FECHA).
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT ANIO, COUNT(*) AS DIAS
FROM DIM_FECHA
GROUP BY ANIO
ORDER BY ANIO;
-- Debes ver en el ejemplo: 7 filas, de 1992 a 1998: 366 días en 1992, 365 en 1993, 365 en 1994, 365 en 1995, 366 en 1996, 365 en 1997 y 214 en 1998.
--
-- TU TURNO:
--   Crea la vista C4: ingreso por región y año, con FACT_LINEITEM, DIM_CLIENTE y DIM_FECHA.
--   INGRESO es la suma del ingreso, a 2 decimales. Ordena por R_NAME y ANIO.
--   Columnas de salida (en este orden): R_NAME, ANIO, INGRESO

CREATE OR REPLACE VIEW C4 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM C4;  -- mira tu resultado

-- ✅ Debes ver: 35 filas (5 regiones x 7 años). Primera: AFRICA, 1992, 6608511861.49. Última: MIDDLE EAST, 1998, 3869651630.83. La suma de INGRESO es 218102223885.00.


-- =====================================================================
-- EJERCICIO 5 ★ · Controles de filas y de grano
-- =====================================================================
-- DEFINICIÓN:
--   Los errores de diseño no dan mensaje: solo se ven comparando con el origen. Dos controles:
--   FILAS (el hecho tiene tantas filas como LINEITEM) y GRANO (la clave que identifica la línea,
--   L_ORDERKEY * 10 + L_LINENUMBER, no se repite; L_LINENUMBER va de 1 a 7, por eso el factor 10).
--   Si las claves distintas son menos que las filas, hay duplicados.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT COUNT(*) AS FILAS_LINEITEM,
       COUNT(DISTINCT L_ORDERKEY * 10 + L_LINENUMBER) AS CLAVES_DISTINTAS
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM;
-- Debes ver en el ejemplo: 1 fila: 6001215 filas y 6001215 claves distintas.
--
-- TU TURNO:
--   Crea la vista C5 con los controles del hecho: dos filas, 'filas' (cuántas filas tiene
--   FACT_LINEITEM) y 'grano' (cuántas claves distintas L_ORDERKEY * 10 + L_LINENUMBER tiene).
--   Columnas de salida (en este orden): CONTROL, VALOR

CREATE OR REPLACE VIEW C5 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM C5;  -- mira tu resultado

-- ✅ Debes ver: 2 filas: filas 6001215 y grano 6001215; ambas iguales a COUNT(*) de LINEITEM.


-- =====================================================================
-- EJERCICIO 6 ★★ · Dimensión de producto y las marcas con más ingreso
-- =====================================================================
-- DEFINICIÓN:
--   Una tercera dimensión: DIM_PRODUCTO sale de PART (200000 partes; las 200000 se venden en SF1). La
--   llave del hecho es PRODUCTO_KEY, copia de L_PARTKEY. Es opcional porque la pregunta de negocio
--   del lab no la usa: el modelo la admite sin cambiar el hecho.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT P_BRAND, COUNT(*) AS PARTES
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.PART
GROUP BY P_BRAND
ORDER BY PARTES DESC, P_BRAND
LIMIT 3;
-- Debes ver en el ejemplo: 3 filas: Brand#35 con 8233 partes, Brand#12 con 8167 y Brand#52 con 8158; son 25 marcas en total.
--
-- TU TURNO:
--   Crea la tabla DIM_PRODUCTO desde PART y la vista C6: las 5 marcas con más ingreso (une el hecho con
--   DIM_PRODUCTO). INGRESO a 2 decimales; ordena por INGRESO de mayor a menor.
--   Columnas de DIM_PRODUCTO (en este orden): PRODUCTO_KEY (= P_PARTKEY), P_NAME, P_BRAND, P_TYPE
--   Columnas de C6 (en este orden): P_BRAND, INGRESO

CREATE OR REPLACE TABLE DIM_PRODUCTO AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT COUNT(*) AS FILAS FROM DIM_PRODUCTO;
SELECT * FROM DIM_PRODUCTO LIMIT 5;  -- mira tu resultado

CREATE OR REPLACE VIEW C6 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM C6;  -- mira tu resultado

-- ✅ Debes ver: DIM_PRODUCTO, 200000 filas. C6: Brand#35 8968148860.13; Brand#12 8938475171.10; Brand#52 8907337839.72; Brand#53 8817506530.89; Brand#33 8811786224.88.


-- =====================================================================
-- EJERCICIO 7 ★★ · Grano mezclado: la medida del pedido infla la suma
-- =====================================================================
-- DEFINICIÓN:
--   Si una tabla de líneas guardara O_TOTALPRICE (medida de pedido), el valor se repetiría en cada línea del
--   pedido y cualquier SUM saldría inflado. Es el mismo fenómeno de la clase 2, pero aquí el error
--   está en la tabla, no en la consulta. Compruébalo: suma O_TOTALPRICE después de unir LINEITEM con
--   ORDERS y compárala con la suma en ORDERS.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT COUNT(*) AS PEDIDOS, SUM(O_TOTALPRICE) AS SUMA_PEDIDOS
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS;
-- Debes ver en el ejemplo: 1 fila: 1500000 pedidos y SUMA_PEDIDOS 226829306447.46.
--
-- TU TURNO:
--   Crea la vista C7: SUMA_PEDIDOS (SUM de O_TOTALPRICE en ORDERS), SUMA_INFLADA (SUM de O_TOTALPRICE
--   después de unir LINEITEM con ORDERS, una fila por línea) y VECES (SUMA_INFLADA / SUMA_PEDIDOS, con
--   1 decimal).
--   Columnas de salida (en este orden): SUMA_PEDIDOS, SUMA_INFLADA, VECES

CREATE OR REPLACE VIEW C7 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM C7;  -- mira tu resultado

-- ✅ Debes ver: 1 fila: 226829306447.46; 1134436101880.19; 5.0


-- =====================================================================
-- EJERCICIO 8 ★★★ · SCD tipo 2: la dimensión conserva la historia
-- =====================================================================
-- DEFINICIÓN:
--   SCD (slowly changing dimension, dimensión de cambio lento): una dimensión cuyos atributos cambian con
--   el tiempo. Tipo 1 sobrescribe el valor y borra la historia; tipo 2 cierra la versión vigente y
--   agrega una fila nueva con otra CLAVE SUSTITUTA (identificador propio de la versión, distinto de la
--   clave de negocio C_CUSTKEY). La unión con el hecho es por la clave de negocio y el rango de
--   fechas: FECHA BETWEEN DESDE AND HASTA. Es la demo de las slides 33 y 34 hecha por ti.
--   El cliente 102022 es real (INDONESIA, ASIA); la mudanza a FRANCE (EUROPE) el 1995-06-01 es un
--   supuesto del ejemplo.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT V.R_NAME
FROM (VALUES ('ASIA',   '1992-01-01'::DATE, '1995-05-31'::DATE),
             ('EUROPE', '1995-06-01'::DATE, '9999-12-31'::DATE)) V(R_NAME, DESDE, HASTA)
WHERE '1994-03-01'::DATE BETWEEN V.DESDE AND V.HASTA;
-- Debes ver en el ejemplo: 1 fila: ASIA (el 1994-03-01 cae en la primera versión).
--
-- TU TURNO:
--   Crea la tabla DIM_CLIENTE_SCD2 con dos versiones del cliente 102022: INDONESIA / ASIA desde
--   1992-01-01 hasta 1995-05-31 y FRANCE / EUROPE desde 1995-06-01 hasta 9999-12-31. Columnas sugeridas: SK
--   (clave sustituta), CLIENTE_KEY, N_NAME, R_NAME, DESDE, HASTA, ES_ACTUAL.
--   Después crea la vista C8: el ingreso de ese cliente por región según la versión vigente a la
--   fecha del pedido (une FACT_LINEITEM con la tabla por CLIENTE_KEY y FECHA BETWEEN DESDE AND HASTA).
--   PEDIDOS cuenta pedidos distintos; INGRESO va a 2 decimales. Ordena por R_NAME.
--   Columnas de C8 (en este orden): R_NAME, PEDIDOS, INGRESO

CREATE OR REPLACE TABLE DIM_CLIENTE_SCD2 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM DIM_CLIENTE_SCD2 LIMIT 5;

CREATE OR REPLACE VIEW C8 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM C8;  -- mira tu resultado

-- ✅ Debes ver: 2 filas: ASIA, 19, 2951661.88; EUROPE, 22, 3087991.75 (suman 6039653.63).



-- =====================================================================
-- PASO FINAL · Corre la verificación
-- =====================================================================
-- 1. Quita la marca de esta hoja:
ALTER SESSION UNSET QUERY_TAG;
-- 2. Copia lab3c_verificacion.sql igual que copiaste este archivo.
-- 3. En Snowsight abre OTRA hoja nueva (+ SQL Worksheet o + > SQL File), pega todo y pulsa Run All.
-- 4. Busca la tabla final: EJERCICIO, NIVEL, RESULTADO, PISTA.
--
-- Una fila por ejercicio:
--   OK         = correcto.
--   REVISAR    = el objeto existe pero no coincide. Lee la PISTA y compara TUS_COLUMNAS con
--                COLUMNAS_ESPERADAS.
--   PENDIENTE  = el objeto todavía es el marcador SELECT NULL AS PENDIENTE.
-- La fila MARCA dice si las cargas de DIM_CLIENTE, DIM_FECHA y FACT_LINEITEM quedaron marcadas
-- LAB3C (PENDIENTE: no hay cargas tuyas con la marca; REVISAR: falta alguna). La lectura del costo
-- no se califica.
-- La última fila es el resumen: cuántos de los 5 ★ están en OK. META: RESUMEN = OK y "5 de 5".
-- PENDIENTE en C6 a C8 es normal si no llegaste a los opcionales. Si dice PENDIENTE pero escribiste
-- tu SELECT, el CREATE falló: busca el mensaje rojo.


-- =====================================================================
-- QUÉ APRENDISTE
-- =====================================================================
-- - La estrella guarda lo que se mide en un hecho de grano declarado (una línea de pedido) y lo que
--   lo describe en dimensiones; una pregunta por región y año usa dos uniones, no cuatro.
-- - La medida del pedido (O_TOTALPRICE) no pertenece a un hecho de líneas: repetida en cada línea,
--   infla la suma 5 veces.
-- - Una estrella cuadra cuando pasan los controles contra el origen: filas, grano, claves sin pareja
--   e ingreso. Los errores de diseño no dan mensaje.
-- - El Query Profile también sirve para leer una carga: el paso más caro es el que une LINEITEM con
--   ORDERS; se carga una vez y las cargas siguientes serían INSERT INTO ... SELECT.
-- - Una dimensión que cambia (SCD) conserva la historia con una fila por versión (tipo 2).
--
-- Siguiente: la slide 36 generaliza los controles en cuatro, y el caso de NYC (lluvia y viajes)
-- aplica la misma estrella con datos reales.


-- =====================================================================
-- ERRORES COMUNES
-- =====================================================================
-- Mensaje o síntoma                             | Causa                          | Cómo evitarlo
-- ---------------------------------------------|--------------------------------|---------------------------
-- FACT_LINEITEM con más de 6001215 filas       | Uniste con una tabla que       | Une solo con ORDERS por
--                                              | repite la clave                | L_ORDERKEY y cuenta antes y
--                                              |                                | después
-- DIM_FECHA con 3000 filas                     | Faltó el filtro por la fecha   | QUALIFY FECHA <= MAXF,
--                                              | máxima                         | después de calcular FECHA con
--                                              |                                | ROW_NUMBER (SEQ4 solo ordena)
-- La consulta de lectura no devuelve filas     | La marca no está en esta hoja  | Corre el Paso 1 (ALTER
--                                              | o no cargaste tablas todavía   | SESSION SET QUERY_TAG) en la
--                                              |                                | misma hoja, antes de cargar
-- This session does not have a current         | No se corrió el Paso 0 en esa  | Selecciona de USE ROLE a
--   database (en la consulta de lectura)       | hoja: QUERY_HISTORY necesita   | USE SCHEMA CURSO.LAB3C; y
--                                              | una base activa                | pulsa ▶
-- Object 'FACT_LINEITEM' does not exist (C4,   | Creaste la vista antes que     | Carga primero C1 a C3 y
--   C5, C6, C8)                                | las tablas                     | luego las vistas
-- MARCA en PENDIENTE o REVISAR en la           | La carga no se hizo con la     | Corre el Paso 1 en la misma
--   verificación                               | marca LAB3C en esa hoja        | hoja y vuelve a correr el
--                                              |                                | CREATE TABLE del hecho
-- Missing column specification (al crear la    | COUNT o SUM sin AS             | Pon AS NOMBRE en cada
--   vista)                                     |                                | columna calculada
-- REVISAR en C3 con el conteo correcto         | Falta una columna, otro nombre | Compara TUS_COLUMNAS con
--                                              | o INGRESO sin el descuento     | COLUMNAS_ESPERADAS
-- REVISAR con columnas distintas               | El alias de salida no coincide | Compara TUS_COLUMNAS con
--                                              |                                | COLUMNAS_ESPERADAS
