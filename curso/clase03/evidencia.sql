-- =====================================================================
-- CLASE 3 · Evidencia de cada afirmación del deck (Snowsight)
-- =====================================================================
--
-- PARA QUÉ SIRVE
--   Cada cifra, comparación o comportamiento de SQL que aparece en pantalla en las 38 slides
--   tiene aquí una consulta, o una cita de la documentación si no se puede medir. Los bloques
--   van en orden de slide. Cada uno trae: la afirmación tal como está en pantalla, qué
--   demuestra cada paso, las consultas paso a paso y, debajo de cada una, el resultado
--   esperado (medido el 9 nov. 2026 en X-Small). Sirve para responder «¿de dónde sale este
--   número?» sin improvisar. demos.sql sigue siendo el guion de la clase; este archivo es la
--   respuesta a la pregunta.
--
-- CÓMO USARLO
--   1. Pega el archivo en una hoja de Snowsight y corre primero el PREPARACIÓN (abajo): crea
--      la base CURSO_EVIDENCIA_C3 y deja la sesión lista.
--   2. Después corre el bloque de la slide que te pregunten, consulta por consulta
--      (Cmd/Ctrl+Enter). También puedes correr todo con Run All: las únicas sentencias que
--      fallan lo hacen dentro de un bloque que atrapa el error y lo muestra como texto
--      (slides 18 y 20). Tarda unos 4 min en total.
--   3. Al final, el bloque FIN borra la base. Corre ese bloque cuando termines.
--   Los bloques de las slides 29 a 31 y 33 a 36 usan las tablas que construye el bloque de la
--   slide 28. Si saltas a esas slides, corre antes el paso 28.0 (unos 5 s).
--
-- WAREHOUSE
--   COMPUTE_WH, tamaño X-Small. Las slides 11, 21 y 26 usan TPC-H SF10 (15 M de pedidos y
--   60 M de líneas): son los bloques más caros, unos 2 min de X-Small cada uno (0.04 créditos).
--   El resto usa SF1 y tarda segundos. Para volver a medir tiempos, corre el bloque entero:
--   la primera corrida de cada consulta es la más lenta (caché de datos del warehouse).
--
-- CACHÉ DE RESULTADOS
--   ALTER SESSION SET USE_CACHED_RESULT = FALSE (en el PREPARACIÓN): sin ella, repetir una
--   consulta devuelve el resultado guardado en 0 s y los tiempos no significan nada.
--
-- DATOS
--   SNOWFLAKE_SAMPLE_DATA (TPCH_SF1, TPCH_SF10, TPCH_SF100), solo lectura. Las tablas de la
--   estrella y de las mudanzas del cliente (SCD) se crean en CURSO_EVIDENCIA_C3 y nada más.
--   Excepción: las slides 30 y 37 leen BIGDATA.DEV.DAILY_ZONE_METRICS (el gold de enero 2024
--   de la clase 1). Si esa tabla no existe en tu cuenta, el bloque devuelve un AVISO, no un
--   error.
--
-- CÓMO LEER LOS RESULTADOS
--   «Esperado» = lo medido el 9 nov. 2026. Los conteos y las sumas no cambian entre corridas;
--   los tiempos sí (compilación sobre todo): compara órdenes de magnitud, no milisegundos.
--   Los bytes de las tablas que se crean aquí varían unos miles entre corridas.
--
-- FUENTES
--   validacion/contenido/clase03_medidas.md (M1 a M19) y clase02_query_profile.md. Cuando una
--   afirmación es de documentación o de diseño, el bloque cita la fuente en vez de inventar
--   una consulta.
--
-- ÍNDICE: SLIDE -> BLOQUE
--   Slide  1  portada, sin afirmaciones
--   Slide  2  un JOIN sin error infla el total: pedido 1066817, 226.8 -> 1 134.4 ..... bloque 2
--   Slide  3  GROUP BY deja 99 996 filas de 1 500 000 ........................... bloque 3
--   Slide  4  los tres problemas y sus síntomas medidos ............................ bloque 4
--   Slide  5  las ocho tablas de TPC-H y sus filas ............................... bloque 5
--   Slide  6  ventana: los 41 pedidos siguen ahí, total 6 273 788.41 ............. bloque 6
--   Slide  7  sin ORDER BY total, con ORDER BY acumulado ......................... bloque 7
--   Slide  8  ROW_NUMBER, RANK y DENSE_RANK con empates .......................... bloque 8
--   Slide  9  LAG: 49, 44 y 32 días; mayor pausa 227 ............................ bloque 9
--   Slide 10  media móvil de tres pedidos; ROWS contra RANGE ..................... bloque 10
--   Slide 11  ventana con ORDER BY: 4 veces más lenta y 215 MB de derrame (SF10) .. bloque 11
--   Slides 12 a 16  logística (Lab 3A, AWS, make doctor) ........... bloque 12 a 16 (citas)
--   Slide 17  el top-3 del Lab 3A salió anidado .................................. bloque 18
--   Slide 18  WHERE no filtra ventanas (error 002063) ............................ bloque 18
--   Slide 19  QUALIFY: 299 831 filas ............................................. bloque 19
--   Slide 20  CTE: 99 996 filas; 297 453 en AUTOMOBILE ........................... bloque 20
--   Slide 21  agregar antes de unir: 60 M contra 15 M filas, 5.0 veces (SF10) ..... bloque 21
--   Slide 22  promedio de promedios 161 711.03 contra 151 219.54 (6.9 %) ......... bloque 22
--   Slide 23  Lab 3B (QUALIFY y promedio ponderado) ......... bloques 19 y 22 (citas)
--   Slide 24  cuatro uniones para traer una región ............................... bloque 24
--   Slide 25  R_NAME vive en 5 filas, no en 6 M .................................. bloque 25
--   Slide 26  desnormalizar: ejecución a la mitad, +6 a 7 % de espacio (SF10) ..... bloque 26
--   Slide 27  copo de nieve contra estrella ...................................... bloque 26
--   Slide 28  el grano: 6 001 215, 1 500 000 y 2 406 ............................. bloque 28
--   Slide 29  la estrella y sus dimensiones ...................................... bloque 29
--   Slide 30  aditividad: INGRESO, promedios y LLUVIA_MM .......................... bloque 30
--   Slide 31  grano mezclado: la suma se infla 5 veces ........................... bloque 31
--   Slide 32  la fecha como dimensión: 39 de 2 406 días .......................... bloque 32
--   Slide 33  SCD tipo 1: 41 pedidos pasan de ASIA a EUROPE ...................... bloque 33
--   Slide 34  SCD tipo 2: 19 pedidos a ASIA y 22 a EUROPE ........................ bloque 34
--   Slide 35  Lab 3C: cuál paso de la carga costó más ............................ bloque 35
--   Slide 36  los cuatro controles de la estrella ................................ bloque 36
--   Slide 37  NYC: LLUVIA_MM en 31 filas, no en 15 909 ........................... bloque 37
--   Slide 38  cierre: cifras que vuelven de las slides 22, 24, 26 y 36 ........... bloque 38
-- =====================================================================


-- =====================================================================
-- PREPARACIÓN · Correr una vez, antes de cualquier bloque
-- Qué se muestra: nada. Deja el rol, el warehouse, la caché de resultados y la base de trabajo.
-- Resultado esperado: «Database CURSO_EVIDENCIA_C3 successfully created.»
-- =====================================================================
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;                    -- X-Small
ALTER SESSION SET USE_CACHED_RESULT = FALSE; -- sin esto los tiempos no se pueden medir
CREATE OR REPLACE DATABASE CURSO_EVIDENCIA_C3;
USE SCHEMA CURSO_EVIDENCIA_C3.PUBLIC;
-- Esta base es lo único que crea el archivo. El bloque FIN la borra.


-- =====================================================================
-- SLIDE 1 · Portada
-- Afirmación en pantalla: «Clase 3 · Responder bien y guardar para que el total cuadre».
-- Sin afirmación verificable. (Las cifras de la clase 2 que menciona la nota del orador,
--   600 M de valores en 0.6 s y 1 022 micro-particiones, están en clase02_query_profile.md y
--   en curso/clase02/deck_corto/slides.json, slide 30; no están en pantalla.)
-- =====================================================================


-- =====================================================================
-- SLIDE 2 · Primer límite: un JOIN sin error infla el total
-- Afirmación en pantalla: «Primer límite: un JOIN sin error infla el total, porque cada
--   pedido se repite en cada línea.» Diagrama: la consulta SUM(O.O_TOTALPRICE) con JOIN entre
--   ORDERS y LINEITEM, «Sin error»; el pedido 1066817 con sus 4 líneas (total 144 930.46
--   repetido; precios de línea 30 964.08, 25 868.64, 41 592.32 y 48 703.98) y «Suma:
--   579 721.84 (× 4)»; «En todo SF1: 226.8 -> 1 134.4 mil millones (× 5.0)». Pie: lo evita
--   la slide 21 y explica la causa la 31. Fuente: clase 2, SF1 (deck corto, slide 19).
-- Qué demuestra cada paso:
--   2.1  cuántos pedidos hay y cuánto suman (226.8 mil millones, el valor correcto).
--   2.2  cuántas líneas hay y que cada pedido tiene al menos una.
--   2.3  un pedido con sus líneas: O_TOTALPRICE se repite en cada línea (es del pedido).
--   2.3b el pedido 1066817 es del cliente 102022 (el de las slides 6, 10 y 32 a 34).
--   2.4  la suma después del JOIN: 6 001 215 filas y 1 134.4 mil millones.
--   2.5  el cociente: 5.0 veces la suma correcta, mientras las filas se multiplican por 4.0.
--   2.6  por qué 5.0 y no 4.0: cada pedido pesa tantas veces como líneas tiene, y los
--        pedidos con más líneas son los más caros.
--   2.7  «sin aviso» y «rápido»: la consulta termina con éxito, sin error, y se ejecuta en
--        unas 2 décimas de segundo.
-- =====================================================================

-- Paso 2.1 · Pedidos y su suma: el valor correcto
SELECT COUNT(*) AS PEDIDOS, SUM(O_TOTALPRICE) AS SUMA_PEDIDOS
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS;
-- Esperado: PEDIDOS 1 500 000; SUMA_PEDIDOS 226 829 306 447.46 (226.8 mil millones).

-- Paso 2.2 · Líneas: 4 por pedido en promedio
SELECT COUNT(*) AS LINEAS, COUNT(DISTINCT L_ORDERKEY) AS PEDIDOS_CON_LINEAS,
       ROUND(COUNT(*) / COUNT(DISTINCT L_ORDERKEY), 4) AS LINEAS_POR_PEDIDO
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM;
-- Esperado: LINEAS 6 001 215; PEDIDOS_CON_LINEAS 1 500 000; LINEAS_POR_PEDIDO 4.0008.

-- Paso 2.3 · Un pedido con sus líneas: O_TOTALPRICE se repite, L_EXTENDEDPRICE no
SELECT O.O_ORDERKEY, O.O_TOTALPRICE, L.L_LINENUMBER, L.L_EXTENDEDPRICE
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM L ON O.O_ORDERKEY = L.L_ORDERKEY
WHERE O.O_ORDERKEY = 1066817
ORDER BY L.L_LINENUMBER;
-- Esperado: 4 filas, todas con O_TOTALPRICE 144 930.46; L_EXTENDEDPRICE 30 964.08,
--   25 868.64, 41 592.32 y 48 703.98. Un SUM(O_TOTALPRICE) de este pedido daría 579 721.84.

-- Paso 2.3b · ¿De quién es el pedido 1066817? Del cliente 102022, el de las slides 6, 10 y 32 a 34
SELECT O_ORDERKEY, O_CUSTKEY, O_ORDERDATE, O_TOTALPRICE
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_ORDERKEY = 1066817;
-- Esperado: O_CUSTKEY 102022; O_ORDERDATE 1992-01-05; O_TOTALPRICE 144 930.46: es el primer
--   pedido del cliente 102022 (el 144 930.46 que abre el total de la slide 6 y la media
--   móvil de la slide 10). La suma de sus 4 precios de línea es 147 129.02: O_TOTALPRICE es el
--   total con descuento e impuesto, no la suma de L_EXTENDEDPRICE.

-- Paso 2.4 · La suma después del JOIN (el error de la slide) y su cociente
ALTER SESSION SET QUERY_TAG = 'EVID_S02';
SELECT COUNT(*) AS FILAS, COUNT(DISTINCT O.O_ORDERKEY) AS PEDIDOS,
       SUM(O.O_TOTALPRICE) AS SUMA_INFLADA
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM L ON O.O_ORDERKEY = L.L_ORDERKEY;
ALTER SESSION UNSET QUERY_TAG;
-- Esperado: FILAS 6 001 215; PEDIDOS 1 500 000; SUMA_INFLADA 1 134 436 101 880.19
--   (1 134.4 mil millones). Los pedidos distintos siguen siendo 1 500 000: solo se repiten.

-- Paso 2.5 · Cuántas veces: filas contra monto
SELECT ROUND(6001215 / 1500000, 4) AS VECES_EN_FILAS,
       ROUND(1134436101880.19 / 226829306447.46, 4) AS VECES_EN_MONTO;
-- Esperado: VECES_EN_FILAS 4.0008 (≈ 4.0); VECES_EN_MONTO 5.0013 (≈ 5.0, «5 veces»).

-- Paso 2.6 · Por qué 5.0 y no 4.0
-- Tras el JOIN, cada pedido aparece N veces (N = sus líneas). Filas: SUM(N) / pedidos = 4.0.
-- Monto: SUM(O_TOTALPRICE * N) / SUM(O_TOTALPRICE). Sale más alto porque N y O_TOTALPRICE
-- crecen juntos (a más líneas, más caro el pedido).
WITH N AS (SELECT L_ORDERKEY, COUNT(*) AS LINEAS
           FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM
           GROUP BY L_ORDERKEY)
SELECT ROUND(AVG(N.LINEAS), 4) AS VECES_EN_FILAS,
       ROUND(SUM(O.O_TOTALPRICE * N.LINEAS) / SUM(O.O_TOTALPRICE), 4) AS VECES_EN_MONTO,
       SUM(O.O_TOTALPRICE * N.LINEAS) AS SUMA_REPETIDA,
       ROUND(CORR(O.O_TOTALPRICE, N.LINEAS), 2) AS CORRELACION
FROM N JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O ON O.O_ORDERKEY = N.L_ORDERKEY;
-- Esperado: VECES_EN_FILAS 4.0008; VECES_EN_MONTO 5.0013; SUMA_REPETIDA 1 134 436 101 880.19
--   (igual al paso 2.4: la suma inflada es exactamente cada pedido por sus líneas);
--   CORRELACION 0.85.

-- Paso 2.6b · El precio medio del pedido crece con sus líneas, casi en proporción
WITH N AS (SELECT L_ORDERKEY, COUNT(*) AS LINEAS
           FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM
           GROUP BY L_ORDERKEY)
SELECT N.LINEAS, COUNT(*) AS PEDIDOS, ROUND(AVG(O.O_TOTALPRICE), 2) AS PRECIO_PROMEDIO
FROM N JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O ON O.O_ORDERKEY = N.L_ORDERKEY
GROUP BY N.LINEAS
ORDER BY N.LINEAS;
-- Esperado (7 filas, ~214 000 pedidos cada una; las líneas por pedido van de 1 a 7):
--   1 -> 37 722.23; 2 -> 75 613.44; 3 -> 113 354.26; 4 -> 151 395.05; 5 -> 188 828.60;
--   6 -> 226 853.68; 7 -> 264 555.64. Cada línea añade unos 37 700.
-- Con líneas de 1 a 7 en partes casi iguales, el promedio de N es 4 y el de N al cuadrado
--   es 20: 20 / 4 = 5. Por eso 5 y no 4.

-- Paso 2.7 · «Sin aviso» y «rápido»: estado y duración de la consulta del paso 2.4
SELECT EXECUTION_STATUS, ERROR_CODE, TOTAL_ELAPSED_TIME AS TOTAL_MS, EXECUTION_TIME AS EJEC_MS
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(RESULT_LIMIT => 100))
WHERE QUERY_TAG = 'EVID_S02' AND QUERY_TYPE = 'SELECT'
ORDER BY START_TIME DESC
LIMIT 1;
-- Esperado: EXECUTION_STATUS SUCCESS; ERROR_CODE vacío (NULL); EJEC_MS unas 2 décimas de
--   segundo (221 ms en la prueba); TOTAL_MS de 1 a 2 s (2 027 ms), casi todo compilación de
--   la primera vez. El motor no marca nada: el error no está en la sintaxis sino en el grano.


-- =====================================================================
-- SLIDE 3 · GROUP BY borra los pedidos a comparar
-- Afirmación en pantalla: «GROUP BY borra los pedidos a comparar; 1 500 000 quedan en
--   99 996 filas.» «Una fila por cliente; fecha y monto de cada pedido ya no están. Orden:
--   más pedidos primero y, en empate, menor cliente. Primero: 3451, con 41.»
-- Qué demuestra cada paso:
--   3.1  la consulta de la slide (limitada a 6 filas para la pantalla): 3451, 102004, 102022.
--   3.2  el número de filas que devuelve completa: 99 996, y que suman los 1 500 000 pedidos.
--   3.3  las columnas que quedan: solo cliente y conteo; fecha y monto no.
--   3.4  por qué 99 996 y no 150 000: solo 99 996 clientes han hecho pedidos.
-- =====================================================================

