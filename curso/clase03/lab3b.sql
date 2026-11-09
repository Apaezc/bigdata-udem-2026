-- =====================================================================
-- LAB 3B · QUALIFY, CTE y promedio ponderado (Big Data UdeM · Clase 3)
-- =====================================================================
--
-- OBJETIVO
--   Filtrar ventanas con QUALIFY sin anidar consultas, encadenar pasos con CTE y corregir un
--   promedio de promedios con el promedio ponderado.
--
-- GLOSARIO (solo lo nuevo respecto del Lab 3A)
--   QUALIFY            cláusula que filtra después de calcular las ventanas.
--   CTE                consulta con nombre (WITH nombre AS (...)), válida solo dentro de la
--                      sentencia; no guarda datos.
--   promedio ponderado suma de (n * promedio) dividida entre la suma de n.
--
-- CÓMO COPIAR ESTE ARCHIVO A SNOWSIGHT (solo navegador, sin terminal)
--   1. En tu fork: carpeta curso > clase03 > lab3b.sql.
--   2. Arriba a la derecha del contenido, el ícono de dos cuadritos es "Copy raw file"
--      (no el de la flecha hacia abajo).
--   3. En Snowsight: Projects > Worksheets > botón + (SQL Worksheet). Si tu Snowsight muestra
--      "Workspaces", usa + > SQL File.
--   4. Pega todo (Ctrl/Cmd + V). No elijas rol ni warehouse: el Paso 0 los fija.
--   5. Si no ves el archivo: botón "Sync fork" > "Update branch".
--
-- CÓMO CORRER
--   Paso 0: selecciona de USE ROLE a USE SCHEMA CURSO.LAB3B; y pulsa ▶.
--   Punto de partida: corre las tres consultas anidadas (no crean nada) para ver el resultado
--   que B1 a B3 deben reproducir.
--   Ejercicios: bloque a bloque con Cmd/Ctrl+Enter (corre la consulta donde está el cursor).
--   Run All corre todo el archivo: en este archivo NO lo uses.
--
-- TIEMPO: 14 min en clase. Núcleo: B1 a B4 (★; la verificación exige los cuatro). B5 es ★★.
--   Los resultados de B1 a B3 son idénticos a EJ1 a EJ3 del Lab 3A (misma salida, columnas y
--   orden); no necesitas haber terminado el Lab 3A.
--
-- NIVELES
--   ★    núcleo: cuatro ejercicios; la verificación exige los cuatro
--   ★★   si queda tiempo
--
-- VERIFICACIÓN DE ESTILO
--   B1, B2 y B3 deben usar QUALIFY: la verificación compara el resultado y revisa que la
--   definición de la vista contenga la palabra QUALIFY. Si el resultado es correcto pero la
--   vista no usa QUALIFY, da REVISAR con la pista «Usa QUALIFY». Límite: es una revisión
--   superficial; un comentario con la palabra QUALIFY también la satisface.
--
-- DICCIONARIO RÁPIDO (TPC-H, factor de escala 1)
--   ORDERS    O_ORDERKEY, O_CUSTKEY, O_ORDERSTATUS, O_TOTALPRICE, O_ORDERDATE, O_ORDERPRIORITY
--   LINEITEM  L_ORDERKEY, L_EXTENDEDPRICE, L_DISCOUNT
--   CUSTOMER  C_CUSTKEY, C_NATIONKEY, C_MKTSEGMENT, C_ACCTBAL
--   NATION    N_NATIONKEY, N_NAME, N_REGIONKEY
--   REGION    R_REGIONKEY, R_NAME
--   Las tablas viven en SNOWFLAKE_SAMPLE_DATA.TPCH_SF1 (solo lectura). Escribe siempre la ruta
--   completa, por ejemplo SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS.
--
-- =====================================================================
-- CÓMO ESCRIBIR CADA EJERCICIO (la misma plantilla en todos)
-- =====================================================================
-- Escribes solo en el lugar del marcador (la línea SELECT NULL AS PENDIENTE):
--
--   ANTES (así llega el archivo):
--     CREATE OR REPLACE VIEW B1 AS
--     -- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
--     SELECT NULL AS PENDIENTE
--     -- ▲▲ hasta aquí ▲▲
--     ;
--     SELECT * FROM B1;  -- mira tu resultado
--
--   DESPUÉS (reemplazas el marcador por tu SELECT, sin ; al final del SELECT):
--     CREATE OR REPLACE VIEW B1 AS
--     -- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
--     SELECT R_NAME, ROW_NUMBER() OVER (ORDER BY R_NAME) AS RN
--     FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION
--     -- ▲▲ hasta aquí ▲▲
--     ;
--     SELECT * FROM B1;  -- mira tu resultado
--
-- Ejecuta los dos bloques con Cmd/Ctrl+Enter. Debes ver "View B1 successfully created" y
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
-- QUÉ HACER: selecciona con el mouse desde USE ROLE hasta USE SCHEMA CURSO.LAB3B; y pulsa ▶.
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

