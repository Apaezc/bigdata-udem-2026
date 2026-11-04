-- =====================================================================
-- CLASE 2 · Guion de demos en vivo del instructor (Snowsight)
-- =====================================================================
--
-- Numeración de slides: final. QP1 a QP8 son las slides 47 a 54; las
-- slides de la versión anterior 47 a 56 son ahora 55 a 64.
-- «corta: M» = número en el deck corto de 30 slides (deck_corto/slides.pdf).
-- Fuente de cifras: clase02_demos_medidas_v2.md (principal) y
-- clase02_demos_medidas.md (v1, solo COUNT(*), caché y costo).
-- Las cifras marcadas [orq] vienen de consultas de lectura del 2026-11-03.
-- Las cifras de QP5 y QP7 son del informe clase02_query_profile.md
-- (casos 1 y 4; medición en caliente, r2).
--
-- PREPARACIÓN (antes de la clase, no en pantalla)
--   USE ROLE ACCOUNTADMIN;
--   USE WAREHOUSE COMPUTE_WH;      -- XSMALL, AUTO_SUSPEND = 60
--   ALTER SESSION SET USE_CACHED_RESULT = FALSE;
--   SELECT 1;                      -- solo reanuda el warehouse; no ejecutes
--                                  -- antes las consultas de las demos
--   Si el warehouse estaba suspendido, ejecuta SELECT 1; unos 30 s antes
--   de cada demo. Para las demos de talla, DEMO_M_WH (Medium) se reanuda
--   con SELECT 1; igual.
--
-- LECTURA DEL QUERY PROFILE
--   En el panel de resultados, Query Details > botón de tres puntos >
--   View Query Profile; o Monitoring > Query History > consulta > pestaña
--   Query Profile. Nodo TableScan: Bytes scanned, Partitions scanned y
--   Partitions total. Para releer el perfil de una
--   consulta ya ejecutada: ALTER SESSION SET USE_CACHED_RESULT = FALSE;
--   y volver a correrla.
--
-- PLAN B: si Snowsight no responde o una cifra se desvía mucho, muestra la
--   tabla medida (slides y notas) y di que se midió el 3 de noviembre.
--
-- ALTER WAREHOUSE ... SUSPEND puede devolver el error 090064 si ya está
-- suspendido; ese error es esperado y se ignora.
-- =====================================================================


-- =====================================================================
-- DEMO 1 · Slide 4 (corta: 3) · Sumar 600 M de líneas
-- Qué se muestra: TableScan de LINEITEM: bytes leídos y 1 022 de 1 022
--   micro-particiones. Una sola fila de resultado.
-- Resultado esperado (medido, X-Small, caché de resultados desactivada):
--   en frío 2.50 s (1.95 GB); en caliente 0.63 y 0.67 s (1.83 GB);
--   1 fila; 1 022 de 1 022 micro-particiones [v2 P4].
-- =====================================================================
USE WAREHOUSE COMPUTE_WH;
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT SUM(L_EXTENDEDPRICE) AS IMPORTE
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.LINEITEM;


-- =====================================================================
-- DEMO 2 · Slide 7 (corta: 6) · Columnas: 0.6 GB una numérica, 6.4 GB un texto
-- Qué se muestra: dos TableScan de LINEITEM en SF100 con mismas
--   particiones (1 022 de 1 022) y bytes muy distintos.
--   Suspender COMPUTE_WH antes de cada consulta (ver la nota del error
--   090064 al inicio del archivo).
-- Resultado esperado (medido, X-Small, en frío):
--   SUM(L_QUANTITY): 4.89 s y 0.60 GB.
--   MAX(L_COMMENT):  10.53 s y 6.37 GB; 1 022 de 1 022 [v2 P2].
-- =====================================================================
USE WAREHOUSE COMPUTE_WH;
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
ALTER WAREHOUSE COMPUTE_WH SUSPEND;

SELECT SUM(L_QUANTITY) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.LINEITEM;

ALTER WAREHOUSE COMPUTE_WH SUSPEND;

SELECT MAX(L_COMMENT) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.LINEITEM;


