-- =====================================================================
-- TALLER 2 · respuesta.sql · EQUIPO 4
-- Rol: Modelador SQL (Andrea Páez Cardona)
-- =====================================================================
-- Pregunta: En enero de 2024, ¿los viajes largos caen más que los cortos los días con lluvia?
-- Tabla   : BIGDATA.DEV.EQUIPO_4_RANGO_DISTANCIA (una fila por fecha y rango de distancia)
--
-- Definiciones (las mismas de taller2/contrato.md):
--   * Rango de distancia: corto < 2 mi · medio 2 a < 5 mi · largo >= 5 mi (se calcula en gold).
--   * Día con lluvia: LLUVIA_MM >= 1.0 mm en el día. Día seco: menos de 1.0 mm.
--   * Se comparan VIAJES POR DÍA, no totales: hay más días secos que lluviosos.
--   * Los días se cuentan con COUNT(DISTINCT FECHA), nunca con COUNT(*): cada día tiene 3 filas
--     (una por rango) y la lluvia se repite en las tres (trampa 1 del Taller 1). La lluvia no se suma.
-- =====================================================================

USE ROLE BIGDATA_DEV;
USE WAREHOUSE BIGDATA_WH;
USE DATABASE BIGDATA;

-- ---------------------------------------------------------------------
-- R1 · La respuesta: viajes por día con lluvia frente a días secos, por rango
-- ---------------------------------------------------------------------
WITH por_dia AS (
    SELECT FECHA,
           RANGO_DISTANCIA,
           VIAJES,
           IFF(LLUVIA_MM >= 1.0, 'con lluvia', 'seco') AS TIPO_DIA
    FROM BIGDATA.DEV.EQUIPO_4_RANGO_DISTANCIA
    WHERE LLUVIA_MM IS NOT NULL
),
promedios AS (
    SELECT RANGO_DISTANCIA,
           TIPO_DIA,
           COUNT(DISTINCT FECHA)                 AS DIAS,
           SUM(VIAJES)                           AS VIAJES,
           SUM(VIAJES) / COUNT(DISTINCT FECHA)   AS VIAJES_POR_DIA
    FROM por_dia
    GROUP BY RANGO_DISTANCIA, TIPO_DIA
)
SELECT RANGO_DISTANCIA,
       MAX(IFF(TIPO_DIA = 'seco',       DIAS, NULL))                     AS DIAS_SECOS,
       MAX(IFF(TIPO_DIA = 'con lluvia', DIAS, NULL))                     AS DIAS_CON_LLUVIA,
       ROUND(MAX(IFF(TIPO_DIA = 'seco',       VIAJES_POR_DIA, NULL)), 0) AS VIAJES_DIA_SECO,
       ROUND(MAX(IFF(TIPO_DIA = 'con lluvia', VIAJES_POR_DIA, NULL)), 0) AS VIAJES_DIA_LLUVIA,
       ROUND(100 * (MAX(IFF(TIPO_DIA = 'con lluvia', VIAJES_POR_DIA, NULL))
                  / MAX(IFF(TIPO_DIA = 'seco',       VIAJES_POR_DIA, NULL)) - 1), 1) AS CAMBIO_PCT
FROM promedios
GROUP BY RANGO_DISTANCIA
ORDER BY CASE RANGO_DISTANCIA WHEN 'corto' THEN 1 WHEN 'medio' THEN 2 ELSE 3 END;

-- Resultado:
--   RANGO   DIAS_SECOS  DIAS_CON_LLUVIA  VIAJES_DIA_SECO  VIAJES_DIA_LLUVIA  CAMBIO_PCT
--   corto   17          14               223 922          240 658            +7.5
--   medio   17          14               206 839          214 002            +3.5
--   largo   17          14               191 455          193 366            +1.0
--
-- CIFRA FINAL: los días con lluvia, los viajes CORTOS suben 7,5 % y los LARGOS solo 1,0 %.
-- Interpretación: la hipótesis NO se confirma. Con lluvia los viajes no caen en ningún rango:
-- suben, y suben más cuanto más corto es el viaje. Lo que más crece son los trayectos de menos
-- de 2 millas, los que con buen tiempo se harían caminando; los largos casi no cambian.
-- Qué NO dice: enero tiene solo 31 días (14 con lluvia y 17 secos) y no se controlan otros
-- factores (festivos, eventos, temperatura).