-- Paso 3.1 · La consulta de la slide, con LIMIT 6 (completa devuelve 99 996 filas)
SELECT O_CUSTKEY, COUNT(*) AS PEDIDOS
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
GROUP BY O_CUSTKEY
ORDER BY PEDIDOS DESC, O_CUSTKEY
LIMIT 6;
-- Esperado: 3451 (41), 102004 (41), 102022 (41), 79300 (40), 117082 (40), 122623 (40).

-- Paso 3.3 · Las columnas del resultado (se corre justo después del 3.1)
DESC RESULT LAST_QUERY_ID();
-- Esperado: dos columnas, O_CUSTKEY y PEDIDOS. No hay O_ORDERDATE ni O_TOTALPRICE.

-- Paso 3.2 · Filas que devuelve la consulta completa y pedidos que suman
SELECT COUNT(*) AS FILAS_DEL_GROUP_BY, SUM(PEDIDOS) AS PEDIDOS_QUE_SUMAN
FROM (SELECT O_CUSTKEY, COUNT(*) AS PEDIDOS
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
      GROUP BY O_CUSTKEY);
-- Esperado: FILAS_DEL_GROUP_BY 99 996; PEDIDOS_QUE_SUMAN 1 500 000.

-- Paso 3.4 · Clientes con y sin pedidos
SELECT (SELECT COUNT(*) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER) AS CLIENTES,
       (SELECT COUNT(DISTINCT O_CUSTKEY) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS)
         AS CON_PEDIDOS;
-- Esperado: CLIENTES 150 000; CON_PEDIDOS 99 996 (50 004 clientes no han pedido nada).


-- =====================================================================
-- SLIDE 4 · Los tres problemas y su síntoma medido
-- Afirmación en pantalla (texto alternativo del diagrama): «GROUP BY deja 99 996 de
--   1 500 000 filas; el promedio de promedios se desvía 6.9 %; cuatro uniones por pregunta
--   frente a una.»
-- Qué demuestra: la slide no afirma nada nuevo, enlaza tres bloques. Aquí van los dos
--   primeros síntomas en una fila; el tercero (4 uniones frente a 1) se mide en los bloques
--   24 (4 operadores Join) y 26 (1 operador Join).
--   Problema 1 -> bloque 3 · Problema 2 -> bloque 22 · Problema 3 -> bloques 24 y 26.
-- =====================================================================

-- Paso 4.1 · Síntomas 1 y 2 en una fila
WITH G AS (SELECT O_ORDERSTATUS, COUNT(*) AS N, AVG(O_TOTALPRICE) AS PROM
           FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
           GROUP BY O_ORDERSTATUS)
SELECT (SELECT COUNT(DISTINCT O_CUSTKEY) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS)
         AS FILAS_TRAS_GROUP_BY,
       (SELECT COUNT(*) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS) AS PEDIDOS,
       ROUND((AVG(PROM) - SUM(N * PROM) / SUM(N)) / (SUM(N * PROM) / SUM(N)) * 100, 1)
         AS DESVIO_PROMEDIO_DE_PROMEDIOS_PCT
FROM G;
-- Esperado: FILAS_TRAS_GROUP_BY 99 996; PEDIDOS 1 500 000; DESVIO_PROMEDIO_DE_PROMEDIOS_PCT 6.9.


-- =====================================================================
-- SLIDE 5 · Las ocho tablas de TPC-H
-- Afirmación en pantalla: «ocho tablas de un mayorista, ya cargadas en tu cuenta»; filas en
--   SF1: REGION 5, NATION 25, CUSTOMER 150 000, ORDERS 1 500 000, LINEITEM 6 001 215,
--   PART 200 000, SUPPLIER 10 000, PARTSUPP 800 000; LINEITEM por escala: SF1 6 001 215,
--   SF10 59 986 052, SF100 600 037 902. Relaciones 1:N de REGION a LINEITEM. «Normalizadas:
--   cada dato vive en una tabla, salvo O_TOTALPRICE (derivado).»
-- Qué demuestra cada paso:
--   5.1  son 8 tablas y sus filas (COUNT(*) sin filtro lee metadatos, no datos).
--   5.2  LINEITEM en SF1, SF10 y SF100.
--   5.3  las relaciones 1:N se cumplen: ninguna fila hija sin padre.
--   5.4  O_TOTALPRICE es derivado: se reconstruye desde las líneas, con impuesto.
-- =====================================================================

-- Paso 5.1 · Las tablas y sus filas (SF1)
SELECT TABLE_NAME AS TABLA, ROW_COUNT AS FILAS
FROM SNOWFLAKE_SAMPLE_DATA.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'TPCH_SF1' AND TABLE_TYPE = 'BASE TABLE'
ORDER BY ROW_COUNT;
-- Esperado: 8 filas. REGION 5; NATION 25; SUPPLIER 10 000; CUSTOMER 150 000; PART 200 000;
--   PARTSUPP 800 000; ORDERS 1 500 000; LINEITEM 6 001 215.

-- Paso 5.2 · LINEITEM en tres escalas
SELECT 'SF1' AS ESCALA, COUNT(*) AS FILAS FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM
UNION ALL SELECT 'SF10', COUNT(*) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM
UNION ALL SELECT 'SF100', COUNT(*) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.LINEITEM;
-- Esperado: SF1 6 001 215; SF10 59 986 052; SF100 600 037 902.

-- Paso 5.3 · Relaciones 1:N: filas hijas sin padre
SELECT 'NATION sin REGION' AS CHEQUEO, COUNT(*) AS FILAS_HUERFANAS
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION N
LEFT JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION R ON N.N_REGIONKEY = R.R_REGIONKEY
WHERE R.R_REGIONKEY IS NULL
UNION ALL
SELECT 'CUSTOMER sin NATION', COUNT(*)
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER C
LEFT JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION N ON C.C_NATIONKEY = N.N_NATIONKEY
WHERE N.N_NATIONKEY IS NULL
UNION ALL
SELECT 'ORDERS sin CUSTOMER', COUNT(*)
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O
LEFT JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER C ON O.O_CUSTKEY = C.C_CUSTKEY
WHERE C.C_CUSTKEY IS NULL
UNION ALL
SELECT 'LINEITEM sin ORDERS', COUNT(*)
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM L
LEFT JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O ON L.L_ORDERKEY = O.O_ORDERKEY
WHERE O.O_ORDERKEY IS NULL;
-- Esperado: las cuatro filas con 0. Cada nación tiene región, cada cliente nación, cada
--   pedido cliente y cada línea pedido: la cadena es de uno a muchos.

-- Paso 5.4 · O_TOTALPRICE es derivado: se reconstruye desde las líneas, con impuesto
WITH L AS (SELECT L_ORDERKEY,
                  SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT) * (1 + L_TAX)) AS RECONSTRUIDO
           FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM
           GROUP BY L_ORDERKEY)
SELECT COUNT(*) AS PEDIDOS,
       ROUND(MAX(ABS(O.O_TOTALPRICE - L.RECONSTRUIDO)), 2) AS DIFERENCIA_MAXIMA,
       ROUND(SUM(L.RECONSTRUIDO), 2) AS SUMA_RECONSTRUIDA,
       SUM(O.O_TOTALPRICE) AS SUMA_O_TOTALPRICE
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O
JOIN L ON O.O_ORDERKEY = L.L_ORDERKEY;
-- Esperado: PEDIDOS 1 500 000; DIFERENCIA_MAXIMA 0.11 (centavos de redondeo, por pedido);
--   SUMA_RECONSTRUIDA 226 829 357 828.87; SUMA_O_TOTALPRICE 226 829 306 447.46 (diferencia
--   de 51 381.41, 0.00002 %). Es la razón de la slide 2: O_TOTALPRICE ya contiene las líneas.


-- =====================================================================
-- SLIDE 6 · Una ventana calcula sobre un grupo sin borrar filas
-- Afirmación en pantalla: «una ventana calcula sobre un grupo sin borrar filas; los 41
--   pedidos siguen ahí.» «TOTAL_CLIENTE suma O_TOTALPRICE (total del pedido con impuesto):
--   6 273 788.41.»
-- Qué demuestra cada paso:
--   6.1  la consulta de la slide: 41 filas, cada una con el total del cliente.
--   6.2  contado: 41 filas y un solo valor de TOTAL_CLIENTE.
--   6.3  el GROUP BY equivalente devuelve 1 fila (contraste con la slide 3).
--   6.4  «con impuesto»: sumar las líneas sin impuesto da 6 039 653.63; con impuesto,
--        6 273 789.73, a 1.32 de O_TOTALPRICE (redondeo).
-- Documentación (OVER, PARTITION BY): docs.snowflake.com/en/sql-reference/functions-analytic
-- =====================================================================

-- Paso 6.1 · La consulta de la slide
SELECT O_ORDERKEY, O_ORDERDATE, O_TOTALPRICE,
       SUM(O_TOTALPRICE) OVER (PARTITION BY O_CUSTKEY) AS TOTAL_CLIENTE
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_CUSTKEY = 102022
ORDER BY O_ORDERDATE, O_ORDERKEY;
-- Esperado: 41 filas. La primera: 1066817, 1992-01-05, 144 930.46, TOTAL_CLIENTE 6 273 788.41.

-- Paso 6.2 · Cuántas filas y cuántos totales distintos
SELECT COUNT(*) AS FILAS, COUNT(DISTINCT TOTAL_CLIENTE) AS TOTALES_DISTINTOS,
       MAX(TOTAL_CLIENTE) AS TOTAL_CLIENTE
FROM (SELECT SUM(O_TOTALPRICE) OVER (PARTITION BY O_CUSTKEY) AS TOTAL_CLIENTE
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
      WHERE O_CUSTKEY = 102022);
-- Esperado: FILAS 41; TOTALES_DISTINTOS 1; TOTAL_CLIENTE 6 273 788.41.

-- Paso 6.3 · El mismo total con GROUP BY: una sola fila
SELECT O_CUSTKEY, COUNT(*) AS PEDIDOS, SUM(O_TOTALPRICE) AS TOTAL_CLIENTE
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_CUSTKEY = 102022
GROUP BY O_CUSTKEY;
-- Esperado: 1 fila: 102022, 41, 6 273 788.41.

-- Paso 6.4 · «Con impuesto»: el total del pedido contra las líneas con y sin impuesto
SELECT ROUND(SUM(L.L_EXTENDEDPRICE * (1 - L.L_DISCOUNT)), 2) AS SIN_IMPUESTO,
       ROUND(SUM(L.L_EXTENDEDPRICE * (1 - L.L_DISCOUNT) * (1 + L.L_TAX)), 2) AS CON_IMPUESTO,
       (SELECT SUM(O_TOTALPRICE) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
        WHERE O_CUSTKEY = 102022) AS O_TOTALPRICE
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM L
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O ON L.L_ORDERKEY = O.O_ORDERKEY
WHERE O.O_CUSTKEY = 102022;
-- Esperado: SIN_IMPUESTO 6 039 653.63; CON_IMPUESTO 6 273 789.73; O_TOTALPRICE 6 273 788.41.


-- =====================================================================
-- SLIDE 7 · PARTITION BY agrupa; ORDER BY convierte el total en acumulado
-- Afirmación en pantalla: tabla del cliente 102022: montos 144 930.46, 111 485.66 y
--   63 555.44; sin ORDER BY, 6 273 788.41 en las tres; con ORDER BY, 144 930.46, 256 416.12
--   y 319 971.56.
-- Qué demuestra cada paso:
--   7.1  las tres primeras filas de la tabla de la slide.
--   7.2  el acumulado termina en el total: la última fila con ORDER BY es 6 273 788.41.
-- =====================================================================

-- Paso 7.1 · Las dos ventanas lado a lado, tres primeras filas
SELECT O_ORDERKEY, O_ORDERDATE, O_TOTALPRICE,
       SUM(O_TOTALPRICE) OVER (PARTITION BY O_CUSTKEY) AS SIN_ORDER_BY,
       SUM(O_TOTALPRICE) OVER (PARTITION BY O_CUSTKEY
                               ORDER BY O_ORDERDATE, O_ORDERKEY) AS CON_ORDER_BY
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_CUSTKEY = 102022
ORDER BY O_ORDERDATE, O_ORDERKEY
LIMIT 3;
-- Esperado: (144 930.46; 6 273 788.41; 144 930.46), (111 485.66; 6 273 788.41; 256 416.12),
--   (63 555.44; 6 273 788.41; 319 971.56).

-- Paso 7.2 · La última fila del acumulado es el total
SELECT O_ORDERKEY, O_ORDERDATE, O_TOTALPRICE,
       SUM(O_TOTALPRICE) OVER (PARTITION BY O_CUSTKEY
                               ORDER BY O_ORDERDATE, O_ORDERKEY) AS CON_ORDER_BY
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_CUSTKEY = 102022
ORDER BY O_ORDERDATE DESC, O_ORDERKEY DESC
LIMIT 1;
-- Esperado: 1 fila (el último pedido del cliente) con CON_ORDER_BY 6 273 788.41.


-- =====================================================================
-- SLIDE 8 · ROW_NUMBER, RANK y DENSE_RANK con empates
-- Afirmación en pantalla: «Ordenados por pedidos y cliente, tres con 41 pedidos empatan:
--   RANK salta, DENSE_RANK no, ROW_NUMBER nunca repite.» Tabla: 3451, 102004, 102022 con 41
--   (RN 1, 2, 3; RK 1, 1, 1; DR 1, 1, 1) y 79300 con 40 (RN 4; RK 4; DR 2).
-- Qué demuestra: la tabla de la slide, con O_CUSTKEY como desempate de ROW_NUMBER (sin él, el
--   orden entre empates no está garantizado y puede variar entre corridas; ver la
--   documentación de ROW_NUMBER, docs.snowflake.com/en/sql-reference/functions/row_number).
-- =====================================================================

-- Paso 8.1 · Las tres funciones sobre el conteo de pedidos por cliente
WITH C AS (SELECT O_CUSTKEY, COUNT(*) AS PEDIDOS
           FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
           GROUP BY O_CUSTKEY)
SELECT O_CUSTKEY AS CLIENTE, PEDIDOS,
       ROW_NUMBER() OVER (ORDER BY PEDIDOS DESC, O_CUSTKEY) AS RN,
       RANK() OVER (ORDER BY PEDIDOS DESC) AS RK,
       DENSE_RANK() OVER (ORDER BY PEDIDOS DESC) AS DR
FROM C
ORDER BY RN
LIMIT 6;
-- Columnas: RN = ROW_NUMBER, RK = RANK, DR = DENSE_RANK.
-- Esperado: 3451 (41; 1, 1, 1); 102004 (41; 2, 1, 1); 102022 (41; 3, 1, 1);
--   79300 (40; 4, 4, 2); 117082 (40; 5, 4, 2); 122623 (40; 6, 4, 2). Las cuatro primeras
--   son las filas de la slide. RANK salta de 1 a 4; DENSE_RANK pasa de 1 a 2.


-- =====================================================================
-- SLIDE 9 · LAG: los días entre pedidos son una resta
-- Afirmación en pantalla: «Cliente 102022: el primer pedido da NULL, no tiene anterior. Los
--   siguientes: 49, 44 y 32 días. La mayor pausa es de 227. LEAD mira hacia adelante.»
-- Qué demuestra cada paso:
--   9.1  la consulta de la slide, con LEAD al lado: NULL, 49, 44, 32; y LEAD desplazado.
--   9.2  41 filas, 40 con anterior, mayor pausa 227, dos pausas de 0 días.
--   9.3  el pedido de la pausa mayor y su anterior.
-- =====================================================================

-- Paso 9.1 · LAG (la slide) y LEAD (la última frase de la slide), primeras 5 filas
SELECT O_ORDERKEY, O_ORDERDATE,
       DATEDIFF('day',
                LAG(O_ORDERDATE) OVER (ORDER BY O_ORDERDATE, O_ORDERKEY),
                O_ORDERDATE) AS DIAS_DESDE_ANTERIOR,
       DATEDIFF('day',
                O_ORDERDATE,
                LEAD(O_ORDERDATE) OVER (ORDER BY O_ORDERDATE, O_ORDERKEY)) AS DIAS_HASTA_SIGUIENTE
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_CUSTKEY = 102022
ORDER BY O_ORDERDATE, O_ORDERKEY
LIMIT 5;
-- Esperado: DIAS_DESDE_ANTERIOR NULL, 49, 44, 32, 3; DIAS_HASTA_SIGUIENTE 49, 44, 32, 3, 44.
--   El LEAD de cada fila es el LAG de la siguiente.

-- Paso 9.2 · Resumen de los 41 pedidos
WITH X AS (SELECT O_ORDERKEY, O_ORDERDATE,
                  DATEDIFF('day',
                           LAG(O_ORDERDATE) OVER (ORDER BY O_ORDERDATE, O_ORDERKEY),
                           O_ORDERDATE) AS DIAS
           FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
           WHERE O_CUSTKEY = 102022)