-- =====================================================================
-- DEMO 3 · Slide 9 (corta: 7) · Filtrar por un mes baja el tiempo y los bytes
-- Qué se muestra: Partitions scanned contra Partitions total en cada
--   una. Decir en voz alta que sin filtro el número de particiones varió
--   entre ejecuciones (QAS hace parte del escaneo; el dato es indicativo).
-- Resultado esperado (medido, X-Small, SF1000):
--   Sin filtro: 5.5 a 6.5 s; 19.2 GB totales (WH + QAS).
--   Con el mes de L_SHIPDATE: 2.03 s, 0.25 GB de warehouse y
--   134 de 10 336 micro-particiones [v2 P3, P4].
--   La medición no registró el estado de la caché en la ejecución filtrada.
-- =====================================================================
USE WAREHOUSE COMPUTE_WH;
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT SUM(L_EXTENDEDPRICE)
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1000.LINEITEM;

SELECT SUM(L_EXTENDEDPRICE)
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1000.LINEITEM
WHERE L_SHIPDATE >= '1995-03-01' AND L_SHIPDATE < '1995-04-01';


-- =====================================================================
-- DEMO 4 · Slide 10 (corta: 7) · COUNT(*) sin filtro se responde sin leer datos
-- Qué se muestra: el COUNT(*) sin filtro no tiene TableScan con bytes
--   (0 bytes, solo metadatos). El segundo, con filtro sobre L_QUANTITY,
--   sí lee la columna.
-- Resultado esperado:
--   COUNT(*) sin filtro: 0.06 s, 0 bytes y 600 037 902 filas [v1 2; v1
--   no repetida en v2; el resultado exacto es [orq]].
--   Con filtro: la variante COUNT(*) WHERE L_QUANTITY > 10 no se midió
--   en v2. Referencia medida: SUM(L_QUANTITY) lee 0.60 GB y tarda 4.89 s
--   en frío [v2 P2]. Decir que el COUNT con filtro no tiene cifra propia.
-- =====================================================================
USE WAREHOUSE COMPUTE_WH;
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT COUNT(*) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.LINEITEM;

SELECT COUNT(*) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.LINEITEM
WHERE L_QUANTITY > 10;


-- =====================================================================
-- DEMO 5 · Slide 11 (corta: 8) · 10 veces más filas, unas 9 veces más tiempo
-- Qué se muestra: total de micro-particiones de cada tabla (1 022 en
--   SF100 y 10 336 en SF1000). No mostrar BYTES_SCANNED de la consulta:
--   no es estable (v2).
-- Resultado esperado (medido, X-Small, caché caliente):
--   SF100: 0.65 s y 1.83 GB totales.
--   SF1000: 6.0 s y 19.2 GB totales (media de las ejecuciones 3 a 5).
--   Razón 6.0 / 0.65 = 9.2. SF1000 no llegó a caché caliente: el 9 es
--   aproximado [v2 P4].
-- =====================================================================
USE WAREHOUSE COMPUTE_WH;
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT SUM(L_EXTENDEDPRICE) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.LINEITEM;
SELECT SUM(L_EXTENDEDPRICE) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.LINEITEM;
SELECT SUM(L_EXTENDEDPRICE) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1000.LINEITEM;
SELECT SUM(L_EXTENDEDPRICE) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1000.LINEITEM;
SELECT SUM(L_EXTENDEDPRICE) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1000.LINEITEM;


-- =====================================================================
-- DEMO 6 · Slide 15 (corta: 11) · Medium contra X-Small en la misma consulta
-- Qué se muestra: porcentaje del TableScan frente a Aggregate (esta consulta
--   no tiene Join: solo TableScan, Aggregate y Result);
--   «Percentage scanned from cache»; micro-particiones que lee el
--   warehouse frente al total (QAS hace el resto). Consulta de la medición
--   v2 P1 (SF1000). Preparación: SELECT 1; en DEMO_M_WH unos 30 s antes.
-- Resultado esperado (medido, tres ejecuciones por talla):
--   X-Small: 14.26, 16.84 y 8.56 s (media 13.2 s; 0.0037 créditos por consulta).
--   Medium:  10.43, 9.45 y 7.47 s (media 9.1 s; 0.0101 créditos).
--   Medium 1.45 veces más rápido y 2.8 veces más caro por consulta.
--   Ejecuciones completas: 9 144 de 10 336 micro-particiones en ambas tallas.
--   Sin spill real: solo aparece un remoto de fondo de 31 a 44 KB [v2 P1].
-- =====================================================================
USE WAREHOUSE COMPUTE_WH;
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT L_RETURNFLAG, L_LINESTATUS, SUM(L_EXTENDEDPRICE), AVG(L_DISCOUNT)
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1000.LINEITEM
WHERE L_SHIPDATE < '1998-01-01'
GROUP BY 1,2;