-- ---------------------------------------------------------------------
-- R2 · Control por día de la semana (función de ventana)
-- Un martes lluvioso no se compara con un sábado seco: cada día se compara con el promedio de
-- los días SECOS del mismo día de la semana, en el mismo rango.
-- ---------------------------------------------------------------------
WITH base AS (
    SELECT FECHA,
           RANGO_DISTANCIA,
           VIAJES,
           LLUVIA_MM >= 1.0                       AS LLUVIOSO,
           DAYOFWEEKISO(FECHA)                    AS DIA_SEMANA
    FROM BIGDATA.DEV.EQUIPO_4_RANGO_DISTANCIA
    WHERE LLUVIA_MM IS NOT NULL
),
con_linea_base AS (
    SELECT base.*,
           AVG(IFF(LLUVIOSO, NULL, VIAJES))
               OVER (PARTITION BY RANGO_DISTANCIA, DIA_SEMANA) AS VIAJES_SECO_MISMO_DIA
    FROM base
)
SELECT RANGO_DISTANCIA,
       COUNT(DISTINCT FECHA)                                            AS DIAS_CON_LLUVIA,
       SUM(VIAJES)                                                      AS VIAJES_REALES,
       ROUND(SUM(VIAJES_SECO_MISMO_DIA), 0)                             AS VIAJES_ESPERADOS,
       ROUND(100 * (SUM(VIAJES) / SUM(VIAJES_SECO_MISMO_DIA) - 1), 1)   AS CAMBIO_PCT_AJUSTADO
FROM con_linea_base
WHERE LLUVIOSO
GROUP BY RANGO_DISTANCIA
ORDER BY CASE RANGO_DISTANCIA WHEN 'corto' THEN 1 WHEN 'medio' THEN 2 ELSE 3 END;

-- Resultado:
--   RANGO   DIAS_CON_LLUVIA  VIAJES_REALES  VIAJES_ESPERADOS  CAMBIO_PCT_AJUSTADO
--   corto   14               3 369 215      3 218 342         +4.7
--   medio   14               2 996 025      2 967 097         +1.0
--   largo   14               2 707 118      2 687 750         +0.7
-- Interpretación: comparando cada día con lluvia contra los días secos del mismo día de la
-- semana, el efecto se reduce (parte de la subida de R1 era que llovió más en días de mucha
-- demanda), pero apunta al mismo lado: los cortos suben 4,7 % y los largos 0,7 %. La lluvia
-- empuja sobre todo los viajes cortos; en los largos el efecto es casi nulo. El cambio se
-- calcula con sumas de viajes, no promediando porcentajes (trampa 2 del Taller 1).


-- ---------------------------------------------------------------------
-- R3 · Comprobación: la tabla de la respuesta es la misma que se concilió
-- ---------------------------------------------------------------------
SELECT COUNT(*)              AS FILAS,          -- esperado: 93 (31 días x 3 rangos)
       COUNT(DISTINCT FECHA) AS DIAS,           -- esperado: 31
       SUM(VIAJES)           AS VIAJES,         -- debe ser igual a las filas de silver
       COUNT_IF(LLUVIA_MM IS NULL) AS FILAS_SIN_LLUVIA  -- esperado: 0
FROM BIGDATA.DEV.EQUIPO_4_RANGO_DISTANCIA;
-- Resultado: FILAS 93 · DIAS 31 · VIAJES 19 650 023 (= filas de silver en Athena)