SELECT COUNT(*) AS PEDIDOS, COUNT(DIAS) AS CON_ANTERIOR, MAX(DIAS) AS MAYOR_PAUSA,
       COUNT_IF(DIAS = 0) AS PAUSAS_DE_CERO
FROM X;
-- Esperado: PEDIDOS 41; CON_ANTERIOR 40; MAYOR_PAUSA 227; PAUSAS_DE_CERO 2.

-- Paso 9.3 · El pedido de la mayor pausa
SELECT O_ORDERKEY, O_ORDERDATE, DIAS_DESDE_ANTERIOR, FECHA_ANTERIOR
FROM (SELECT O_ORDERKEY, O_ORDERDATE,
             LAG(O_ORDERDATE) OVER (ORDER BY O_ORDERDATE, O_ORDERKEY) AS FECHA_ANTERIOR,
             DATEDIFF('day', FECHA_ANTERIOR, O_ORDERDATE) AS DIAS_DESDE_ANTERIOR
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
      WHERE O_CUSTKEY = 102022)
ORDER BY DIAS_DESDE_ANTERIOR DESC NULLS LAST
LIMIT 1;
-- Esperado: pedido 1804518, 1993-12-24, 227 días; fecha anterior 1993-05-11.


-- =====================================================================
-- SLIDE 10 · El marco: media móvil de tres pedidos, ROWS contra RANGE
-- Afirmación en pantalla: «Cada pedido promedia sus 2 anteriores y él mismo: 144 930.46,
--   128 208.06, 106 657.19. Sin marco explícito rige RANGE: dos pedidos del mismo día
--   reciben el mismo valor.»
-- Qué demuestra cada paso:
--   10.1  la media móvil de la slide, comparada con el promedio calculado a mano con LAG.
--   10.2  los dos pedidos del 1994-12-15: sin marco (RANGE) reciben el mismo promedio; con
--         ROWS, no.
-- Documentación: el marco por defecto con ORDER BY es RANGE BETWEEN UNBOUNDED PRECEDING AND
--   CURRENT ROW (docs.snowflake.com/en/sql-reference/functions-window-syntax).
-- =====================================================================

-- Paso 10.1 · Media móvil de la slide y su cálculo manual
SELECT O_ORDERKEY, O_ORDERDATE, O_TOTALPRICE,
       AVG(O_TOTALPRICE) OVER (
         ORDER BY O_ORDERDATE, O_ORDERKEY
         ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS MEDIA_MOVIL_3,
       (O_TOTALPRICE
        + LAG(O_TOTALPRICE, 1) OVER (ORDER BY O_ORDERDATE, O_ORDERKEY)
        + LAG(O_TOTALPRICE, 2) OVER (ORDER BY O_ORDERDATE, O_ORDERKEY)) / 3 AS A_MANO
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_CUSTKEY = 102022
ORDER BY O_ORDERDATE, O_ORDERKEY
LIMIT 4;
-- Esperado: MEDIA_MOVIL_3 144 930.46; 128 208.06; 106 657.19; 100 712.37. A_MANO es NULL en las
--   dos primeras filas (no hay 2 anteriores) y 106 657.19 y 100 712.37 en las otras: coincide.
--   Las dos primeras promedian solo las filas que existen: (144 930.46 + 111 485.66) / 2.

-- Paso 10.2 · Sin marco explícito (RANGE) frente a ROWS, pedidos del mismo día
SELECT O_ORDERKEY, O_ORDERDATE, PROM_SIN_MARCO, PROM_ROWS
FROM (SELECT O_ORDERKEY, O_ORDERDATE,
             ROUND(AVG(O_TOTALPRICE) OVER (ORDER BY O_ORDERDATE), 2) AS PROM_SIN_MARCO,
             ROUND(AVG(O_TOTALPRICE) OVER (
               ORDER BY O_ORDERDATE, O_ORDERKEY
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 2) AS PROM_ROWS
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
      WHERE O_CUSTKEY = 102022)
WHERE O_ORDERKEY IN (562371, 3008738)
ORDER BY O_ORDERKEY;
-- Esperado: 562371 y 3008738 (ambos 1994-12-15): PROM_SIN_MARCO 148 599.62 en los dos;
--   PROM_ROWS 157 314.49 y 148 599.62. Los pedidos del mismo día comparten valor con RANGE.


-- =====================================================================
-- SLIDE 11 · Toda ventana tiene costo (SF10, X-Small)
-- Afirmación en pantalla: «Con ORDER BY, una ventana tardó unas 4 veces más que sin él y
--   derramó 215 MB (SF10).» Diagrama: GROUP BY mediana 0.28 s (rango 0.26 a 0.29), Aggregate 79 a
--   96 % del tiempo, sin derrame; ventana sin ORDER BY 0.43 s (0.39 a 0.45), WindowFunction
--   88 a 93 %, sin derrame; ventana con ORDER BY 1.76 s (1.63 a 1.87), WindowFunction 81 a
--   98 %, derrame a disco local de 215 MB. Escala SF10, 15 M de filas, 3 corridas, caché
--   desactivada. «Derrame: lo que no cabe en memoria se escribe a disco local.»
-- Qué demuestra cada paso:
--   11.1  las tres consultas, tres corridas cada una (cada grupo con su QUERY_TAG).
--   11.2  tiempo de ejecución por consulta: mediana, mínimo y máximo de las 3 corridas.
--   11.3  el cociente entre la consulta con ORDER BY y la que no lo tiene (las «4 veces»).
--   11.4  el perfil de la última corrida de cada consulta: operador, porcentaje y derrame.
-- Costo: SF10, X-Small, unos 60 s de ejecución en total (0.02 créditos). El tiempo varía
--   entre corridas y cuentas; el orden de magnitud (≈ 4 veces) y el derrame de la tercera
--   consulta, no. Definición de derrame:
--   docs.snowflake.com/en/user-guide/ui-query-profile (Queries Too Large to Fit in Memory).
-- Nota: en la tercera consulta, la suma es acumulada, no total; su CHECK_SUMA es distinto.
-- =====================================================================

-- Paso 11.1a · GROUP BY (3 corridas)
ALTER SESSION SET QUERY_TAG = 'EVID_S11_A_GROUP_BY';
SELECT COUNT(*) AS FILAS_SALIDA, SUM(S) AS CHECK_SUMA
FROM (SELECT O_CUSTKEY, SUM(O_TOTALPRICE) AS S
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS
      GROUP BY O_CUSTKEY);
SELECT COUNT(*) AS FILAS_SALIDA, SUM(S) AS CHECK_SUMA
FROM (SELECT O_CUSTKEY, SUM(O_TOTALPRICE) AS S
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS
      GROUP BY O_CUSTKEY);
SELECT COUNT(*) AS FILAS_SALIDA, SUM(S) AS CHECK_SUMA
FROM (SELECT O_CUSTKEY, SUM(O_TOTALPRICE) AS S
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS
      GROUP BY O_CUSTKEY);
SET Q11A = LAST_QUERY_ID();
-- Esperado (las 3 corridas): FILAS_SALIDA 999 982; CHECK_SUMA 2 266 298 190 748.43.

-- Paso 11.1b · Ventana sin ORDER BY (3 corridas)
ALTER SESSION SET QUERY_TAG = 'EVID_S11_B_SIN_ORDER_BY';
SELECT COUNT(*) AS FILAS_SALIDA, SUM(W) AS CHECK_SUMA
FROM (SELECT SUM(O_TOTALPRICE) OVER (PARTITION BY O_CUSTKEY) AS W
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS);
SELECT COUNT(*) AS FILAS_SALIDA, SUM(W) AS CHECK_SUMA
FROM (SELECT SUM(O_TOTALPRICE) OVER (PARTITION BY O_CUSTKEY) AS W
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS);
SELECT COUNT(*) AS FILAS_SALIDA, SUM(W) AS CHECK_SUMA
FROM (SELECT SUM(O_TOTALPRICE) OVER (PARTITION BY O_CUSTKEY) AS W
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS);
SET Q11B = LAST_QUERY_ID();
-- Esperado (las 3 corridas): FILAS_SALIDA 15 000 000; CHECK_SUMA 40 015 026 117 947.15.

-- Paso 11.1c · Ventana con ORDER BY (3 corridas)
ALTER SESSION SET QUERY_TAG = 'EVID_S11_C_CON_ORDER_BY';
SELECT COUNT(*) AS FILAS_SALIDA, SUM(W) AS CHECK_SUMA
FROM (SELECT SUM(O_TOTALPRICE) OVER (PARTITION BY O_CUSTKEY ORDER BY O_ORDERDATE) AS W
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS);
SELECT COUNT(*) AS FILAS_SALIDA, SUM(W) AS CHECK_SUMA
FROM (SELECT SUM(O_TOTALPRICE) OVER (PARTITION BY O_CUSTKEY ORDER BY O_ORDERDATE) AS W
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS);
SELECT COUNT(*) AS FILAS_SALIDA, SUM(W) AS CHECK_SUMA
FROM (SELECT SUM(O_TOTALPRICE) OVER (PARTITION BY O_CUSTKEY ORDER BY O_ORDERDATE) AS W
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS);
SET Q11C = LAST_QUERY_ID();
ALTER SESSION UNSET QUERY_TAG;
-- Esperado (las 3 corridas): FILAS_SALIDA 15 000 000; CHECK_SUMA 21 146 864 883 921.01
--   (acumulada: distinta de la anterior, pero la comparación de costo sigue siendo válida).

-- Paso 11.2 · Tiempo de ejecución por consulta, de las 3 corridas
SELECT QUERY_TAG AS CONSULTA, COUNT(*) AS CORRIDAS,
       ROUND(MEDIAN(EXECUTION_TIME) / 1000, 2) AS EJEC_MEDIANA_S,
       ROUND(MIN(EXECUTION_TIME) / 1000, 2) AS EJEC_MIN_S,
       ROUND(MAX(EXECUTION_TIME) / 1000, 2) AS EJEC_MAX_S
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(RESULT_LIMIT => 200))
WHERE QUERY_TAG LIKE 'EVID_S11_%' AND QUERY_TYPE = 'SELECT'
GROUP BY QUERY_TAG
ORDER BY QUERY_TAG;
-- Esperado (X-Small; tres mediciones, 8 y 9 nov.): A_GROUP_BY 0.26 a 0.29 s (en una de las
--   mediciones, una corrida tardó 0.67 s); B_SIN_ORDER_BY 0.39 a 0.45 s; C_CON_ORDER_BY 1.63
--   a 1.87 s (medianas 1.64, 1.76 y 1.78). CORRIDAS 3 en cada fila.

-- Paso 11.3 · El cociente: ventana con ORDER BY frente a ventana sin él
WITH H AS (SELECT QUERY_TAG AS T, MEDIAN(EXECUTION_TIME) / 1000 AS S
           FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(RESULT_LIMIT => 200))
           WHERE QUERY_TAG LIKE 'EVID_S11_%' AND QUERY_TYPE = 'SELECT'
           GROUP BY QUERY_TAG)
SELECT ROUND(MAX(IFF(T = 'EVID_S11_B_SIN_ORDER_BY', S, NULL)), 2) AS SIN_ORDER_BY_S,
       ROUND(MAX(IFF(T = 'EVID_S11_C_CON_ORDER_BY', S, NULL)), 2) AS CON_ORDER_BY_S,
       ROUND(MAX(IFF(T = 'EVID_S11_C_CON_ORDER_BY', S, NULL))
             / MAX(IFF(T = 'EVID_S11_B_SIN_ORDER_BY', S, NULL)), 1) AS VECES
FROM H;
-- Esperado: VECES entre 4.1 y 4.6: 4.1 el 8 nov. (1.76 / 0.43) y 4.2 y 4.6 el 9 nov.
--   (1.64 / 0.39 y 1.78 / 0.39). «4 veces» es el orden de magnitud, no un valor fijo.

-- Paso 11.4 · Perfil de la última corrida de cada consulta: operador, % del tiempo y derrame
SELECT 'A GROUP BY' AS CONSULTA, OPERATOR_TYPE,
       ROUND(EXECUTION_TIME_BREAKDOWN:overall_percentage::FLOAT * 100, 1) AS PCT_DEL_TIEMPO,
       COALESCE(OPERATOR_STATISTICS:spilling:bytes_spilled_local_storage::NUMBER, 0)
         AS DERRAME_LOCAL_BYTES
FROM TABLE(GET_QUERY_OPERATOR_STATS($Q11A))
WHERE OPERATOR_TYPE = 'Aggregate'
UNION ALL
SELECT 'B SIN ORDER BY', OPERATOR_TYPE,
       ROUND(EXECUTION_TIME_BREAKDOWN:overall_percentage::FLOAT * 100, 1),
       COALESCE(OPERATOR_STATISTICS:spilling:bytes_spilled_local_storage::NUMBER, 0)
FROM TABLE(GET_QUERY_OPERATOR_STATS($Q11B))
WHERE OPERATOR_TYPE = 'WindowFunction'
UNION ALL
SELECT 'C CON ORDER BY', OPERATOR_TYPE,
       ROUND(EXECUTION_TIME_BREAKDOWN:overall_percentage::FLOAT * 100, 1),
       COALESCE(OPERATOR_STATISTICS:spilling:bytes_spilled_local_storage::NUMBER, 0)
FROM TABLE(GET_QUERY_OPERATOR_STATS($Q11C))
WHERE OPERATOR_TYPE = 'WindowFunction';
-- Esperado: A: dos filas Aggregate (la del GROUP BY y la del COUNT/SUM exterior); la mayor
--   entre 79 y 96 % del tiempo (78.9 y 83.3 el 9 nov.), derrame 0. B: WindowFunction entre 88
--   y 93 % (88.5), derrame 0. C: WindowFunction entre 81 y 98 % (98.5 y 97.1),
--   DERRAME_LOCAL_BYTES de unos 215 000 000 (215 093 248 y 215 085 056 el 9 nov.;
--   214 941 696 a 215 179 264 el 8 nov.): los «215 MB».


-- =====================================================================
-- SLIDES 12 a 16 · Logística: Lab 3A, parada AWS, make doctor
-- No hay consulta para estas slides: afirman procedimientos, no datos. Lo verificable, con su
-- fuente:
-- Slide 12  «Lab 3A: con cinco ventanas comparas pedidos sin perder ninguno»: los cinco
--   ejercicios obligatorios son EJ1 a EJ5; la meta es «5 de 5» en lab3a_verificacion.sql
--   (RESUMEN). Se comprueba corriendo esa verificación.
-- Slide 13  tabla Snowsight contra Code Editor: criterio de diseño, no medible.
-- Slide 14  «make doctor comprueba Snowflake y AWS»: scripts/doctor.sh (secciones «AWS» y
--   «Snowflake», con aws sts get-caller-identity y snow connection test). La llave privada no
--   sale del Code Editor: docs/guia.md, pasos 7 y 8.
-- Slide 15  Run space, clonar el fork, prompt ~/bigdata$: docs/guia.md, pasos 5.2 y 6.
-- Slide 16  «Conexión configurada» (scripts/snowflake-conexion.sh:174), «Setup completado»
--   (scripts/setup.sh:97) y «Diagnóstico sin fallos» (scripts/doctor.sh:84): son los mensajes
--   literales de esos scripts.
-- =====================================================================


-- =====================================================================
-- SLIDES 17 y 18 · WHERE no filtra ventanas
-- Afirmación en pantalla (17): «El top-3 del Lab 3A salió anidado: una consulta dentro de
--   otra. ¿Cómo se filtra una ventana sin anidar?»
-- Afirmación en pantalla (18): «Filtrar una ventana obliga a anidar, porque WHERE va antes.
--   Da error. Orden de evaluación: FROM, WHERE, GROUP BY, HAVING, ventanas, QUALIFY,
--   DISTINCT, ORDER BY, LIMIT. En WHERE la ventana todavía no existe.»
-- Qué demuestra cada paso:
--   18.1  la consulta de la slide falla con el código 002063 (error atrapado y mostrado como
--         texto para no cortar la hoja).
--   18.2  la forma anidada, la que usó el Lab 3A, sí funciona y da el top-3 (slide 17).
--   18.3  el orden de evaluación: WHERE se aplica antes de numerar las filas; QUALIFY, después.
-- Documentación del orden de evaluación: docs.snowflake.com/en/sql-reference/constructs/qualify
-- =====================================================================

-- Paso 18.1 · La consulta de la slide falla (se atrapa el error para poder mostrarlo)
EXECUTE IMMEDIATE $$
BEGIN
  EXECUTE IMMEDIATE 'SELECT O_CUSTKEY, O_ORDERKEY, O_TOTALPRICE,
       ROW_NUMBER() OVER (PARTITION BY O_CUSTKEY
                          ORDER BY O_TOTALPRICE DESC) AS RN
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE RN <= 3';
  RETURN 'sin error';
EXCEPTION
  WHEN OTHER THEN
    RETURN 'SQLCODE ' || SQLCODE || ' | SQLSTATE ' || SQLSTATE || ' | ' || SQLERRM;