-- TU BASE DE TRABAJO: CURSO es la base de datos y LAB3B el esquema donde se guardan tus objetos.
CREATE DATABASE IF NOT EXISTS CURSO;
CREATE SCHEMA IF NOT EXISTS CURSO.LAB3B;
USE SCHEMA CURSO.LAB3B;


-- =====================================================================
-- PUNTO DE PARTIDA · las consultas anidadas de EJ1, EJ2 y EJ3 del Lab 3A (ya escritas)
-- =====================================================================
-- Son las soluciones del Lab 3A. Córrelas con Cmd/Ctrl+Enter y fíjate en los niveles: la ventana
-- va dentro de un SELECT y el filtro afuera. En B1 a B3 las reescribes con QUALIFY.

-- Anidada 1 (EJ1): 3 pedidos más caros por prioridad.
SELECT O_ORDERPRIORITY, O_ORDERKEY, O_TOTALPRICE, RN
FROM (SELECT O_ORDERPRIORITY, O_ORDERKEY, O_TOTALPRICE,
             ROW_NUMBER() OVER (PARTITION BY O_ORDERPRIORITY
                                ORDER BY O_TOTALPRICE DESC, O_ORDERKEY) AS RN
      FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS)
WHERE RN <= 3
ORDER BY O_ORDERPRIORITY, RN;
-- Debes ver: 15 filas. Primera: 1-URGENT, 4722021, 544089.09, 1. Última: 5-LOW, 631651, 504509.06, 3.

-- Anidada 2 (EJ2): último pedido por cliente (muestra las 5 primeras filas).
SELECT * FROM (
  SELECT O_CUSTKEY, O_ORDERKEY, O_ORDERDATE
  FROM (SELECT O_CUSTKEY, O_ORDERKEY, O_ORDERDATE,
               ROW_NUMBER() OVER (PARTITION BY O_CUSTKEY
                                  ORDER BY O_ORDERDATE DESC, O_ORDERKEY DESC) AS RN
        FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS)
  WHERE RN = 1
  ORDER BY O_CUSTKEY
) ORDER BY O_CUSTKEY LIMIT 5;
-- Debes ver: 5 filas. Primera: cliente 1, pedido 4273923, 1997-03-23. La consulta completa devuelve 99996 filas.

-- Anidada 3 (EJ3): meses de 1995 que cayeron frente al mes anterior (tres niveles).
SELECT MES, MONTO, MONTO_ANTERIOR, VARIACION_PCT
FROM (SELECT MES, MONTO,
             LAG(MONTO) OVER (ORDER BY MES) AS MONTO_ANTERIOR,
             ROUND((MONTO - LAG(MONTO) OVER (ORDER BY MES))
                   / LAG(MONTO) OVER (ORDER BY MES) * 100, 2) AS VARIACION_PCT
      FROM (SELECT DATE_TRUNC('month', O_ORDERDATE) AS MES, SUM(O_TOTALPRICE) AS MONTO
            FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
            WHERE O_ORDERDATE >= '1995-01-01' AND O_ORDERDATE < '1996-01-01'
            GROUP BY DATE_TRUNC('month', O_ORDERDATE)))
WHERE VARIACION_PCT < 0
ORDER BY MES;
-- Debes ver: 6 filas: feb, abr, jun, ago, sep y nov de 1995. Primera: 1995-02-01, 2689142056.26, 2946587345.85, -8.74.

-- Consulta dada para B4: el «promedio de promedios» por estado de pedido (AVG sobre los AVG).
WITH POR_ESTADO AS (SELECT O_ORDERSTATUS, COUNT(*) AS PEDIDOS, AVG(O_TOTALPRICE) AS PROM
                    FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
                    GROUP BY O_ORDERSTATUS)
SELECT ROUND(AVG(PROM), 2) AS PROM_DE_PROMEDIOS
FROM POR_ESTADO;
-- Debes ver: 1 fila: PROM_DE_PROMEDIOS 161711.03. El promedio directo de los 1500000 pedidos es otro número: 151219.54.



