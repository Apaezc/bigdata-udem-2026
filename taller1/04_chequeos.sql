
-- =====================================================================
-- TALLER 1 · 04_chequeos.sql · Controles de integridad
-- =====================================================================
-- TALLER 1 - BIG DATA E INGENIERÍA DE DATOS
-- ARCHIVO: 04_chequeos.sql
-- RESPONSABLE: INGENIERÍA DE DATOS
-- 
-- Se ejecutan los cuatro controles obligatorios del enunciado:
-- 1. Cantidad de filas.
-- 2. Unicidad del grano FECHA + ZONA + EMPRESA.
-- 3. Registros sin zona correspondiente en DIM_ZONA.
-- 4. Total de viajes contra el origen.
--
-- OBJETIVO:
-- Validar la integridad y consistencia del modelo estrella.
--
-- El modelo utiliza ZONA y EMPRESA como llaves naturales.
-- =====================================================================

USE WAREHOUSE COMPUTE_WH;

USE DATABASE CURSO;

USE SCHEMA T1;

-- ============================================================
-- CONTROL 1: CANTIDAD DE REGISTROS
-- Se esperan 46.715 registros.
-- ============================================================

SELECT
    'filas' AS CONTROL,
    COUNT(*) AS HECHO,
    46715 AS ESPERADO
FROM CURSO.T1.FACT_VIAJES_DIA;

-- ============================================================
-- CONTROL 2: UNICIDAD DEL GRANO
-- Cada registro debe ser único por fecha, zona y empresa.
-- ============================================================

SELECT
    COUNT(*) AS TOTAL_REGISTROS,
    COUNT(DISTINCT CONCAT(FECHA,'|',ZONA,'|',EMPRESA)) AS COMBINACIONES_UNICAS
FROM CURSO.T1.FACT_VIAJES_DIA;

-- ============================================================
-- CONTROL 3: ZONAS HUÉRFANAS
-- Todas las zonas deben existir en DIM_ZONA.
-- ============================================================

SELECT
    COUNT(*) AS ZONAS_SIN_DIMENSION
FROM CURSO.T1.FACT_VIAJES_DIA F
LEFT JOIN CURSO.T1.DIM_ZONA D
    ON F.ZONA = D.ZONA
WHERE D.ZONA IS NULL;

-- ============================================================
-- CONTROL 4: TOTAL DE VIAJES
-- Se esperan 60.268.466 viajes.
-- ============================================================

SELECT
    SUM(VIAJES) AS TOTAL_VIAJES
FROM CURSO.T1.FACT_VIAJES_DIA;