END;
$$;
-- Esperado: «SQLCODE 2063 | SQLSTATE 42601 | SQL compilation error: Window function
--   [ROW_NUMBER() OVER (PARTITION BY ORDERS.O_CUSTKEY ORDER BY ORDERS.O_TOTALPRICE DESC
--   NULLS FIRST)] appears outside of SELECT, QUALIFY, and ORDER BY clauses.»
--   Para verlo como error rojo, pega solo la consulta de la slide 18 en otra hoja.

-- Paso 18.2 · La salida anidada (Lab 3A) sí funciona: el filtro va afuera de la ventana
SELECT COUNT(*) AS FILAS, COUNT(DISTINCT O_CUSTKEY) AS CLIENTES
FROM (SELECT O_CUSTKEY, O_ORDERKEY, O_TOTALPRICE,
             ROW_NUMBER() OVER (PARTITION BY O_CUSTKEY
                                ORDER BY O_TOTALPRICE DESC, O_ORDERKEY) AS RN
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS)
WHERE RN <= 3;
-- Esperado: FILAS 299 831; CLIENTES 99 996 (mismas cifras que con QUALIFY en el bloque 19).

-- Paso 18.3 · Orden de evaluación: el mismo filtro (precio mayor de 400 000) antes o después
-- Con WHERE se filtra primero y la ventana numera solo las filas que quedan; con QUALIFY se
-- numera toda la tabla y después se filtra: los números de fila llegan hasta 1.5 M.
SELECT 'WHERE (antes de la ventana)' AS FILTRO, MAX(RN) AS RN_MAXIMO, COUNT(*) AS FILAS
FROM (SELECT ROW_NUMBER() OVER (ORDER BY O_ORDERKEY) AS RN
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
      WHERE O_TOTALPRICE > 400000)
UNION ALL
SELECT 'QUALIFY (después de la ventana)', MAX(RN), COUNT(*)
FROM (SELECT ROW_NUMBER() OVER (ORDER BY O_ORDERKEY) AS RN
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
      QUALIFY O_TOTALPRICE > 400000);
-- Esperado: WHERE: RN_MAXIMO 3 590 y FILAS 3 590 (numeró solo los pedidos filtrados);
--   QUALIFY: RN_MAXIMO 1 499 920 y FILAS 3 590 (numeró los 1 500 000 y luego filtró).


-- =====================================================================
-- SLIDE 19 · QUALIFY filtra después de calcular la ventana
-- Afirmación en pantalla: «Devuelve 299 831 filas: hasta 3 pedidos por cliente, porque
--   algunos clientes tienen menos. O_ORDERKEY desempata, porque ROW_NUMBER no fija el orden
--   entre empates.»
-- Qué demuestra cada paso:
--   19.1  la consulta de la slide, para un cliente (3 filas de 41) y contada para todos.
--   19.2  por qué 299 831 y no 3 x 99 996 = 299 988: 17 clientes tienen 1 pedido y 123 tienen 2.
--   19.3  el desempate: en estos datos no hay empates de precio dentro de un cliente, así que
--         O_ORDERKEY es una precaución (la documentación no fija el orden entre empates).
-- Documentación: docs.snowflake.com/en/sql-reference/functions/row_number
-- =====================================================================

-- Paso 19.1a · La consulta de la slide, para un solo cliente (completa devuelve 299 831 filas)
SELECT O_CUSTKEY, O_ORDERKEY, O_TOTALPRICE
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_CUSTKEY = 102022
QUALIFY ROW_NUMBER() OVER (
           PARTITION BY O_CUSTKEY
           ORDER BY O_TOTALPRICE DESC, O_ORDERKEY) <= 3
ORDER BY O_CUSTKEY, O_TOTALPRICE DESC;
-- Esperado: 3 filas del cliente 102022, las de mayor O_TOTALPRICE de sus 41 pedidos.

-- Paso 19.1b · La consulta de la slide, contada para todos los clientes
SELECT COUNT(*) AS FILAS, COUNT(DISTINCT O_CUSTKEY) AS CLIENTES
FROM (SELECT O_CUSTKEY, O_ORDERKEY, O_TOTALPRICE
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
      QUALIFY ROW_NUMBER() OVER (
                 PARTITION BY O_CUSTKEY
                 ORDER BY O_TOTALPRICE DESC, O_ORDERKEY) <= 3);
-- Esperado: FILAS 299 831; CLIENTES 99 996.

-- Paso 19.2 · Cuántas filas aporta cada cliente al top-3
WITH P AS (SELECT O_CUSTKEY, COUNT(*) AS PEDIDOS
           FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
           GROUP BY O_CUSTKEY)
SELECT LEAST(PEDIDOS, 3) AS FILAS_EN_EL_TOP3, COUNT(*) AS CLIENTES,
       SUM(LEAST(PEDIDOS, 3)) AS FILAS
FROM P
GROUP BY LEAST(PEDIDOS, 3)
ORDER BY 1;
-- Esperado: 1 -> 17 clientes, 17 filas; 2 -> 123 clientes, 246 filas; 3 -> 99 856 clientes,
--   299 568 filas. Suman 99 996 clientes y 299 831 filas.

-- Paso 19.3 · ¿Hay empates de precio dentro de un cliente?
SELECT COUNT(*) AS PARES_CLIENTE_PRECIO_REPETIDOS
FROM (SELECT O_CUSTKEY, O_TOTALPRICE
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
      GROUP BY O_CUSTKEY, O_TOTALPRICE
      HAVING COUNT(*) > 1);
-- Esperado: 0. Aquí O_ORDERKEY no cambia el resultado; se deja porque ROW_NUMBER no garantiza
--   el orden entre empates y otro conjunto de datos podría tenerlos.


-- =====================================================================
-- SLIDE 20 · Una CTE nombra cada paso
-- Afirmación en pantalla: «CTE: consulta con nombre, no guarda datos. por_cliente deja
--   99 996 filas; la unión con CUSTOMER suma PEDIDOS por segmento: 297 453 en AUTOMOBILE.»
-- Qué demuestra cada paso:
--   20.1  la consulta de la slide: 5 segmentos, AUTOMOBILE 297 453; suman 1 500 000.
--   20.2  el primer paso por separado: por_cliente deja 99 996 filas.
--   20.3  «no guarda datos»: fuera de la consulta, el nombre por_cliente no existe.
-- =====================================================================

-- Paso 20.1 · La consulta de la slide
WITH por_cliente AS (
  SELECT O_CUSTKEY, COUNT(*) AS PEDIDOS
  FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
  GROUP BY O_CUSTKEY)
SELECT C.C_MKTSEGMENT, SUM(P.PEDIDOS) AS PEDIDOS
FROM por_cliente P JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER C
  ON C.C_CUSTKEY = P.O_CUSTKEY
GROUP BY C.C_MKTSEGMENT
ORDER BY C.C_MKTSEGMENT;
-- Esperado: AUTOMOBILE 297 453; BUILDING 303 959; FURNITURE 299 461; HOUSEHOLD 300 147;
--   MACHINERY 298 980. Suman 1 500 000.

-- Paso 20.2 · El primer paso por separado
WITH por_cliente AS (
  SELECT O_CUSTKEY, COUNT(*) AS PEDIDOS
  FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
  GROUP BY O_CUSTKEY)
SELECT COUNT(*) AS FILAS FROM por_cliente;
-- Esperado: FILAS 99 996.

-- Paso 20.3 · La CTE no existe fuera de su consulta (error atrapado y mostrado como texto)
EXECUTE IMMEDIATE $$
BEGIN
  EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM por_cliente';
  RETURN 'sin error';
EXCEPTION
  WHEN OTHER THEN
    RETURN 'SQLCODE ' || SQLCODE || ' | ' || SQLERRM;
END;
$$;
-- Esperado: «SQLCODE 2003 | SQL compilation error: Object 'POR_CLIENTE' does not exist or not
--   authorized...». Nada se guardó.


-- =====================================================================
-- SLIDE 21 · Agregar antes de unir (SF1 y SF10)
-- Afirmación en pantalla: «El 5× de la slide 2 se evita agregando las líneas antes de unir; la
--   ejecución no cambió.» Dos consultas lado a lado (unir primero; agregar en una CTE) con:
--   total, SF1, 1 134.4 mil millones (× 5.0) contra 226.8 exacto; filas del Join LINEITEM-ORDERS
--   (SF10, X-Small), 60 M contra 15 M; ejecución 0.9 a 1.3 s contra 1.1 a 1.2 s.
-- Qué demuestra cada paso:
--   21.1  SF1: unir primero da 6 001 215 filas y 1 134.4 mil millones; agregar primero,
--         1 500 000 filas y 226.8 mil millones (el valor real).
--   21.2  SF10, por cliente, con las dos medidas: tres corridas de cada forma.
--   21.3  filas que entrega el operador Join de cada forma (59 986 052 contra 15 000 000).
--   21.4  tiempo de ejecución de cada forma: casi igual.
--   21.5  el total de O_TOTALPRICE de cada forma frente al real: 5.0 contra 1.0.
-- Costo: SF10, X-Small, unos 30 s de ejecución (0.01 créditos).
-- =====================================================================

-- Paso 21.1a · SF1, unir primero
SELECT COUNT(*) AS FILAS, SUM(O.O_TOTALPRICE) AS S
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM L ON O.O_ORDERKEY = L.L_ORDERKEY;
-- Esperado: FILAS 6 001 215; S 1 134 436 101 880.19.

-- Paso 21.1b · SF1, agregar primero
WITH L AS (SELECT L_ORDERKEY FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM GROUP BY 1)
SELECT COUNT(*) AS FILAS, SUM(O.O_TOTALPRICE) AS S
FROM L JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O ON O.O_ORDERKEY = L.L_ORDERKEY;
-- Esperado: FILAS 1 500 000; S 226 829 306 447.46.

-- Paso 21.2a · SF10, por cliente, unir y agregar (3 corridas)
ALTER SESSION SET QUERY_TAG = 'EVID_S21_UNIR_Y_AGREGAR';
SELECT COUNT(*) AS CLIENTES, SUM(S_LINEAS) AS SUMA_LINEAS, SUM(S_PEDIDO) AS SUMA_PEDIDO
FROM (SELECT O.O_CUSTKEY, SUM(L.L_EXTENDEDPRICE) AS S_LINEAS, SUM(O.O_TOTALPRICE) AS S_PEDIDO
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS O
      JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM L ON O.O_ORDERKEY = L.L_ORDERKEY
      GROUP BY O.O_CUSTKEY);
SELECT COUNT(*) AS CLIENTES, SUM(S_LINEAS) AS SUMA_LINEAS, SUM(S_PEDIDO) AS SUMA_PEDIDO
FROM (SELECT O.O_CUSTKEY, SUM(L.L_EXTENDEDPRICE) AS S_LINEAS, SUM(O.O_TOTALPRICE) AS S_PEDIDO
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS O
      JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM L ON O.O_ORDERKEY = L.L_ORDERKEY
      GROUP BY O.O_CUSTKEY);
SELECT COUNT(*) AS CLIENTES, SUM(S_LINEAS) AS SUMA_LINEAS, SUM(S_PEDIDO) AS SUMA_PEDIDO
FROM (SELECT O.O_CUSTKEY, SUM(L.L_EXTENDEDPRICE) AS S_LINEAS, SUM(O.O_TOTALPRICE) AS S_PEDIDO
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS O
      JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM L ON O.O_ORDERKEY = L.L_ORDERKEY
      GROUP BY O.O_CUSTKEY);
SET Q21U = LAST_QUERY_ID();
-- Esperado (las 3 corridas): CLIENTES 999 982; SUMA_LINEAS 2 293 813 156 773.36;
--   SUMA_PEDIDO 11 329 533 808 416.01.

-- Paso 21.2b · SF10, por cliente, agregar y unir (3 corridas)
ALTER SESSION SET QUERY_TAG = 'EVID_S21_AGREGAR_Y_UNIR';
SELECT COUNT(*) AS CLIENTES, SUM(S_LINEAS) AS SUMA_LINEAS, SUM(S_PEDIDO) AS SUMA_PEDIDO
FROM (WITH L AS (SELECT L_ORDERKEY, SUM(L_EXTENDEDPRICE) AS S_LINEAS
                 FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM
                 GROUP BY L_ORDERKEY)
      SELECT O.O_CUSTKEY, SUM(L.S_LINEAS) AS S_LINEAS, SUM(O.O_TOTALPRICE) AS S_PEDIDO
      FROM L JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS O ON O.O_ORDERKEY = L.L_ORDERKEY
      GROUP BY O.O_CUSTKEY);
SELECT COUNT(*) AS CLIENTES, SUM(S_LINEAS) AS SUMA_LINEAS, SUM(S_PEDIDO) AS SUMA_PEDIDO
FROM (WITH L AS (SELECT L_ORDERKEY, SUM(L_EXTENDEDPRICE) AS S_LINEAS
                 FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM
                 GROUP BY L_ORDERKEY)
      SELECT O.O_CUSTKEY, SUM(L.S_LINEAS) AS S_LINEAS, SUM(O.O_TOTALPRICE) AS S_PEDIDO
      FROM L JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS O ON O.O_ORDERKEY = L.L_ORDERKEY
      GROUP BY O.O_CUSTKEY);
SELECT COUNT(*) AS CLIENTES, SUM(S_LINEAS) AS SUMA_LINEAS, SUM(S_PEDIDO) AS SUMA_PEDIDO
FROM (WITH L AS (SELECT L_ORDERKEY, SUM(L_EXTENDEDPRICE) AS S_LINEAS
                 FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM
                 GROUP BY L_ORDERKEY)
      SELECT O.O_CUSTKEY, SUM(L.S_LINEAS) AS S_LINEAS, SUM(O.O_TOTALPRICE) AS S_PEDIDO
      FROM L JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS O ON O.O_ORDERKEY = L.L_ORDERKEY
      GROUP BY O.O_CUSTKEY);
SET Q21A = LAST_QUERY_ID();
ALTER SESSION UNSET QUERY_TAG;
-- Esperado (las 3 corridas): CLIENTES 999 982; SUMA_LINEAS 2 293 813 156 773.36 (igual que
--   arriba: la medida de las líneas no se infla); SUMA_PEDIDO 2 266 298 190 748.43.

-- Paso 21.3 · Filas que entrega el operador Join en la última corrida de cada forma
SELECT 'Unir y agregar' AS FORMA, OPERATOR_STATISTICS:output_rows::NUMBER AS FILAS_DEL_JOIN
FROM TABLE(GET_QUERY_OPERATOR_STATS($Q21U))
WHERE OPERATOR_TYPE = 'Join'
UNION ALL
SELECT 'Agregar y unir', OPERATOR_STATISTICS:output_rows::NUMBER
FROM TABLE(GET_QUERY_OPERATOR_STATS($Q21A))
WHERE OPERATOR_TYPE = 'Join';
-- Esperado: Unir y agregar 59 986 052 (60 M); Agregar y unir 15 000 000 (15 M).

-- Paso 21.4 · Tiempo de ejecución de las 3 corridas de cada forma
SELECT QUERY_TAG AS FORMA, COUNT(*) AS CORRIDAS,
       ROUND(MIN(EXECUTION_TIME) / 1000, 2) AS EJEC_MIN_S,
       ROUND(MAX(EXECUTION_TIME) / 1000, 2) AS EJEC_MAX_S
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(RESULT_LIMIT => 200))
WHERE QUERY_TAG LIKE 'EVID_S21_%' AND QUERY_TYPE = 'SELECT'
GROUP BY QUERY_TAG
ORDER BY QUERY_TAG;
-- Esperado (8 y 9 nov.): AGREGAR_Y_UNIR 1.13 a 1.22 s; UNIR_Y_AGREGAR 0.95 a 1.33 s. Los
--   rangos se traslapan: agregar antes no hizo la ejecución más corta, aunque el Join
--   recibe 4 veces menos filas.

-- Paso 21.5 · Total de O_TOTALPRICE de cada forma frente al real (SUM de ORDERS SF10)
SELECT R.REAL AS O_TOTALPRICE_REAL,
       ROUND(U.SUMA_PEDIDO / R.REAL, 1) AS VECES_UNIENDO_PRIMERO,
       ROUND(A.SUMA_PEDIDO / R.REAL, 1) AS VECES_AGREGANDO_PRIMERO
FROM (SELECT SUMA_PEDIDO FROM TABLE(RESULT_SCAN($Q21U))) U,
     (SELECT SUMA_PEDIDO FROM TABLE(RESULT_SCAN($Q21A))) A,
     (SELECT SUM(O_TOTALPRICE) AS REAL FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS) R;
-- Esperado: O_TOTALPRICE_REAL 2 266 298 190 748.43; VECES_UNIENDO_PRIMERO 5.0;
--   VECES_AGREGANDO_PRIMERO 1.0 («exacto»).


-- =====================================================================
-- SLIDE 22 · El promedio de promedios se desvía 6.9 %
-- Afirmación en pantalla: «Con medias desiguales, el promedio de promedios se desvía
--   6.9 %.» Tabla: F 729 413 pedidos, promedio 150 398.22; O 732 044, 150 288.47;
--   P 38 543, 184 446.39; promedio de promedios 161 711.03; directo = ponderado (SUM/SUM)
--   151 219.54.
-- Qué demuestra cada paso:
--   22.1  la tabla de la slide: pedidos y promedio por estado.
--   22.2  el peso de cada estado: P es 2.57 % de los pedidos, pero pesa 33.33 % en el
--         promedio de promedios.
--   22.3  los tres promedios y el desvío: 161 711.03 contra 151 219.54 (6.94 %).
--   22.4  contraste: con grupos parecidos (prioridad del pedido) el desvío es ≤ 0.18 %. La
--         trampa duele cuando las medias y los tamaños son desiguales.
-- =====================================================================