-- =====================================================================
-- EJERCICIO 1 ★ · QUALIFY: el top-N sin subconsulta
-- =====================================================================
-- DEFINICIÓN:
--   QUALIFY filtra después de calcular las ventanas, igual que HAVING filtra después de agrupar.
--   Orden de evaluación: FROM, WHERE, GROUP BY, HAVING, ventanas, QUALIFY, DISTINCT, ORDER BY, LIMIT.
--   Por eso la consulta del EJ1 del Lab 3A, que anidaba la ventana en una subconsulta, se escribe en un
--   solo nivel. QUALIFY admite alias definidos en el SELECT. No es SQL estándar: en otros motores
--   hay que anidar.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT C_MKTSEGMENT, C_CUSTKEY, C_ACCTBAL
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER
QUALIFY ROW_NUMBER() OVER (PARTITION BY C_MKTSEGMENT
                           ORDER BY C_ACCTBAL DESC, C_CUSTKEY) = 1
ORDER BY C_MKTSEGMENT;
-- Debes ver en el ejemplo: 5 filas, las mismas del ejemplo del EJ1 del Lab 3A: AUTOMOBILE 69321, BUILDING 61453, FURNITURE 144232, HOUSEHOLD 76146, MACHINERY 23828.
--
-- TU TURNO:
--   EJ1 del Lab 3A (los 3 pedidos más caros de cada prioridad, desempate por O_ORDERKEY ascendente),
--   sin subconsulta: con QUALIFY. Ordena por O_ORDERPRIORITY y RN.
--   Columnas de salida (en este orden): O_ORDERPRIORITY, O_ORDERKEY, O_TOTALPRICE, RN

CREATE OR REPLACE VIEW B1 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM B1;  -- mira tu resultado

-- ✅ Debes ver: 15 filas, igual que EJ1.


-- =====================================================================
-- EJERCICIO 2 ★ · QUALIFY con la ventana dentro de la condición
-- =====================================================================
-- DEFINICIÓN:
--   QUALIFY acepta la ventana escrita directamente en la condición, sin alias. Así el último pedido de
--   cada cliente (EJ2 del Lab 3A) no necesita ni SELECT anidado ni columna RN.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT O_CUSTKEY, O_ORDERKEY, O_ORDERDATE
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
WHERE O_CUSTKEY <= 5
QUALIFY ROW_NUMBER() OVER (PARTITION BY O_CUSTKEY
                           ORDER BY O_ORDERDATE, O_ORDERKEY) = 1
ORDER BY O_CUSTKEY;
-- Debes ver en el ejemplo: 4 filas, igual que el ejemplo del EJ2 del Lab 3A: 1 pedido 454791, 2 pedido 1374019, 4 pedido 164711, 5 pedido 2630562.
--
-- TU TURNO:
--   EJ2 del Lab 3A (el pedido más reciente de cada cliente, desempate por O_ORDERKEY descendente)
--   con QUALIFY. Ordena por O_CUSTKEY.
--   Columnas de salida (en este orden): O_CUSTKEY, O_ORDERKEY, O_ORDERDATE

CREATE OR REPLACE VIEW B2 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM B2 ORDER BY 1 LIMIT 20;  -- mira tu resultado (la vista tiene 99996 filas)

-- ✅ Debes ver: 99996 filas, igual que EJ2.


-- =====================================================================
-- EJERCICIO 3 ★ · QUALIFY con GROUP BY: LAG sobre una suma
-- =====================================================================
-- DEFINICIÓN:
--   QUALIFY también funciona con GROUP BY: primero se agrupa, después se calcula la ventana sobre el
--   resultado agrupado (LAG(SUM(...)) OVER (...)) y al final se filtra. En esta consulta no hace falta
--   la vista MENSUAL_1995 del Lab 3A: agrupas por mes, filtras 1995 con WHERE antes de agrupar y
--   dejas que QUALIFY descarte los meses que no cayeron. Enero no tiene mes anterior (LAG da NULL): la
--   condición lo descarta sola.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT YEAR(O_ORDERDATE) AS ANIO, COUNT(*) AS PEDIDOS
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
GROUP BY YEAR(O_ORDERDATE)
QUALIFY COUNT(*) > LAG(COUNT(*)) OVER (ORDER BY YEAR(O_ORDERDATE))
ORDER BY ANIO;
-- Debes ver en el ejemplo: 2 filas, los años cuyos pedidos subieron frente al año anterior: 1994 con 227597 y 1995 con 228637 (1992 no tiene año anterior: LAG da NULL y QUALIFY lo descarta).
--
-- TU TURNO:
--   EJ3 del Lab 3A (los meses de 1995 cuyo monto cayó frente al mes anterior) con GROUP BY y QUALIFY
--   sobre LAG de la suma. MES es el primer día del mes (DATE_TRUNC('month', O_ORDERDATE)); MONTO, la suma
--   de O_TOTALPRICE. VARIACION_PCT = (MONTO - MONTO_ANTERIOR) / MONTO_ANTERIOR * 100, a 2 decimales.
--   Filtra 1995 con WHERE antes de agrupar. Ordena por MES.
--   Columnas de salida (en este orden): MES, MONTO, MONTO_ANTERIOR, VARIACION_PCT

