-- =====================================================================
-- TALLER 1 · 04_chequeos.sql · Los cuatro controles de integridad (esqueleto)
-- =====================================================================
-- Los cuatro controles del enunciado (sección 15): filas, grano único, sin huérfanos y viajes
-- totales contra el origen. Debajo está la consulta del enunciado como punto de partida:
-- descoméntala y ajusta los nombres de tus llaves (ZONA_KEY, EMPRESA_KEY) a los de tu estrella.
-- Salida esperada: cuatro filas con HECHO igual a ESPERADO.
-- Si `filas` o `viajes` no coinciden, revisa la trampa 4; si `grano` es menor que `filas`, hay duplicados.
-- =====================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE SCHEMA CURSO.T1;

-- SELECT 'filas' AS CONTROL, COUNT(*) AS HECHO, 46715 AS ESPERADO
-- FROM CURSO.T1.FACT_VIAJES_DIA
-- UNION ALL
-- SELECT 'grano', COUNT(DISTINCT FECHA || '|' || ZONA_KEY || '|' || EMPRESA_KEY), 46715
-- FROM CURSO.T1.FACT_VIAJES_DIA
-- UNION ALL
-- SELECT 'sin zona', COUNT(*), 0
-- FROM CURSO.T1.FACT_VIAJES_DIA F LEFT JOIN CURSO.T1.DIM_ZONA Z USING (ZONA_KEY)
-- WHERE Z.ZONA_KEY IS NULL
-- UNION ALL
-- SELECT 'viajes', SUM(VIAJES), 60268466
-- FROM CURSO.T1.FACT_VIAJES_DIA;

-- TODO · Un control más que decidas tú (por ejemplo, sin fecha o sin empresa huérfanas).