-- Paso 22.1 · Pedidos y promedio por estado
SELECT O_ORDERSTATUS AS ESTADO, COUNT(*) AS PEDIDOS, ROUND(AVG(O_TOTALPRICE), 2) AS PROMEDIO
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
GROUP BY O_ORDERSTATUS
ORDER BY O_ORDERSTATUS;
-- Esperado: F 729 413 y 150 398.22; O 732 044 y 150 288.47; P 38 543 y 184 446.39.

-- Paso 22.2 · Peso real de cada estado frente a su peso en el promedio de promedios
SELECT O_ORDERSTATUS AS ESTADO,
       ROUND(COUNT(*) / SUM(COUNT(*)) OVER () * 100, 2) AS PESO_EN_PROMEDIO_DIRECTO_PCT,
       ROUND(1 / COUNT(*) OVER () * 100, 2) AS PESO_EN_PROMEDIO_DE_PROMEDIOS_PCT
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
GROUP BY O_ORDERSTATUS
ORDER BY O_ORDERSTATUS;
-- Esperado: F 48.63 y 33.33; O 48.80 y 33.33; P 2.57 y 33.33.

-- Paso 22.3 · Los tres promedios y el desvío
WITH G AS (SELECT O_ORDERSTATUS AS ESTADO, COUNT(*) AS PEDIDOS, AVG(O_TOTALPRICE) AS PROM
           FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
           GROUP BY 1)
SELECT ROUND(AVG(PROM), 2) AS PROM_DE_PROMEDIOS,
       ROUND((SELECT AVG(O_TOTALPRICE) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS), 2)
         AS PROM_DIRECTO,
       ROUND(SUM(PEDIDOS * PROM) / SUM(PEDIDOS), 2) AS PROM_PONDERADO,
       ROUND((AVG(PROM) - SUM(PEDIDOS * PROM) / SUM(PEDIDOS))
             / (SUM(PEDIDOS * PROM) / SUM(PEDIDOS)) * 100, 2) AS DESVIO_PCT
FROM G;
-- Esperado: PROM_DE_PROMEDIOS 161 711.03; PROM_DIRECTO 151 219.54; PROM_PONDERADO 151 219.54;
--   DESVIO_PCT 6.94 (diferencia de 10 491.49).

-- Paso 22.4 · Contraste: el mismo error con grupos parecidos (prioridad del pedido)
WITH PC AS (SELECT O_ORDERPRIORITY AS CORTE, O_CUSTKEY, AVG(O_TOTALPRICE) AS AVG_CLI
            FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
            GROUP BY 1, 2),
A AS (SELECT CORTE, AVG(AVG_CLI) AS PROM_DE_PROMEDIOS FROM PC GROUP BY 1),
B AS (SELECT O_ORDERPRIORITY AS CORTE, AVG(O_TOTALPRICE) AS PROM_DIRECTO
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
      GROUP BY 1)
SELECT A.CORTE, ROUND(A.PROM_DE_PROMEDIOS, 2) AS PROM_DE_PROMEDIOS,
       ROUND(B.PROM_DIRECTO, 2) AS PROM_DIRECTO,
       ROUND((A.PROM_DE_PROMEDIOS - B.PROM_DIRECTO) / B.PROM_DIRECTO * 100, 2) AS DESVIO_PCT
FROM A JOIN B ON A.CORTE = B.CORTE
ORDER BY A.CORTE;
-- Esperado: 1-URGENT 0.13 %; 2-HIGH 0.06 %; 3-MEDIUM 0.02 %; 4-NOT SPECIFIED 0.18 %;
--   5-LOW 0.04 %. Promediar promedios de clientes es casi inofensivo aquí (medias parecidas).


-- =====================================================================
-- SLIDE 23 · Lab 3B
-- Afirmación en pantalla: «Lab 3B: QUALIFY evita anidar tres consultas y el promedio
--   ponderado corrige un error.»
-- Sin consulta propia: el «evita anidar» se ve en el bloque 19 (QUALIFY frente a la forma
--   anidada del bloque 18) y el «corrige un error» en el bloque 22 (ponderado = directo). Los
--   ejercicios B1 a B4 se verifican con lab3b_verificacion.sql (meta «4 de 4»).
-- =====================================================================


-- =====================================================================
-- SLIDE 24 · Preguntar por región pide cuatro uniones
-- Afirmación en pantalla: «Preguntar por región pide cuatro uniones cada vez.» «Cuatro
--   uniones para traer un nombre.»
-- Qué demuestra cada paso:
--   24.1  la consulta de la slide: cinco regiones, cuatro JOIN.
--   24.2  el plan lo confirma: 4 operadores Join y 5 TableScan, uno por tabla.
-- =====================================================================

-- Paso 24.1 · La consulta de la slide
SELECT R.R_NAME, SUM(L.L_EXTENDEDPRICE * (1 - L.L_DISCOUNT)) AS INGRESO
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM L
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O ON L.L_ORDERKEY = O.O_ORDERKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER C ON O.O_CUSTKEY = C.C_CUSTKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION N ON C.C_NATIONKEY = N.N_NATIONKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION R ON N.N_REGIONKEY = R.R_REGIONKEY
GROUP BY R.R_NAME ORDER BY 1;
SET Q24 = LAST_QUERY_ID();
-- Esperado (el SUM sin ROUND trae decimales de más; redondeados a centavos): AFRICA
--   43 488 870 851.69; AMERICA 43 565 312 628.95; ASIA 43 858 010 644.94; EUROPE
--   44 032 702 326.30; MIDDLE EAST 43 157 327 433.13.

-- Paso 24.2 · Operadores del plan de esa consulta
SELECT OPERATOR_TYPE, COUNT(*) AS OPERADORES
FROM TABLE(GET_QUERY_OPERATOR_STATS($Q24))
WHERE OPERATOR_TYPE IN ('Join', 'TableScan')
GROUP BY OPERATOR_TYPE
ORDER BY OPERATOR_TYPE;
-- Esperado: Join 4; TableScan 5. Salida de cada Join (de LINEITEM hacia REGION): 6 001 215,
--   1 500 000, 150 000 y 25 filas.


-- =====================================================================
-- SLIDE 25 · Normalizar guarda cada dato una vez
-- Afirmación en pantalla: «Normalizar guarda cada dato una vez: R_NAME vive en 5 filas, no
--   en 6 M.» Diagrama: LINEITEM 6 001 215, ORDERS 1 500 000, CUSTOMER 150 000, NATION 25,
--   REGION 5; «Si R_NAME estuviera en cada línea: 6 001 215 copias». Pie: formas normales 1,
--   2 y 3 (definición).
-- Qué demuestra cada paso:
--   25.1  filas de la cadena y que el nombre de región existe una vez por región.
--   25.2  si R_NAME se copiara a cada línea, serían 6 001 215 copias de solo 5 valores.
-- Las formas normales son definiciones de diseño (Codd, 1970; Kimball y Ross, The Data
--   Warehouse Toolkit, 3.ª ed., cap. 1); no hay consulta que las mida.
-- =====================================================================

-- Paso 25.1 · La cadena y el nombre único
SELECT (SELECT COUNT(*) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM) AS LINEITEM,
       (SELECT COUNT(*) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS) AS ORDERS,
       (SELECT COUNT(*) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER) AS CUSTOMER,
       (SELECT COUNT(*) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION) AS NATION,
       (SELECT COUNT(*) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION) AS REGION,
       (SELECT COUNT(DISTINCT R_NAME) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION)
         AS NOMBRES_DE_REGION;
-- Esperado: 6 001 215; 1 500 000; 150 000; 25; 5; NOMBRES_DE_REGION 5.

-- Paso 25.2 · R_NAME repetido en cada línea
SELECT COUNT(R.R_NAME) AS COPIAS_DE_R_NAME, COUNT(DISTINCT R.R_NAME) AS VALORES_DISTINTOS
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM L
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O ON L.L_ORDERKEY = O.O_ORDERKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER C ON O.O_CUSTKEY = C.C_CUSTKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION N ON C.C_NATIONKEY = N.N_NATIONKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION R ON N.N_REGIONKEY = R.R_REGIONKEY;
-- Esperado: COPIAS_DE_R_NAME 6 001 215; VALORES_DISTINTOS 5.


-- =====================================================================
-- SLIDES 26 y 27 · Desnormalizar, copo de nieve y estrella (SF10)
-- Afirmación en pantalla (26): «Desnormalizar (repetir datos) redujo la ejecución casi a la
--   mitad; hecho y dimensión ocuparon 6-7 % más.» Tabla (SF10, 3 corridas): normalizado,
--   4 uniones, ejecución 1.2 a 1.5 s, dimensión 108.3 MB; hecho + 3 tablas, 3 uniones,
--   0.65 a 0.69 s, 108.3 MB; hecho + dimensión, 1 unión, 0.60 a 0.65 s, 115.9 MB.
-- Afirmación en pantalla (27): copo de nieve = hecho + CUSTOMER, NATION y REGION (3 uniones);
--   estrella = hecho + una DIM_CLIENTE (1 unión); «+7.0 % al repetir N_NAME y R_NAME en una
--   dimensión con todas las columnas (SF10)»; «Ambos usan FACT_LINEITEM con O_CUSTKEY
--   copiado: +6.2 % de espacio (88 MB) en el hecho.»
-- Qué demuestra cada paso:
--   26.0  las tablas de SF10: el hecho (LINEITEM con O_CUSTKEY), una copia sin O_CUSTKEY para
--         medir el costo de ese campo, y la dimensión con todas las columnas más N_NAME y
--         R_NAME.
--   26.1  las 3 formas de la misma pregunta (ingreso por región), 3 corridas cada una.
--   26.2  mismo resultado en las tres formas (0 filas distintas).
--   26.3  uniones por forma (operadores Join): 4, 3 y 1.
--   26.4  tiempo de ejecución y de compilación por forma, y el cociente entre normalizado y
--         estrella.
--   26.5  espacio: dimensión +7.0 %; hecho +6.2 %.
-- Costo: SF10, X-Small. Crear el hecho tarda unos 20 s; todo el bloque, unos 2 min
--   (0.04 créditos). Los tiempos varían; el orden de magnitud no.
-- =====================================================================

-- Paso 26.0 · Tablas de SF10 (esquema SF10 de CURSO_EVIDENCIA_C3)
CREATE OR REPLACE SCHEMA CURSO_EVIDENCIA_C3.SF10;
USE SCHEMA CURSO_EVIDENCIA_C3.SF10;

-- El hecho: LINEITEM con O_CUSTKEY copiado en cada línea (59 986 052 filas).
CREATE OR REPLACE TABLE FACT_LINEITEM AS
SELECT L.*, O.O_CUSTKEY
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM L
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS O ON L.L_ORDERKEY = O.O_ORDERKEY;

-- La copia de referencia: LINEITEM creada de la misma forma, sin O_CUSTKEY.
CREATE OR REPLACE TABLE LINEITEM_COPIA AS
SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM;

-- La dimensión: CUSTOMER con N_NAME y R_NAME repetidos (1 500 000 filas).
CREATE OR REPLACE TABLE DIM_CLIENTE_COMPLETA AS
SELECT C.*, N.N_NAME, R.R_NAME
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.CUSTOMER C
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.NATION N ON C.C_NATIONKEY = N.N_NATIONKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.REGION R ON N.N_REGIONKEY = R.R_REGIONKEY;

SELECT (SELECT COUNT(*) FROM FACT_LINEITEM) AS FACT_LINEITEM,
       (SELECT COUNT(*) FROM LINEITEM_COPIA) AS LINEITEM_COPIA,
       (SELECT COUNT(*) FROM DIM_CLIENTE_COMPLETA) AS DIM_CLIENTE_COMPLETA;
-- Esperado: 59 986 052; 59 986 052; 1 500 000.

-- Paso 26.1a · Forma 1, normalizado: 4 uniones (3 corridas)
ALTER SESSION SET QUERY_TAG = 'EVID_S26_1_NORMALIZADO';
SELECT R.R_NAME, ROUND(SUM(L.L_EXTENDEDPRICE * (1 - L.L_DISCOUNT)), 2) AS INGRESO
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM L
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS O ON L.L_ORDERKEY = O.O_ORDERKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.CUSTOMER C ON O.O_CUSTKEY = C.C_CUSTKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.NATION N ON C.C_NATIONKEY = N.N_NATIONKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.REGION R ON N.N_REGIONKEY = R.R_REGIONKEY
GROUP BY R.R_NAME ORDER BY 1;
SELECT R.R_NAME, ROUND(SUM(L.L_EXTENDEDPRICE * (1 - L.L_DISCOUNT)), 2) AS INGRESO
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM L
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS O ON L.L_ORDERKEY = O.O_ORDERKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.CUSTOMER C ON O.O_CUSTKEY = C.C_CUSTKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.NATION N ON C.C_NATIONKEY = N.N_NATIONKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.REGION R ON N.N_REGIONKEY = R.R_REGIONKEY
GROUP BY R.R_NAME ORDER BY 1;
SELECT R.R_NAME, ROUND(SUM(L.L_EXTENDEDPRICE * (1 - L.L_DISCOUNT)), 2) AS INGRESO
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM L
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS O ON L.L_ORDERKEY = O.O_ORDERKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.CUSTOMER C ON O.O_CUSTKEY = C.C_CUSTKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.NATION N ON C.C_NATIONKEY = N.N_NATIONKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.REGION R ON N.N_REGIONKEY = R.R_REGIONKEY
GROUP BY R.R_NAME ORDER BY 1;
SET Q26_1 = LAST_QUERY_ID();
-- Esperado (las 3 corridas): AFRICA 435 475 383 578.07; AMERICA 434 758 267 615.94;
--   ASIA 436 738 690 443.01; EUROPE 436 890 284 129.48; MIDDLE EAST 435 252 080 170.44.

-- Paso 26.1b · Forma 2, hecho + CUSTOMER, NATION y REGION (copo de nieve): 3 uniones
ALTER SESSION SET QUERY_TAG = 'EVID_S26_2_HECHO_Y_3_TABLAS';
SELECT R.R_NAME, ROUND(SUM(F.L_EXTENDEDPRICE * (1 - F.L_DISCOUNT)), 2) AS INGRESO
FROM FACT_LINEITEM F
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.CUSTOMER C ON F.O_CUSTKEY = C.C_CUSTKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.NATION N ON C.C_NATIONKEY = N.N_NATIONKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.REGION R ON N.N_REGIONKEY = R.R_REGIONKEY
GROUP BY R.R_NAME ORDER BY 1;
SELECT R.R_NAME, ROUND(SUM(F.L_EXTENDEDPRICE * (1 - F.L_DISCOUNT)), 2) AS INGRESO
FROM FACT_LINEITEM F
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.CUSTOMER C ON F.O_CUSTKEY = C.C_CUSTKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.NATION N ON C.C_NATIONKEY = N.N_NATIONKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.REGION R ON N.N_REGIONKEY = R.R_REGIONKEY
GROUP BY R.R_NAME ORDER BY 1;
SELECT R.R_NAME, ROUND(SUM(F.L_EXTENDEDPRICE * (1 - F.L_DISCOUNT)), 2) AS INGRESO
FROM FACT_LINEITEM F
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.CUSTOMER C ON F.O_CUSTKEY = C.C_CUSTKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.NATION N ON C.C_NATIONKEY = N.N_NATIONKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.REGION R ON N.N_REGIONKEY = R.R_REGIONKEY
GROUP BY R.R_NAME ORDER BY 1;
SET Q26_2 = LAST_QUERY_ID();
-- Esperado (las 3 corridas): las mismas 5 cifras de la forma 1.

-- Paso 26.1c · Forma 3, hecho + dimensión (estrella): 1 unión
ALTER SESSION SET QUERY_TAG = 'EVID_S26_3_HECHO_Y_DIMENSION';
SELECT D.R_NAME, ROUND(SUM(F.L_EXTENDEDPRICE * (1 - F.L_DISCOUNT)), 2) AS INGRESO
FROM FACT_LINEITEM F
JOIN DIM_CLIENTE_COMPLETA D ON F.O_CUSTKEY = D.C_CUSTKEY
GROUP BY D.R_NAME ORDER BY 1;
SELECT D.R_NAME, ROUND(SUM(F.L_EXTENDEDPRICE * (1 - F.L_DISCOUNT)), 2) AS INGRESO
FROM FACT_LINEITEM F
JOIN DIM_CLIENTE_COMPLETA D ON F.O_CUSTKEY = D.C_CUSTKEY
GROUP BY D.R_NAME ORDER BY 1;
SELECT D.R_NAME, ROUND(SUM(F.L_EXTENDEDPRICE * (1 - F.L_DISCOUNT)), 2) AS INGRESO
FROM FACT_LINEITEM F
JOIN DIM_CLIENTE_COMPLETA D ON F.O_CUSTKEY = D.C_CUSTKEY
GROUP BY D.R_NAME ORDER BY 1;
SET Q26_3 = LAST_QUERY_ID();
ALTER SESSION UNSET QUERY_TAG;
-- Esperado (las 3 corridas): las mismas 5 cifras de la forma 1.