CREATE OR REPLACE VIEW B3 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM B3;  -- mira tu resultado

-- ✅ Debes ver: 6 filas, igual que EJ3: feb (-8.74), abr (-1.95), jun (-1.46), ago (-0.16), sep (-4.35), nov (-3.96).


-- =====================================================================
-- EJERCICIO 4 ★ · Promedio ponderado: el promedio de promedios se desvía
-- =====================================================================
-- DEFINICIÓN:
--   Un promedio de promedios da el mismo peso a cada grupo, aunque los grupos tengan tamaños muy
--   distintos. El promedio ponderado guarda numerador y denominador (la suma de n * promedio y la
--   suma de n) y divide al final: SUM(n * promedio) / SUM(n) es igual al promedio directo.
--   Más arriba está la consulta que calcula el «promedio de promedios» por estado de pedido con
--   AVG(PROM). Ejecútala, compárala con el promedio directo y corrígela.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
WITH G AS (SELECT C_MKTSEGMENT, COUNT(*) AS CLIENTES, AVG(C_ACCTBAL) AS PROM
           FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER
           GROUP BY C_MKTSEGMENT)
SELECT ROUND(AVG(PROM), 2) AS PROM_DE_PROMEDIOS,
       ROUND(SUM(CLIENTES * PROM) / SUM(CLIENTES), 2) AS PROM_PONDERADO,
       ROUND((SELECT AVG(C_ACCTBAL) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER), 2) AS PROM_DIRECTO
FROM G;
-- Debes ver en el ejemplo: 1 fila: PROM_DE_PROMEDIOS 4495.49, PROM_PONDERADO 4495.51, PROM_DIRECTO 4495.51. Con segmentos casi iguales la diferencia es pequeña; con grupos desiguales, como los estados de pedido, llega a 6.94 %.
--
-- TU TURNO:
--   Parte de la consulta dada (promedio de promedios del monto O_TOTALPRICE por estado de pedido) y
--   corrígela con el promedio ponderado. Muestra una sola fila con los cuatro valores, a 2 decimales:
--   PROM_DE_PROMEDIOS (AVG de los promedios), PROM_DIRECTO (AVG de O_TOTALPRICE sobre todos los
--   pedidos), PROM_PONDERADO (SUM(PEDIDOS * PROM) / SUM(PEDIDOS)) y
--   DIFERENCIA_PCT = (PROM_DE_PROMEDIOS - PROM_DIRECTO) / PROM_DIRECTO * 100.
--   Columnas de salida (en este orden): PROM_DE_PROMEDIOS, PROM_DIRECTO, PROM_PONDERADO, DIFERENCIA_PCT

CREATE OR REPLACE VIEW B4 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM B4;  -- mira tu resultado

-- ✅ Debes ver: 1 fila: 161711.03, 151219.54, 151219.54, 6.94


-- =====================================================================
-- EJERCICIO 5 ★★ · CTE: agregar antes de unir y contar las uniones
-- =====================================================================
-- DEFINICIÓN:
--   Una CTE (expresión de tabla común) es una consulta con nombre, válida solo dentro de la sentencia:
--   cada paso se escribe, se nombra y se usa abajo. No guarda datos. Agregar la tabla del lado «muchos»
--   (LINEITEM) por la llave del JOIN (una fila por L_ORDERKEY) antes de unir deja la unión de uno a
--   uno. Para sumar medidas de las líneas el total no cambia; la técnica evita repetir la medida del
--   pedido (O_TOTALPRICE) y achica el JOIN.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
WITH por_cliente AS (
  SELECT O_CUSTKEY, COUNT(*) AS PEDIDOS
  FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
  GROUP BY O_CUSTKEY)
SELECT C.C_MKTSEGMENT, SUM(P.PEDIDOS) AS PEDIDOS
FROM por_cliente P JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER C
  ON C.C_CUSTKEY = P.O_CUSTKEY