USE WAREHOUSE DEMO_M_WH;

SELECT L_RETURNFLAG, L_LINESTATUS, SUM(L_EXTENDEDPRICE), AVG(L_DISCOUNT)
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1000.LINEITEM
WHERE L_SHIPDATE < '1998-01-01'
GROUP BY 1,2;

USE WAREHOUSE COMPUTE_WH;
-- Error 090064 si DEMO_M_WH ya estaba suspendido: ignorar.
ALTER WAREHOUSE DEMO_M_WH SUSPEND;


-- =====================================================================
-- DEMO 7 · Slide 16 (corta: 11) · Caché de resultados
-- Qué se muestra: la segunda ejecución no tiene TableScan; el perfil
--   muestra reutilización de resultado. Comprobar en vivo el nombre del
--   nodo. Esta consulta reaparece en la slide 36 (corta: 17).
-- Resultado esperado (medido, X-Small):
--   Primera ejecución: 2.14 s y 2.07 GB por operador.
--   Segunda: 0.05 s, 0 bytes y 0 micro-particiones; 7 filas [v1 5].
--   Esta demo deja USE_CACHED_RESULT = TRUE; las demos siguientes lo
--   desactivan de nuevo.
-- =====================================================================
USE WAREHOUSE COMPUTE_WH;
-- Primera ejecución sin caché de resultados, para que sea siempre en frío
-- aunque la consulta se haya corrido en las últimas 24 h.
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT L_SHIPMODE, COUNT(*), SUM(L_EXTENDEDPRICE)
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.LINEITEM
GROUP BY 1;

-- Segunda ejecución: se activa la caché y la misma consulta sale de ella.
ALTER SESSION SET USE_CACHED_RESULT = TRUE;

SELECT L_SHIPMODE, COUNT(*), SUM(L_EXTENDEDPRICE)
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.LINEITEM
GROUP BY 1;


-- =====================================================================
-- DEMO 7b · Slide 36 (corta: 17) · GROUP BY reduce 600 M de líneas a 7 filas
-- Qué se muestra: la misma consulta de la slide 16 (corta: 11), ahora para ver qué hace
--   GROUP BY: una fila por modo de envío, con COUNT(*) y SUM por grupo.
--   Sale de la caché de resultados (la demo 7 dejó USE_CACHED_RESULT = TRUE).
-- Resultado esperado (medido, X-Small): 0.05 s, 0 bytes y 7 filas; la
--   primera ejecución (demo 7) midió 2.14 s [v1 5].
-- =====================================================================
USE WAREHOUSE COMPUTE_WH;
ALTER SESSION SET USE_CACHED_RESULT = TRUE;

SELECT L_SHIPMODE, COUNT(*), SUM(L_EXTENDEDPRICE)
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.LINEITEM
GROUP BY 1;


-- =====================================================================
-- DEMO 8 · Slide 37 (corta: 17) · WHERE filtra filas, HAVING filtra grupos
-- Qué se muestra: TableScan de ORDERS con 10 de 10 micro-particiones en
--   SF1 (el filtro de fecha no poda en SF1); el orden lógico en el texto.
-- Resultado esperado (medido, [orq]): 5 filas:
--   63733, 107440, 115471, 120877 (12) y 14920 (11).
-- =====================================================================
USE WAREHOUSE COMPUTE_WH;
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT O_CUSTKEY, COUNT(*) AS PEDIDOS
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_ORDERDATE >= '1995-01-01' AND O_ORDERDATE < '1996-01-01'
GROUP BY O_CUSTKEY
HAVING COUNT(*) >= 8
ORDER BY PEDIDOS DESC, O_CUSTKEY
LIMIT 5;


-- =====================================================================
-- DEMO 9 · Slide 39 (corta: 17) · WHERE no admite agregaciones
-- Qué se muestra: el error de compilación. No hay Query Profile: la
--   consulta no llega a ejecutarse. Se lee el mensaje en voz alta.
-- Resultado esperado (error de compilación, [orq]):
--   Invalid aggregate function in where clause [COUNT(*)]
-- =====================================================================
USE WAREHOUSE COMPUTE_WH;