-- Paso 26.2 · Las tres formas dan el mismo resultado: filas distintas entre la 1 y la 3
WITH N AS (SELECT R.R_NAME AS REG, SUM(L.L_EXTENDEDPRICE * (1 - L.L_DISCOUNT)) AS INGRESO
           FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM L
           JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS O ON L.L_ORDERKEY = O.O_ORDERKEY
           JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.CUSTOMER C ON O.O_CUSTKEY = C.C_CUSTKEY
           JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.NATION NA ON C.C_NATIONKEY = NA.N_NATIONKEY
           JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.REGION R ON NA.N_REGIONKEY = R.R_REGIONKEY
           GROUP BY R.R_NAME),
S AS (SELECT D.R_NAME AS REG, SUM(F.L_EXTENDEDPRICE * (1 - F.L_DISCOUNT)) AS INGRESO
      FROM FACT_LINEITEM F
      JOIN DIM_CLIENTE_COMPLETA D ON F.O_CUSTKEY = D.C_CUSTKEY
      GROUP BY D.R_NAME)
SELECT (SELECT COUNT(*) FROM (SELECT * FROM N EXCEPT SELECT * FROM S))
     + (SELECT COUNT(*) FROM (SELECT * FROM S EXCEPT SELECT * FROM N)) AS FILAS_DIFERENTES,
       (SELECT COUNT(*) FROM N) AS REGIONES;
-- Esperado: FILAS_DIFERENTES 0; REGIONES 5.

-- Paso 26.3 · Uniones (operadores Join) y tablas leídas en la última corrida de cada forma
SELECT '1 normalizado' AS FORMA,
       COUNT_IF(OPERATOR_TYPE = 'Join') AS UNIONES,
       COUNT_IF(OPERATOR_TYPE = 'TableScan') AS TABLAS_LEIDAS
FROM TABLE(GET_QUERY_OPERATOR_STATS($Q26_1))
UNION ALL
SELECT '2 hecho + 3 tablas', COUNT_IF(OPERATOR_TYPE = 'Join'),
       COUNT_IF(OPERATOR_TYPE = 'TableScan')
FROM TABLE(GET_QUERY_OPERATOR_STATS($Q26_2))
UNION ALL
SELECT '3 hecho + dimensión', COUNT_IF(OPERATOR_TYPE = 'Join'),
       COUNT_IF(OPERATOR_TYPE = 'TableScan')
FROM TABLE(GET_QUERY_OPERATOR_STATS($Q26_3));
-- Esperado: 4 uniones y 5 tablas; 3 uniones y 4 tablas; 1 unión y 2 tablas.

-- Paso 26.4 · Tiempo de ejecución y de compilación de las 3 corridas de cada forma
SELECT QUERY_TAG AS FORMA, COUNT(*) AS CORRIDAS,
       ROUND(MIN(EXECUTION_TIME) / 1000, 2) AS EJEC_MIN_S,
       ROUND(MAX(EXECUTION_TIME) / 1000, 2) AS EJEC_MAX_S,
       ROUND(MIN(COMPILATION_TIME) / 1000, 2) AS COMPILACION_MIN_S,
       ROUND(MAX(COMPILATION_TIME) / 1000, 2) AS COMPILACION_MAX_S
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(RESULT_LIMIT => 200))
WHERE QUERY_TAG LIKE 'EVID_S26_%' AND QUERY_TYPE = 'SELECT'
GROUP BY QUERY_TAG
ORDER BY QUERY_TAG;
-- Esperado (dos corridas del archivo el 9 nov.; entre paréntesis, el rango de la slide):
--   1 normalizado 1.32 a 1.45 s de ejecución (1.2 a 1.5, con M5); 2 hecho + 3 tablas 0.63 a 0.68 s
--   (0.65 a 0.69); 3 hecho + dimensión 0.60 a 0.63 s (0.60 a 0.65). Compilación: 1.9 a 3.9 s,
--   0.5 a 2.5 s y 0.05 a 0.33 s. La compilación varía mucho entre corridas; la ejecución,
--   poco.

-- Paso 26.4b · «Casi a la mitad»: ejecución normalizada frente a ejecución con el hecho
WITH H AS (SELECT QUERY_TAG AS T, MEDIAN(EXECUTION_TIME) / 1000 AS S
           FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(RESULT_LIMIT => 200))
           WHERE QUERY_TAG LIKE 'EVID_S26_%' AND QUERY_TYPE = 'SELECT'
           GROUP BY QUERY_TAG)
SELECT ROUND(MAX(IFF(T = 'EVID_S26_1_NORMALIZADO', S, NULL)), 2) AS NORMALIZADO_S,
       ROUND(MAX(IFF(T = 'EVID_S26_3_HECHO_Y_DIMENSION', S, NULL)), 2) AS ESTRELLA_S,
       ROUND(MAX(IFF(T = 'EVID_S26_3_HECHO_Y_DIMENSION', S, NULL))
             / MAX(IFF(T = 'EVID_S26_1_NORMALIZADO', S, NULL)), 2) AS ESTRELLA_ENTRE_NORMALIZADO
FROM H;
-- Esperado: ESTRELLA_ENTRE_NORMALIZADO 0.44 a 0.46 (NORMALIZADO_S 1.33 y 1.39; ESTRELLA_S
--   0.62 y 0.61): casi la mitad.

-- Paso 26.5 · Espacio: la dimensión (CUSTOMER + NATION + REGION contra la completa) y el hecho
SELECT 'CUSTOMER + NATION + REGION (normalizado)' AS TABLA,
       SUM(BYTES) AS BYTES, ROUND(SUM(BYTES) / 1e6, 1) AS MB, NULL AS DIF_PCT
FROM SNOWFLAKE_SAMPLE_DATA.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'TPCH_SF10' AND TABLE_NAME IN ('CUSTOMER', 'NATION', 'REGION')
UNION ALL
SELECT 'DIM_CLIENTE_COMPLETA', BYTES, ROUND(BYTES / 1e6, 1),
       ROUND((BYTES / (SELECT SUM(BYTES)
                       FROM SNOWFLAKE_SAMPLE_DATA.INFORMATION_SCHEMA.TABLES
                       WHERE TABLE_SCHEMA = 'TPCH_SF10'
                         AND TABLE_NAME IN ('CUSTOMER', 'NATION', 'REGION')) - 1) * 100, 1)
FROM CURSO_EVIDENCIA_C3.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'SF10' AND TABLE_NAME = 'DIM_CLIENTE_COMPLETA'
UNION ALL
SELECT 'LINEITEM_COPIA (sin O_CUSTKEY)', BYTES, ROUND(BYTES / 1e6, 1), NULL
FROM CURSO_EVIDENCIA_C3.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'SF10' AND TABLE_NAME = 'LINEITEM_COPIA'
UNION ALL
SELECT 'FACT_LINEITEM (con O_CUSTKEY)', F.BYTES, ROUND(F.BYTES / 1e6, 1),
       ROUND((F.BYTES / C.BYTES - 1) * 100, 1)
FROM CURSO_EVIDENCIA_C3.INFORMATION_SCHEMA.TABLES F
JOIN CURSO_EVIDENCIA_C3.INFORMATION_SCHEMA.TABLES C
  ON C.TABLE_SCHEMA = 'SF10' AND C.TABLE_NAME = 'LINEITEM_COPIA'
WHERE F.TABLE_SCHEMA = 'SF10' AND F.TABLE_NAME = 'FACT_LINEITEM';
-- Esperado: normalizado 108 257 280 bytes (108.3 MB); DIM_CLIENTE_COMPLETA 115 863 040
--   (115.9 MB), +7.0 %; LINEITEM_COPIA 1 431 657 984; FACT_LINEITEM 1 519 718 400 (1 519.7
--   MB), +6.2 % (≈ 88 MB más). Los bytes de las tablas nuevas varían unos miles entre
--   corridas.

USE SCHEMA CURSO_EVIDENCIA_C3.PUBLIC;


-- =====================================================================
-- SLIDE 28 · El grano declara qué es una fila
-- Afirmación en pantalla: «El grano declara qué es una fila: en FACT_LINEITEM (hechos), una
--   línea de pedido.» Tabla: línea de pedido, 6 001 215 filas; pedido, 1 500 000; día,
--   2 406.
-- Qué demuestra cada paso:
--   28.0  construye la estrella de SF1 (DIM_CLIENTE, DIM_FECHA, DIM_PRODUCTO y
--         FACT_LINEITEM) en CURSO_EVIDENCIA_C3.ESTRELLA. Es el mismo SQL de C1 a C3 del Lab 3C.
--   28.1  FACT_LINEITEM tiene 6 001 215 filas y 6 001 215 claves (L_ORDERKEY, L_LINENUMBER):
--         una fila por línea, sin repetidas.
--   28.2  los pedidos son 1 500 000 y los días del rango, 2 406.
-- =====================================================================

-- Paso 28.0 · Construir la estrella de SF1 (unos 5 s)
CREATE OR REPLACE SCHEMA CURSO_EVIDENCIA_C3.ESTRELLA;
USE SCHEMA CURSO_EVIDENCIA_C3.ESTRELLA;
ALTER SESSION SET QUERY_TAG = 'EVID_C3_ESTRELLA';

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

CREATE OR REPLACE TABLE DIM_PRODUCTO AS
SELECT P_PARTKEY AS PRODUCTO_KEY, P_NAME, P_BRAND, P_TYPE
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.PART;

CREATE OR REPLACE TABLE FACT_LINEITEM AS
SELECT L.L_ORDERKEY, L.L_LINENUMBER,
       O.O_CUSTKEY AS CLIENTE_KEY,
       O.O_ORDERDATE AS FECHA,
       L.L_PARTKEY AS PRODUCTO_KEY,
       L.L_QUANTITY, L.L_EXTENDEDPRICE, L.L_DISCOUNT,
       L.L_EXTENDEDPRICE * (1 - L.L_DISCOUNT) AS INGRESO
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM L
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O ON L.L_ORDERKEY = O.O_ORDERKEY;

ALTER SESSION UNSET QUERY_TAG;

SELECT (SELECT COUNT(*) FROM DIM_CLIENTE) AS DIM_CLIENTE,
       (SELECT COUNT(*) FROM DIM_FECHA) AS DIM_FECHA,
       (SELECT COUNT(*) FROM DIM_PRODUCTO) AS DIM_PRODUCTO,
       (SELECT COUNT(*) FROM FACT_LINEITEM) AS FACT_LINEITEM;
-- Esperado: 150 000; 2 406; 200 000; 6 001 215.

-- Paso 28.1 · El grano: una fila por línea de pedido
SELECT COUNT(*) AS FILAS,
       COUNT(DISTINCT L_ORDERKEY, L_LINENUMBER) AS CLAVES_DEL_GRANO,
       COUNT(DISTINCT L_ORDERKEY * 10 + L_LINENUMBER) AS CLAVES_DE_LA_SLIDE_36,
       MIN(L_LINENUMBER) AS LINEA_MIN, MAX(L_LINENUMBER) AS LINEA_MAX
FROM FACT_LINEITEM;
-- Esperado: FILAS 6 001 215; CLAVES_DEL_GRANO 6 001 215; CLAVES_DE_LA_SLIDE_36 6 001 215
--   (L_LINENUMBER va de 1 a 7, menor que 10: la clave compuesta L_ORDERKEY * 10 + L_LINENUMBER
--   no mezcla pedidos); LINEA_MIN 1; LINEA_MAX 7.

-- Paso 28.2 · Pedidos y días: los otros dos granos de la tabla
SELECT COUNT(DISTINCT L_ORDERKEY) AS PEDIDOS_EN_EL_HECHO,
       (SELECT COUNT(*) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS) AS PEDIDOS_EN_ORDERS,
       (SELECT COUNT(*) FROM DIM_FECHA) AS DIAS_DEL_RANGO,
       (SELECT MIN(FECHA) FROM DIM_FECHA) AS PRIMER_DIA,
       (SELECT MAX(FECHA) FROM DIM_FECHA) AS ULTIMO_DIA
FROM FACT_LINEITEM;
-- Esperado: PEDIDOS_EN_EL_HECHO 1 500 000; PEDIDOS_EN_ORDERS 1 500 000; DIAS_DEL_RANGO 2 406;
--   PRIMER_DIA 1992-01-01; ULTIMO_DIA 1998-08-02.


-- =====================================================================
-- SLIDE 29 · FACT_LINEITEM guarda lo que se mide; las dimensiones describen
-- Afirmación en pantalla: estrella con FACT_LINEITEM (6 001 215 filas; llaves L_ORDERKEY,
--   L_LINENUMBER, CLIENTE_KEY, FECHA, PRODUCTO_KEY; medidas L_QUANTITY, L_EXTENDEDPRICE,
--   L_DISCOUNT, INGRESO), DIM_CLIENTE (150 000; C_NAME, C_MKTSEGMENT, N_NAME, R_NAME),
--   DIM_FECHA (2 406; FECHA, ANIO, MES), DIM_PRODUCTO (200 000; P_NAME, P_BRAND, P_TYPE,
--   opcional). Pie: «Hecho transaccional: una fila por evento.»
-- Qué demuestra cada paso:
--   29.1  las columnas de cada tabla coinciden con el diagrama.
--   29.2  la estrella responde «ingreso por región y año» con dos uniones, no cuatro: 35 filas.
-- Definición de hecho transaccional: Kimball y Ross, The Data Warehouse Toolkit, 3.ª ed.
--   Requiere: bloque 28 (paso 28.0).
-- =====================================================================
USE SCHEMA CURSO_EVIDENCIA_C3.ESTRELLA;

-- Paso 29.1 · Columnas y filas de cada tabla
SELECT T.TABLE_NAME AS TABLA, T.ROW_COUNT AS FILAS,
       LISTAGG(C.COLUMN_NAME, ', ') WITHIN GROUP (ORDER BY C.ORDINAL_POSITION) AS COLUMNAS
FROM CURSO_EVIDENCIA_C3.INFORMATION_SCHEMA.TABLES T
JOIN CURSO_EVIDENCIA_C3.INFORMATION_SCHEMA.COLUMNS C
  ON C.TABLE_SCHEMA = T.TABLE_SCHEMA AND C.TABLE_NAME = T.TABLE_NAME
WHERE T.TABLE_SCHEMA = 'ESTRELLA'
  AND T.TABLE_NAME IN ('FACT_LINEITEM', 'DIM_CLIENTE', 'DIM_FECHA', 'DIM_PRODUCTO')
GROUP BY T.TABLE_NAME, T.ROW_COUNT
ORDER BY T.ROW_COUNT DESC;
-- Esperado: FACT_LINEITEM 6 001 215: L_ORDERKEY, L_LINENUMBER, CLIENTE_KEY, FECHA,
--   PRODUCTO_KEY, L_QUANTITY, L_EXTENDEDPRICE, L_DISCOUNT, INGRESO. DIM_PRODUCTO 200 000:
--   PRODUCTO_KEY, P_NAME, P_BRAND, P_TYPE. DIM_CLIENTE 150 000: CLIENTE_KEY, C_NAME,
--   C_MKTSEGMENT, N_NAME, R_NAME. DIM_FECHA 2 406: FECHA, ANIO, MES.

-- Paso 29.2 · Ingreso por región y año con la estrella: dos uniones
SELECT D.R_NAME, T.ANIO, ROUND(SUM(F.INGRESO), 2) AS INGRESO
FROM FACT_LINEITEM F
JOIN DIM_CLIENTE D ON F.CLIENTE_KEY = D.CLIENTE_KEY
JOIN DIM_FECHA T ON F.FECHA = T.FECHA
GROUP BY D.R_NAME, T.ANIO
ORDER BY D.R_NAME, T.ANIO;
-- Esperado: 35 filas (5 regiones por 7 años). Primera: AFRICA, 1992, 6 608 511 861.49.
--   Última: MIDDLE EAST, 1998, 3 869 651 630.83. Suman 218 102 223 885.00.


-- =====================================================================
-- SLIDE 30 · Aditividad
-- Afirmación en pantalla: «Las aditivas se suman por cualquier dimensión; promedios y lluvia
--   diaria, no.» INGRESO: aditiva, SUM por cualquier dimensión. Precio promedio: no
--   aditiva, guardar SUM y COUNT. LLUVIA_MM del gold (tabla final): semiaditiva, no sumar
--   por zona.
-- Qué demuestra cada paso:
--   30.1  INGRESO da el mismo total agrupado por región, año, segmento o marca.
--   30.2  un promedio no se suma ni se promedia: el promedio por región no recompone el
--         global; SUM y COUNT guardados sí.
--   30.3  LLUVIA_MM del gold: el 2024-01-10 hay 514 filas con 21.7 mm cada una; sumarlas da
--         11 153.8, que no es lluvia. Sumar un valor por día sí tiene sentido (152.8 mm en
--         enero).
-- Clasificación aditiva, semiaditiva y no aditiva: Kimball y Ross, The Data Warehouse
--   Toolkit, 3.ª ed., cap. 1 («additive, semi-additive, non-additive facts»).
-- Requiere: bloque 28 (pasos 30.1 y 30.2). El paso 30.3 usa BIGDATA.DEV.DAILY_ZONE_METRICS.
-- =====================================================================
USE SCHEMA CURSO_EVIDENCIA_C3.ESTRELLA;