GROUP BY C.C_MKTSEGMENT
ORDER BY C.C_MKTSEGMENT;
-- Debes ver en el ejemplo: 5 filas: AUTOMOBILE 297453, BUILDING 303959, FURNITURE 299461, HOUSEHOLD 300147, MACHINERY 298980.
--
-- TU TURNO:
--   El ingreso (SUM de L_EXTENDEDPRICE * (1 - L_DISCOUNT)) por región, agregando LINEITEM por pedido en una
--   CTE antes de unir. Cuenta cuántos JOIN usaste y anótalo aquí, en un comentario:
--   -- JOIN usados: ____
--   Ordena por R_NAME.
--   Columnas de salida (en este orden): R_NAME, INGRESO (a 2 decimales)

CREATE OR REPLACE VIEW B5 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM B5;  -- mira tu resultado

-- ✅ Debes ver: 5 filas: AFRICA 43488870851.69; AMERICA 43565312628.95; ASIA 43858010644.94; EUROPE 44032702326.30; MIDDLE EAST 43157327433.13 (cuatro JOIN).



-- =====================================================================
-- PASO FINAL · Corre la verificación
-- =====================================================================
-- 1. Copia lab3b_verificacion.sql igual que copiaste este archivo.
-- 2. En Snowsight abre OTRA hoja nueva (+ SQL Worksheet o + > SQL File), pega todo y pulsa Run All.
-- 3. Busca la tabla final: EJERCICIO, NIVEL, RESULTADO, PISTA.
--
-- Una fila por ejercicio:
--   OK         = correcto.
--   REVISAR    = la vista existe pero no coincide (o B1 a B3 no usan QUALIFY). Lee la PISTA y
--                compara TUS_COLUMNAS con COLUMNAS_ESPERADAS.
--   PENDIENTE  = la vista todavía tiene el marcador SELECT NULL AS PENDIENTE.
-- La última fila es el resumen: cuántos de los 4 ★ están en OK. META: RESUMEN = OK y "4 de 4".
-- PENDIENTE en B5 es normal si no llegaste al ★★. Si dice PENDIENTE pero escribiste tu SELECT,
-- el CREATE falló: busca el mensaje rojo.


-- =====================================================================
-- QUÉ APRENDISTE
-- =====================================================================
-- - QUALIFY filtra después de calcular la ventana: el top-N por grupo y el último de cada grupo se
--   escriben en un solo nivel. Con GROUP BY filtra sobre LAG(SUM(...)).
-- - Una CTE nombra cada paso y se lee de arriba abajo; no guarda datos ni acelera la consulta.
-- - Agregar antes de unir deja la unión de uno a uno; el promedio de promedios se corrige
--   guardando numerador y denominador (promedio ponderado).
-- - B5 necesitó cuatro uniones para traer el nombre de una región: ¿cuántas harían falta cada
--   vez que preguntes por región?
--
-- Siguiente: B5 necesitó cuatro uniones para un nombre de región; el bloque de modelado muestra
-- por qué y qué cambia si se guarda de otra forma.


-- =====================================================================
-- ERRORES COMUNES
-- =====================================================================
-- Mensaje o síntoma                             | Causa                          | Cómo evitarlo
-- ---------------------------------------------|--------------------------------|---------------------------
-- Window function ... appears outside of       | Escribiste la ventana en WHERE | Muévela a QUALIFY
--   SELECT, QUALIFY, and ORDER BY clauses      |                                |
-- B3 devuelve meses de más o filas repetidas   | La ventana se calculó sobre    | Agrupa por mes y aplica LAG
--   (QUALIFY sin GROUP BY)                     | filas, no sobre meses          | a la suma
-- B4 da 161711.03 en las tres columnas         | Seguiste con AVG sobre los AVG | Pondera con n:
--                                              |                                | SUM(PEDIDOS * PROM) /
--                                              |                                | SUM(PEDIDOS)
-- B5 no coincide con los montos esperados      | Falta una condición ON o la    | Revisa las cuatro condiciones
--                                              | fórmula del ingreso está mal   | ON y usa L_EXTENDEDPRICE *
--                                              |                                | (1 - L_DISCOUNT)
-- Missing column specification (al crear la    | COUNT o SUM sin AS             | Pon AS NOMBRE en cada
--   vista)                                     |                                | columna calculada
-- REVISAR en B1, B2 o B3 con resultado         | La vista no usa QUALIFY (anidaste | Reescribe con QUALIFY y sin
--   correcto: «Usa QUALIFY»                    | una subconsulta)               | subconsulta
-- This session does not have a current         | No se corrió el Paso 0 en esa  | Selecciona de USE ROLE a
--   database                                   | hoja                           | USE SCHEMA CURSO.LAB3B; y
--                                              |                                | pulsa ▶
-- REVISAR con columnas distintas               | El alias de salida no coincide | Compara TUS_COLUMNAS con
--                                              |                                | COLUMNAS_ESPERADAS