SELECT O_CUSTKEY, COUNT(*)
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE COUNT(*) > 8
GROUP BY O_CUSTKEY;


-- =====================================================================
-- DEMO 10 · Slide 40 (corta: 17) · Columna fuera de GROUP BY
-- Qué se muestra: el error de compilación. No hay Query Profile.
-- Resultado esperado (error de compilación, [orq]):
--   'CUSTOMER.C_NAME' in select clause is neither an aggregate nor in the group by clause
-- =====================================================================
USE WAREHOUSE COMPUTE_WH;

SELECT C_MKTSEGMENT, C_NAME, COUNT(*)
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER
GROUP BY C_MKTSEGMENT;


-- =====================================================================
-- DEMO 11 · Slide 43 (corta: 19) · Unir pedidos con líneas repite cada pedido
-- Qué se muestra: el conteo de filas antes y después del JOIN, y la
--   suma de O_TOTALPRICE antes y después. Es la misma tabla, la suma se
--   infla al unir.
-- Resultado esperado [orq]:
--   COUNT(*) ORDERS: 1 500 000; COUNT(*) ORDERS JOIN LINEITEM: 6 001 215.
--   SUM(O_TOTALPRICE) ORDERS: 226 829 306 447.46;
--   SUM(O_TOTALPRICE) después del JOIN: 1 134 436 101 880.19 (5 veces).
-- =====================================================================
USE WAREHOUSE COMPUTE_WH;
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT COUNT(*) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS;

SELECT COUNT(*)
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM L
  ON O.O_ORDERKEY = L.L_ORDERKEY;

SELECT SUM(O_TOTALPRICE) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS;

SELECT SUM(O.O_TOTALPRICE)
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM L
  ON O.O_ORDERKEY = L.L_ORDERKEY;


-- =====================================================================
-- DEMO 12 · Slide 45 (corta: 21) · COUNT(DISTINCT) cuenta cada clave una vez
-- Qué se muestra: FILAS contra CLIENTES por segmento después del JOIN.
--   Es el caso que la clase 3 resuelve agregando antes de unir.
-- Resultado esperado [orq]:
--   AUTOMOBILE: 297 453 filas y 19 876 clientes.
--   BUILDING:   303 959 filas y 20 177 clientes.
-- =====================================================================
USE WAREHOUSE COMPUTE_WH;
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT C.C_MKTSEGMENT,
       COUNT(*) AS FILAS,
       COUNT(DISTINCT C.C_CUSTKEY) AS CLIENTES
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER C
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS O
  ON C.C_CUSTKEY = O.O_CUSTKEY
GROUP BY C.C_MKTSEGMENT;


-- =====================================================================
-- QP5 · Slide 51 (corta: 24) · Proyección: SELECT * contra tres columnas (caso 1)
-- Qué se muestra: el TableScan de LINEITEM en SF10 lee 1.72 GB con
--   SELECT * y 0.45 GB con tres columnas. Las particiones no cambian
--   (116 de 116 en ambas). HASH_AGG(*) obliga a leer las columnas sin
--   transferir filas. Demo en vivo: menos de 2 s en ambas versiones.
-- Resultado esperado (informe, caso 1, caliente):
--   Antes (SELECT *): 1 456 ms; TableScan 1 720 348 768 bytes; 116 / 116.
--   Después (3 columnas): 289 ms; TableScan 445 726 720 bytes; 116 / 116.
--   Operador dominante: TableScan 86.55 % y 81.82 %.
--   Advertencia del informe: BYTES_SCANNED de QUERY_HISTORY no sirve aquí
--   (1 716 809 824 en ambas); usar los bytes del operador TableScan.
-- =====================================================================
USE WAREHOUSE COMPUTE_WH;
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

-- Antes
SELECT HASH_AGG(*) AS H FROM (
  SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM
  WHERE L_SHIPDATE >= '1995-01-01' AND L_SHIPDATE < '1996-01-01');

-- Después
SELECT HASH_AGG(*) AS H FROM (
  SELECT L_ORDERKEY, L_EXTENDEDPRICE, L_SHIPDATE
  FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM
  WHERE L_SHIPDATE >= '1995-01-01' AND L_SHIPDATE < '1996-01-01');