-- Paso 30.1 · INGRESO sumado por cuatro dimensiones distintas
SELECT 'por región' AS CORTE, ROUND(SUM(S), 2) AS TOTAL
FROM (SELECT D.R_NAME, SUM(F.INGRESO) AS S
      FROM FACT_LINEITEM F JOIN DIM_CLIENTE D USING (CLIENTE_KEY) GROUP BY 1)
UNION ALL
SELECT 'por año', ROUND(SUM(S), 2)
FROM (SELECT T.ANIO, SUM(F.INGRESO) AS S
      FROM FACT_LINEITEM F JOIN DIM_FECHA T USING (FECHA) GROUP BY 1)
UNION ALL
SELECT 'por segmento', ROUND(SUM(S), 2)
FROM (SELECT D.C_MKTSEGMENT, SUM(F.INGRESO) AS S
      FROM FACT_LINEITEM F JOIN DIM_CLIENTE D USING (CLIENTE_KEY) GROUP BY 1)
UNION ALL
SELECT 'por marca de producto', ROUND(SUM(S), 2)
FROM (SELECT P.P_BRAND, SUM(F.INGRESO) AS S
      FROM FACT_LINEITEM F JOIN DIM_PRODUCTO P USING (PRODUCTO_KEY) GROUP BY 1)
UNION ALL
SELECT 'sin agrupar', ROUND(SUM(INGRESO), 2) FROM FACT_LINEITEM;
-- Esperado: 218 102 223 885.00 en las cinco filas.

-- Paso 30.2 · Un promedio por región no recompone el promedio global
-- Se compara el precio de línea promedio. Las regiones tienen tamaños casi iguales, así que
-- la diferencia es pequeña; con grupos desiguales se dispara (bloque 22, 6.94 %). Sumar los
-- promedios, en cambio, no tiene sentido nunca.
WITH R AS (SELECT D.R_NAME, AVG(F.L_EXTENDEDPRICE) AS PROMEDIO, COUNT(*) AS N,
                  SUM(F.L_EXTENDEDPRICE) AS S
           FROM FACT_LINEITEM F JOIN DIM_CLIENTE D USING (CLIENTE_KEY)
           GROUP BY D.R_NAME)
SELECT ROUND(SUM(PROMEDIO), 2) AS SUMA_DE_PROMEDIOS,
       ROUND(AVG(PROMEDIO), 4) AS PROMEDIO_DE_PROMEDIOS,
       ROUND(SUM(S) / SUM(N), 4) AS SUM_ENTRE_COUNT,
       (SELECT ROUND(AVG(L_EXTENDEDPRICE), 4) FROM FACT_LINEITEM) AS PROMEDIO_DIRECTO
FROM R;
-- Esperado: SUMA_DE_PROMEDIOS 191 275.73 (sin sentido); PROMEDIO_DE_PROMEDIOS 38 255.1463;
--   SUM_ENTRE_COUNT 38 255.1385; PROMEDIO_DIRECTO 38 255.1385. Guardar SUM y COUNT recompone
--   el valor exacto en cualquier corte; el promedio guardado, no.

-- Paso 30.3 · LLUVIA_MM en el gold: una medida del día repetida en cada zona
EXECUTE IMMEDIATE $$
DECLARE
  r RESULTSET;
BEGIN
  r := (SELECT COUNT(*) AS FILAS, MIN(LLUVIA_MM) AS LLUVIA_MIN, MAX(LLUVIA_MM) AS LLUVIA_MAX,
               SUM(LLUVIA_MM) AS SUMA_DE_LLUVIA
        FROM BIGDATA.DEV.DAILY_ZONE_METRICS
        WHERE FECHA = '2024-01-10');
  RETURN TABLE(r);
EXCEPTION
  WHEN OTHER THEN
    r := (SELECT 'AVISO: no existe BIGDATA.DEV.DAILY_ZONE_METRICS en esta cuenta' AS AVISO);
    RETURN TABLE(r);
END;
$$;
-- Esperado (gold de enero 2024): FILAS 514; LLUVIA_MIN 21.7; LLUVIA_MAX 21.7;
--   SUMA_DE_LLUVIA 11 153.8. El número real de lluvia de ese día es 21.7 mm.

-- Paso 30.3b · Sumar la lluvia: por filas contra una vez por día
EXECUTE IMMEDIATE $$
DECLARE
  r RESULTSET;
BEGIN
  r := (SELECT ROUND(SUM(LLUVIA_DEL_DIA), 1) AS LLUVIA_DE_ENERO_UNA_VEZ_POR_DIA,
               ROUND(SUM(SUMA_DE_FILAS), 1) AS SUMA_DE_TODAS_LAS_FILAS
        FROM (SELECT FECHA, MAX(LLUVIA_MM) AS LLUVIA_DEL_DIA, SUM(LLUVIA_MM) AS SUMA_DE_FILAS
              FROM BIGDATA.DEV.DAILY_ZONE_METRICS
              GROUP BY FECHA));
  RETURN TABLE(r);
EXCEPTION
  WHEN OTHER THEN
    r := (SELECT 'AVISO: no existe BIGDATA.DEV.DAILY_ZONE_METRICS en esta cuenta' AS AVISO);
    RETURN TABLE(r);
END;
$$;
-- Esperado: LLUVIA_DE_ENERO_UNA_VEZ_POR_DIA 152.8 (mm); SUMA_DE_TODAS_LAS_FILAS 78 394.7.
--   Por tiempo sí se suma (los días de enero); por zona no (repetiría la lluvia 261 veces).


-- =====================================================================
-- SLIDE 31 · Grano mezclado
-- Afirmación en pantalla: «Grano mezclado: la medida del pedido, repetida en cada línea,
--   infla la suma 5 veces.» Diagrama: un pedido de 100 con tres líneas suma 300 después del
--   JOIN; 1 500 000 -> 6 001 215 filas (× 4.0); SUM(O_TOTALPRICE) 226.8 -> 1 134.4 mil
--   millones (× 5.0). «El monto crece más que las filas porque los pedidos grandes tienen
--   más líneas y se repiten más.»
-- Qué demuestra cada paso:
--   31.1  un pedido real de tres líneas hace lo del diagrama: su monto sumado vale 3 veces.
--   31.2  la cifra de la slide 2 (× 4.0 filas, × 5.0 monto); el desglose paso a paso está en
--         el bloque 2 (pasos 2.1 a 2.6b).
--   31.3  el error en una tabla de hechos: si FACT_LINEITEM llevara O_TOTALPRICE, el SUM se
--         infla; la medida propia de la línea, INGRESO, no.
--   31.4  por qué el ingreso por línea no reproduce el total del pedido: O_TOTALPRICE incluye
--         impuesto (con (1 + L_TAX) coincide con 0.00002 %).
-- Requiere: bloque 28.
-- =====================================================================
USE SCHEMA CURSO_EVIDENCIA_C3.ESTRELLA;

-- Paso 31.1 · Un pedido con tres líneas (el pedido A del diagrama)
WITH A AS (SELECT L_ORDERKEY
           FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM
           GROUP BY L_ORDERKEY
           HAVING COUNT(*) = 3
           ORDER BY L_ORDERKEY
           LIMIT 1)
SELECT O.O_ORDERKEY, O.O_TOTALPRICE, L.L_LINENUMBER,
       SUM(O.O_TOTALPRICE) OVER () AS SUMA_TRAS_EL_JOIN
FROM A
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O ON O.O_ORDERKEY = A.L_ORDERKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM L ON L.L_ORDERKEY = O.O_ORDERKEY
ORDER BY L.L_LINENUMBER;
-- Esperado: el pedido 5, 3 filas con el mismo O_TOTALPRICE 144 659.20 y SUMA_TRAS_EL_JOIN
--   433 977.60, 3 veces ese valor. Igual que 100 -> 300 en el diagrama.

-- Paso 31.2 · Las cifras de la slide: filas y monto
SELECT COUNT(*) AS FILAS_TRAS_EL_JOIN,
       ROUND(COUNT(*) / 1500000, 1) AS VECES_EN_FILAS,
       SUM(O.O_TOTALPRICE) AS SUMA_TRAS_EL_JOIN,
       ROUND(SUM(O.O_TOTALPRICE) / (SELECT SUM(O_TOTALPRICE)
                                    FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS), 1)
         AS VECES_EN_MONTO
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM L
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O ON L.L_ORDERKEY = O.O_ORDERKEY;
-- Esperado: FILAS_TRAS_EL_JOIN 6 001 215; VECES_EN_FILAS 4.0; SUMA_TRAS_EL_JOIN
--   1 134 436 101 880.19; VECES_EN_MONTO 5.0.

-- Paso 31.3 · En la tabla de hechos: la medida del pedido se infla, la de la línea no
SELECT ROUND(SUM(F.INGRESO), 2) AS INGRESO_POR_LINEA,
       SUM(O.O_TOTALPRICE) AS O_TOTALPRICE_EN_EL_HECHO,
       (SELECT SUM(O_TOTALPRICE) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS)
         AS O_TOTALPRICE_REAL
FROM FACT_LINEITEM F
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O ON O.O_ORDERKEY = F.L_ORDERKEY;
-- Esperado: INGRESO_POR_LINEA 218 102 223 885.00 (correcto, una vez por línea);
--   O_TOTALPRICE_EN_EL_HECHO 1 134 436 101 880.19 (5.0 veces); O_TOTALPRICE_REAL
--   226 829 306 447.46.

-- Paso 31.4 · El ingreso por línea contra el total del pedido: el impuesto
SELECT ROUND(SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT)), 2) AS INGRESO_SIN_IMPUESTO,
       ROUND(SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT) * (1 + L_TAX)), 2) AS CON_IMPUESTO,
       (SELECT SUM(O_TOTALPRICE) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS)
         AS SUMA_O_TOTALPRICE
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM;
-- Esperado: INGRESO_SIN_IMPUESTO 218 102 223 885.00; CON_IMPUESTO 226 829 357 828.87;
--   SUMA_O_TOTALPRICE 226 829 306 447.46 (diferencia de 51 381.41, 0.00002 %).


-- =====================================================================
-- SLIDE 32 · La fecha también es dimensión
-- Afirmación en pantalla: «La fecha también es dimensión: el cliente 102022 compró en 39 de
--   2 406 días.» «GENERATOR crea 3 000 filas; QUALIFY deja 2 406 días. LEFT JOIN conserva
--   2 367 sin pedidos. Los 41 pedidos caen en 39 días: dos días tienen dos.»
-- Qué demuestra cada paso:
--   32.1  el rango de fechas de los pedidos: 2 406 días.
--   32.2  GENERATOR crea 3 000 filas.
--   32.3  41 pedidos en 39 días distintos; los dos días con dos pedidos.
--   32.4  la consulta de la slide: 2 406 días, 39 con pedidos, 2 367 sin pedidos.
--   32.5  por qué ROW_NUMBER y no SEQ4 directo: SEQ4 no garantiza una secuencia sin huecos
--         (aquí sí la dio, de 0 a 2 999).
-- Documentación de GENERATOR y SEQ4: docs.snowflake.com/en/sql-reference/functions/generator
-- =====================================================================

-- Paso 32.1 · Rango de fechas de los pedidos
SELECT MIN(O_ORDERDATE) AS PRIMERA, MAX(O_ORDERDATE) AS ULTIMA,
       DATEDIFF('day', MIN(O_ORDERDATE), MAX(O_ORDERDATE)) + 1 AS DIAS_EN_EL_RANGO
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS;
-- Esperado: PRIMERA 1992-01-01; ULTIMA 1998-08-02; DIAS_EN_EL_RANGO 2 406.

-- Paso 32.2 · GENERATOR crea 3 000 filas
SELECT COUNT(*) AS FILAS, COUNT(DISTINCT SEQ) AS VALORES_DISTINTOS,
       MIN(SEQ) AS MINIMO, MAX(SEQ) AS MAXIMO
FROM (SELECT SEQ4() AS SEQ FROM TABLE(GENERATOR(ROWCOUNT => 3000)));
-- Esperado: FILAS 3 000; VALORES_DISTINTOS 3 000; MINIMO 0; MAXIMO 2 999.

-- Paso 32.3 · Pedidos del cliente 102022 y días en que compró
SELECT COUNT(*) AS PEDIDOS, COUNT(DISTINCT O_ORDERDATE) AS DIAS_DISTINTOS
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_CUSTKEY = 102022;
-- Esperado: PEDIDOS 41; DIAS_DISTINTOS 39.

SELECT O_ORDERDATE, COUNT(*) AS PEDIDOS
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_CUSTKEY = 102022
GROUP BY O_ORDERDATE
HAVING COUNT(*) > 1
ORDER BY O_ORDERDATE;
-- Esperado: 1994-12-15 (2 pedidos) y 1997-03-12 (2 pedidos).

-- Paso 32.4 · La consulta de la slide
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
-- Esperado: DIAS 2 406; CON_PEDIDOS 39; SIN_PEDIDOS 2 367 (98.4 % de los días).

-- Paso 32.5 · Contraste: con todos los clientes no hay huecos (por eso se filtra por cliente)
WITH r AS (SELECT MIN(O_ORDERDATE) AS MINF, MAX(O_ORDERDATE) AS MAXF
           FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS),
d AS (SELECT DATEADD('day', ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1, MINF) AS FECHA
      FROM r, TABLE(GENERATOR(ROWCOUNT => 3000))
      QUALIFY FECHA <= MAXF),
p AS (SELECT DISTINCT O_ORDERDATE AS FECHA
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS)
SELECT COUNT(*) AS DIAS, COUNT(p.FECHA) AS CON_PEDIDOS,
       COUNT(*) - COUNT(p.FECHA) AS SIN_PEDIDOS
FROM d LEFT JOIN p ON p.FECHA = d.FECHA;
-- Esperado: DIAS 2 406; CON_PEDIDOS 2 406; SIN_PEDIDOS 0.


-- =====================================================================
-- SLIDE 33 · SCD tipo 1 sobrescribe
-- Afirmación en pantalla: «SCD tipo 1 sobrescribe: si el cliente 102022 se mudara, 41 pedidos
--   pasarían de ASIA a EUROPE.» Diagrama: 102022 INDONESIA/ASIA pasa a FRANCE/EUROPE;
--   ingreso de ASIA 6 039 653.63 antes y 0 después; EUROPE 0 antes y 6 039 653.63 después;
--   «ASIA pierde 6 039 653.63 y EUROPE lo gana; ningún pedido cambió.» «Ingreso = suma de
--   L_EXTENDEDPRICE × (1 − L_DISCOUNT), sin impuesto; O_TOTALPRICE (6 273 788.41) sí lo
--   incluye.» La mudanza es un supuesto; los pedidos son reales.
-- Qué demuestra cada paso:
--   33.1  el cliente 102022 es real: INDONESIA, ASIA, segmento AUTOMOBILE.
--   33.2  antes de la mudanza: 41 pedidos y 6 039 653.63 en ASIA.
--   33.3  de esos 41, 19 son anteriores al 1995-06-01 (ya habían ocurrido).
--   33.4  después del UPDATE: los 41 pedidos, con los mismos importes, quedan en EUROPE.
--   33.5  la fila del diagrama ya no dice dónde estaba el cliente cuando compró: se perdió.
--   El supuesto (FRANCE, 1995-06-01) lo elige el ejemplo; no está en TPC-H.
-- Documentación: Kimball y Ross, The Data Warehouse Toolkit, 3.ª ed., cap. 5 (tipos 1 y 2).
-- Requiere: bloque 28.
-- =====================================================================
USE SCHEMA CURSO_EVIDENCIA_C3.ESTRELLA;

-- Paso 33.1 · El cliente en la dimensión
SELECT * FROM DIM_CLIENTE WHERE CLIENTE_KEY = 102022;
-- Esperado: 102022, Customer#000102022, AUTOMOBILE, INDONESIA, ASIA.

-- Paso 33.2 · Una copia mínima de la dimensión (solo ese cliente) y el ingreso por región
CREATE OR REPLACE TABLE DEMO_DIM AS
SELECT * FROM DIM_CLIENTE WHERE CLIENTE_KEY = 102022;

SELECT D.R_NAME, COUNT(DISTINCT F.L_ORDERKEY) AS PEDIDOS, ROUND(SUM(F.INGRESO), 2) AS INGRESO
FROM FACT_LINEITEM F JOIN DEMO_DIM D ON F.CLIENTE_KEY = D.CLIENTE_KEY
GROUP BY D.R_NAME;
-- Esperado (antes): ASIA, 41 pedidos, 6 039 653.63.

-- Paso 33.3 · Cuántos de los 41 pedidos son anteriores a la supuesta mudanza
SELECT COUNT(DISTINCT L_ORDERKEY) AS PEDIDOS_ANTES_DEL_1995_06_01,
       ROUND(SUM(INGRESO), 2) AS INGRESO