-- =====================================================================
-- QP7 · Slide 53 (corta: 26) · Join con llave incompleta (caso 4)
-- Qué se muestra: el nodo Join de la versión con una sola llave muestra
--   la explosión: 239 944 208 filas de salida frente a 59 986 052 (la
--   cardinalidad de LINEITEM) con dos llaves. Demo en vivo: menos de 2 s.
--   Decir que el número de filas es la señal, no el tiempo.
-- Resultado esperado (informe, caso 4, caliente):
--   Antes (1 llave): COUNT(*) 239 944 208; 1 424 ms; Join 88.64 %;
--     TableScan 182 755 328 bytes; 148 / 148.
--   Después (2 llaves): COUNT(*) 59 986 052; 871 ms; Join 63.33 %;
--     TableScan 327 942 144 bytes; 148 / 148.
--   Nota del informe: el operador Join de la versión con 2 llaves reporta
--   59 968 602 filas de salida, 17 450 menos que el COUNT final; esa
--   diferencia no está explicada. No se afirma en voz alta.
-- =====================================================================
USE WAREHOUSE COMPUTE_WH;
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

-- Antes (llave incompleta)
SELECT COUNT(*) AS N
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM L
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.PARTSUPP PS
  ON L.L_PARTKEY = PS.PS_PARTKEY;

-- Después (llave completa)
SELECT COUNT(*) AS N
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM L
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.PARTSUPP PS
  ON L.L_PARTKEY = PS.PS_PARTKEY AND L.L_SUPPKEY = PS.PS_SUPPKEY;


-- =====================================================================
-- QP8 · Slide 54 (corta: 27) · Spilling (SOLO COMENTARIO; NO SE EJECUTA EN VIVO)
-- La consulta tarda 48 s en X-Small: no cabe en la clase. Mostrar
-- capturas de los dos perfiles, no ejecutarla.
--   Consulta: ROW_NUMBER() OVER (PARTITION BY L_ORDERKEY ORDER BY
--   L_EXTENDEDPRICE) sobre SNOWFLAKE_SAMPLE_DATA.TPCH_SF100.LINEITEM,
--   agregada a COUNT(*) y MAX(RN).
--   QID XS:     01c830a8-0209-8e46-0012-59ae000b20e2 (48.4 s; 4.73 GB
--               derramados a disco local; WindowFunction 59.6 %).
--   QID MEDIUM: 01c830a9-0209-96bf-0012-59ae000b7102 (11.0 s; 0 bytes
--               derramados; WindowFunction 52.9 %).
--   Fuente: clase02_query_profile.md, «Caso 6 · Spilling».
-- =====================================================================


-- =====================================================================
-- DEMO 13 · Slide 58 (corta: 29) · Q4 del mini-caso
-- Qué se muestra: Árbol del plan, TableScan de LINEITEM y estadísticas
--   de las tres cifras: bytes leídos, micro-particiones y el operador
--   dominante. Caché de resultados desactivada.
-- Resultado esperado [orq], SF10, X-Small, 3 ejecuciones:
--   TableScan LINEITEM 393 581 216 bytes (0.39 GB); 116 de 116
--   micro-particiones; 60.6 % del tiempo en la primera ejecución.
--   Tiempo total 5.69, 5.90 y 2.66 s (2.7 a 5.9 s). 35 filas (5 regiones
--   por 7 modos de envío). Ejecución 2 y 3: 8.9 % y 6.7 % para el
--   TableScan; operador dominante Aggregate o Join (26.8 % a 31.7 %).
-- =====================================================================
USE WAREHOUSE COMPUTE_WH;
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT R.R_NAME AS REGION, L.L_SHIPMODE AS MODO_ENVIO, COUNT(*) AS LINEAS,
       SUM(L.L_EXTENDEDPRICE) AS IMPORTE_LINEAS
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.LINEITEM L
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS O ON L.L_ORDERKEY = O.O_ORDERKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.CUSTOMER C ON O.O_CUSTKEY = C.C_CUSTKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.NATION N ON C.C_NATIONKEY = N.N_NATIONKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.REGION R ON N.N_REGIONKEY = R.R_REGIONKEY
GROUP BY R.R_NAME, L.L_SHIPMODE
ORDER BY REGION, IMPORTE_LINEAS DESC, MODO_ENVIO;


-- =====================================================================
-- CIERRE DE LAS DEMOS
-- =====================================================================
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