FROM FACT_LINEITEM
WHERE CLIENTE_KEY = 102022 AND FECHA < DATE '1995-06-01';
-- Esperado: 19 pedidos; 2 951 661.88.

-- Paso 33.4 · Tipo 1: se sobrescribe la fila y se repite la consulta
UPDATE DEMO_DIM SET N_NAME = 'FRANCE', R_NAME = 'EUROPE' WHERE CLIENTE_KEY = 102022;

SELECT D.R_NAME, COUNT(DISTINCT F.L_ORDERKEY) AS PEDIDOS, ROUND(SUM(F.INGRESO), 2) AS INGRESO
FROM FACT_LINEITEM F JOIN DEMO_DIM D ON F.CLIENTE_KEY = D.CLIENTE_KEY
GROUP BY D.R_NAME;
-- Esperado (después): EUROPE, 41 pedidos, 6 039 653.63. ASIA ya no aparece: pierde los
--   6 039 653.63, incluidos los 2 951 661.88 de los 19 pedidos de 1992 a mayo de 1995.

-- Paso 33.5 · La historia se perdió: la dimensión solo guarda la versión nueva
SELECT CLIENTE_KEY, N_NAME, R_NAME FROM DEMO_DIM;
-- Esperado: 1 fila: 102022, FRANCE, EUROPE. Nada indica que antes estuvo en INDONESIA.

-- Paso 33.6 · «O_TOTALPRICE sí incluye impuesto»: ya demostrado en el bloque 6 (paso 6.4).
--   Ingreso sin impuesto 6 039 653.63; con impuesto 6 273 789.73; O_TOTALPRICE 6 273 788.41.


-- =====================================================================
-- SLIDE 34 · SCD tipo 2 conserva la historia
-- Afirmación en pantalla: «Mudanza supuesta, SCD tipo 2: por fecha del pedido, 19 van a ASIA
--   y 22 a EUROPE.» Tabla: versión 1 (clave sustituta), INDONESIA, ASIA, desde 1992-01-01,
--   hasta 1995-05-31, 19 pedidos; versión 2, FRANCE, EUROPE, desde 1995-06-01, hasta
--   9999-12-31 (sin fin), 22 pedidos.
-- Qué demuestra cada paso:
--   34.1  la dimensión con dos versiones (la fila vigente se cierra y se inserta la nueva).
--   34.2  la unión con el hecho por la clave de negocio y FECHA BETWEEN DESDE AND HASTA reparte
--         los pedidos: 19 y 22, que suman 41.
--   34.3  el reparto no duplica ni pierde líneas: 163 líneas antes y después.
--   34.4  los importes también cuadran: 2 951 661.88 + 3 087 991.75 = 6 039 653.63.
-- Requiere: bloque 28.
-- =====================================================================
USE SCHEMA CURSO_EVIDENCIA_C3.ESTRELLA;

-- Paso 34.1 · La dimensión con dos versiones
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

SELECT SK, N_NAME, R_NAME, DESDE, HASTA FROM DEMO_DIM_SCD2 ORDER BY SK;
-- Esperado: (1, INDONESIA, ASIA, 1992-01-01, 1995-05-31) y (2, FRANCE, EUROPE, 1995-06-01,
--   9999-12-31).

-- Paso 34.2 · Pedidos por versión (la tabla de la slide)
SELECT D.SK, D.N_NAME, D.R_NAME, D.DESDE, D.HASTA,
       COUNT(DISTINCT F.L_ORDERKEY) AS PEDIDOS, ROUND(SUM(F.INGRESO), 2) AS INGRESO
FROM DEMO_DIM_SCD2 D
LEFT JOIN FACT_LINEITEM F ON F.CLIENTE_KEY = D.CLIENTE_KEY
                         AND F.FECHA BETWEEN D.DESDE AND D.HASTA
GROUP BY D.SK, D.N_NAME, D.R_NAME, D.DESDE, D.HASTA
ORDER BY D.SK;
-- Esperado: SK 1, INDONESIA, ASIA, 1992-01-01, 1995-05-31, 19 pedidos, 2 951 661.88;
--   SK 2, FRANCE, EUROPE, 1995-06-01, 9999-12-31, 22 pedidos, 3 087 991.75.

-- Paso 34.3 · El rango no duplica ni pierde líneas
SELECT (SELECT COUNT(*) FROM FACT_LINEITEM WHERE CLIENTE_KEY = 102022) AS LINEAS_DEL_CLIENTE,
       COUNT(*) AS LINEAS_TRAS_LA_UNION,
       COUNT(DISTINCT F.L_ORDERKEY) AS PEDIDOS,
       ROUND(SUM(F.INGRESO), 2) AS INGRESO_TOTAL
FROM FACT_LINEITEM F
JOIN DEMO_DIM_SCD2 D ON F.CLIENTE_KEY = D.CLIENTE_KEY
                    AND F.FECHA BETWEEN D.DESDE AND D.HASTA;
-- Esperado: LINEAS_DEL_CLIENTE 163; LINEAS_TRAS_LA_UNION 163; PEDIDOS 41;
--   INGRESO_TOTAL 6 039 653.63 (igual al total sin mudanza del bloque 33).


-- =====================================================================
-- SLIDE 35 · Lab 3C: construir la estrella y compruebas que cuadra
-- Afirmación en pantalla: «Mide cuál paso de tu carga costó más y abre su Query Profile.»
--   (el resto son instrucciones del lab).
-- Qué demuestra cada paso (con la carga del paso 28.0, marcada EVID_C3_ESTRELLA):
--   35.1  el tiempo de cada CREATE TABLE de la carga, de mayor a menor: el más caro es
--         FACT_LINEITEM (unos 2 a 3 s en X-Small; las dimensiones, de 0.5 a 1.5 s).
--   35.2  en su perfil, el operador que concentra el tiempo es CreateTableAsSelect, seguido
--         del TableScan de LINEITEM.
-- Requiere: bloque 28 (paso 28.0), en la misma sesión.
-- =====================================================================
USE SCHEMA CURSO_EVIDENCIA_C3.ESTRELLA;

-- Paso 35.1 · Tiempo por paso de la carga
SELECT REGEXP_SUBSTR(QUERY_TEXT, $$CREATE OR REPLACE TABLE \w+$$) AS PASO,
       ROUND(EXECUTION_TIME / 1000, 2) AS SEGUNDOS, QUERY_ID
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(RESULT_LIMIT => 500))
WHERE QUERY_TAG = 'EVID_C3_ESTRELLA' AND QUERY_TYPE = 'CREATE_TABLE_AS_SELECT'
ORDER BY EXECUTION_TIME DESC;
-- Esperado: 4 filas; la primera, CREATE OR REPLACE TABLE FACT_LINEITEM, de 2 a 3 s (2.24
--   el 9 nov.); DIM_PRODUCTO 1.15, DIM_CLIENTE 0.81 y DIM_FECHA 0.63 s. (Si corriste el
--   bloque 28 más de una vez, saldrán más filas: toma las más recientes.)

-- Paso 35.2 · Operador que concentra el tiempo en la carga del hecho
SET Q35 = (SELECT QUERY_ID
           FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(RESULT_LIMIT => 500))
           WHERE QUERY_TAG = 'EVID_C3_ESTRELLA' AND QUERY_TYPE = 'CREATE_TABLE_AS_SELECT'
             AND QUERY_TEXT ILIKE '%TABLE FACT_LINEITEM%'
           ORDER BY START_TIME DESC
           LIMIT 1);
SELECT OPERATOR_TYPE,
       ROUND(EXECUTION_TIME_BREAKDOWN:overall_percentage::FLOAT * 100, 1) AS PCT_DEL_TIEMPO
FROM TABLE(GET_QUERY_OPERATOR_STATS($Q35))
WHERE OPERATOR_TYPE <> 'CREATE TABLE'   -- la raíz del plan, siempre 100 %
ORDER BY PCT_DEL_TIEMPO DESC NULLS LAST
LIMIT 3;
-- Esperado: CreateTableAsSelect primero. El 9 nov.: 71.3 % (con TableScan 25.0 %) en una
--   corrida y 91.7 % (con Join 3.3 %) en otra; lab3c_solucion.sql (8 nov.) dio 93 a 98 %: el
--   rango medido en total es 71 a 98 %, el que muestran demos.sql y lab3c_solucion.sql. El reparto
--   varía con la caché de datos del warehouse.


-- =====================================================================
-- SLIDE 36 · Una estrella cuadra cuando pasan cuatro controles
-- Afirmación en pantalla: «Una estrella cuadra cuando pasan cuatro controles: filas, grano,
--   claves sin pareja e ingreso.» «Un control dice si el dato es correcto; el tiempo por paso
--   dice cuánto costó obtenerlo. Origen: 6 001 215 filas y claves; 0 sin cliente; ingreso
--   218 102 223 885.»
-- Qué demuestra cada paso:
--   36.1  los valores esperados salen del origen (SNOWFLAKE_SAMPLE_DATA), no se inventan.
--   36.2  los cuatro controles de la slide sobre la estrella: todos coinciden.
--   36.3  prueba negativa: con una dimensión que repite una clave, los controles lo detectan.
-- Requiere: bloque 28.
-- =====================================================================
USE SCHEMA CURSO_EVIDENCIA_C3.ESTRELLA;

-- Paso 36.1 · Los valores esperados, calculados en el origen
SELECT (SELECT COUNT(*) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM) AS LINEAS_ORIGEN,
       (SELECT COUNT(DISTINCT L_ORDERKEY * 10 + L_LINENUMBER)
        FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM) AS CLAVES_ORIGEN,
       (SELECT COUNT(*)
        FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O
        LEFT JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER C ON O.O_CUSTKEY = C.C_CUSTKEY
        WHERE C.C_CUSTKEY IS NULL) AS PEDIDOS_SIN_CLIENTE_ORIGEN,
       (SELECT ROUND(SUM(L_EXTENDEDPRICE * (1 - L_DISCOUNT)))
        FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM) AS INGRESO_ORIGEN;
-- Esperado: 6 001 215; 6 001 215; 0; 218 102 223 885.

-- Paso 36.2 · Los cuatro controles de la slide
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
-- Esperado: filas 6 001 215 (6 001 215); grano 6 001 215 (6 001 215); sin cliente 0 (0);
--   ingreso 218 102 223 885 (218 102 223 885). FACT igual a ESPERADO en las cuatro.

-- Paso 36.3 · Prueba negativa: una dimensión con una clave repetida
CREATE OR REPLACE TABLE DIM_CLIENTE_MALA AS
SELECT * FROM DIM_CLIENTE
UNION ALL
SELECT * FROM DIM_CLIENTE WHERE CLIENTE_KEY = 102022;

SELECT COUNT(*) AS FILAS_DEL_HECHO_TRAS_LA_UNION, COUNT(*) - 6001215 AS FILAS_DE_MAS,
       ROUND(SUM(F.INGRESO)) AS INGRESO
FROM FACT_LINEITEM F JOIN DIM_CLIENTE_MALA D USING (CLIENTE_KEY);
-- Esperado: 6 001 378 filas (163 de más: las líneas del cliente 102022, una vez más) e
--   ingreso 218 108 263 539, distinto de 218 102 223 885. Los controles «filas» e «ingreso»
--   habrían fallado.


-- =====================================================================
-- SLIDE 37 · Caso NYC
-- Afirmación en pantalla: «Caso NYC, lluvia y viajes: la estrella propuesta guardaría
--   LLUVIA_MM en 31 filas, no en 15 909.» Diagrama: 15 909 filas en enero 2024, grano fecha ×
--   zona × empresa; LLUVIA_MM un valor por día (31 en enero), no 511-515 filas por día; 261
--   zonas; empresas Uber y Lyft. Pie: «Hoy se repite en cada fila del gold.»
-- Qué demuestra cada paso:
--   37.1  el gold tiene 15 909 filas, 31 días, 261 zonas y 2 empresas.
--   37.2  cada día tiene entre 511 y 515 filas.
--   37.3  cada día tiene un solo valor de LLUVIA_MM: la lluvia se repite en todas sus filas.
-- La estrella de NYC es una propuesta de diseño: no hay nada que medir en ella.
-- Requiere: BIGDATA.DEV.DAILY_ZONE_METRICS (gold de la clase 1). Si no existe, cada paso
--   devuelve un AVISO.
-- =====================================================================

-- Paso 37.1 · Dimensiones del gold
EXECUTE IMMEDIATE $$
DECLARE
  r RESULTSET;
BEGIN
  r := (SELECT COUNT(*) AS FILAS, COUNT(DISTINCT FECHA) AS DIAS, COUNT(DISTINCT ZONA) AS ZONAS,
               COUNT(DISTINCT EMPRESA) AS EMPRESAS, SUM(VIAJES) AS VIAJES
        FROM BIGDATA.DEV.DAILY_ZONE_METRICS);
  RETURN TABLE(r);
EXCEPTION
  WHEN OTHER THEN
    r := (SELECT 'AVISO: no existe BIGDATA.DEV.DAILY_ZONE_METRICS en esta cuenta' AS AVISO);
    RETURN TABLE(r);
END;
$$;
-- Esperado: FILAS 15 909; DIAS 31; ZONAS 261; EMPRESAS 2; VIAJES 19 650 023.

-- Paso 37.2 · Filas por día
EXECUTE IMMEDIATE $$
DECLARE
  r RESULTSET;
BEGIN
  r := (SELECT MIN(N) AS FILAS_POR_DIA_MIN, MAX(N) AS FILAS_POR_DIA_MAX
        FROM (SELECT FECHA, COUNT(*) AS N
              FROM BIGDATA.DEV.DAILY_ZONE_METRICS
              GROUP BY FECHA));
  RETURN TABLE(r);
EXCEPTION
  WHEN OTHER THEN
    r := (SELECT 'AVISO: no existe BIGDATA.DEV.DAILY_ZONE_METRICS en esta cuenta' AS AVISO);
    RETURN TABLE(r);
END;
$$;
-- Esperado: FILAS_POR_DIA_MIN 511; FILAS_POR_DIA_MAX 515.

-- Paso 37.3 · Valores distintos de LLUVIA_MM por día
EXECUTE IMMEDIATE $$
DECLARE
  r RESULTSET;
BEGIN
  r := (SELECT MAX(VALORES) AS MAX_VALORES_DISTINTOS_POR_DIA, COUNT(*) AS DIAS
        FROM (SELECT FECHA, COUNT(DISTINCT LLUVIA_MM) AS VALORES
              FROM BIGDATA.DEV.DAILY_ZONE_METRICS
              GROUP BY FECHA));
  RETURN TABLE(r);
EXCEPTION
  WHEN OTHER THEN
    r := (SELECT 'AVISO: no existe BIGDATA.DEV.DAILY_ZONE_METRICS en esta cuenta' AS AVISO);
    RETURN TABLE(r);
END;
$$;
-- Esperado: MAX_VALORES_DISTINTOS_POR_DIA 1; DIAS 31. Una estrella con DIM_FECHA guardaría
--   esos 31 valores una sola vez; el gold actual los repite en 15 909 filas.


-- =====================================================================
-- SLIDE 38 · Cierre
-- Afirmación en pantalla: «Tres problemas resueltos; la clase 4 lleva 239.5 M de viajes de
--   NYC a un lake.» Diagrama: promedio ponderado (SUM / SUM) 151 219.54, igual al directo;
--   de 4 uniones a 1; ejecución casi a la mitad en esta medición; 4 controles. «Lake: almacén
--   de archivos.» «La pregunta de la lluvia la responde el Taller 1, 15 nov.»
-- Qué demuestra cada paso:
--   38.1  151 219.54, el promedio directo y ponderado: bloque 22.
--   38.2  de 4 uniones a 1 y ejecución casi a la mitad: bloque 26 (pasos 26.3 y 26.4b).
--   38.3  los 4 controles: bloque 36.
--   38.4  239.5 M de viajes de NYC en 2024: no está en Snowflake. Es el conteo de los 12
--         archivos Parquet FHVHV de 2024 que midió la corrida de Glue
--         (validacion/resultados.md, línea 234; validacion/contenido/clase01_datos_reales.md,
--         tabla de la sección 4.4). Enero solo: 19 650 023 viajes, que sí suma el gold
--         (bloque 37, paso 37.1).
--   El Taller 1 y su fecha son calendario del curso, no medibles.
-- =====================================================================

-- Paso 38.1 · El promedio directo de la slide 22, en una línea
SELECT ROUND(AVG(O_TOTALPRICE), 2) AS PROMEDIO_DIRECTO
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS;
-- Esperado: 151 219.54.


-- =====================================================================
-- FIN · Borrar la base de la evidencia
-- Qué hace: borra CURSO_EVIDENCIA_C3 con todas sus tablas (ESTRELLA, SF10 y PUBLIC). Es lo
--   único que creó este archivo. Los 1.5 GB del hecho de SF10 se liberan aquí.
-- =====================================================================
DROP DATABASE IF EXISTS CURSO_EVIDENCIA_C3;
-- Si dejaste COMPUTE_WH encendido, se suspende solo a los 60 s. Para suspenderlo ya:
--   ALTER WAREHOUSE COMPUTE_WH SUSPEND;   -- error 090064 si ya estaba suspendido: ignorar.
