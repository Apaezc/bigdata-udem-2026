-- ============================================================
-- TALLER 1 - BIG DATA E INGENIERÍA DE DATOS
-- ARCHIVO: 02_carga.sql
-- RESPONSABLE: INGENIERÍA DE DATOS
--
-- Carga las dimensiones primero y la tabla de hechos después.
-- Se puede ejecutar más de una vez porque se vacían las tablas
-- antes de insertar nuevamente los datos.
--
-- Fuentes:
-- DAILY_ZONE_METRICS: 46715 filas
-- DIM_ZONA: 265 filas originales
-- FESTIVOS_2024: 11 filas
--
-- IMPORTANTE:
-- DIM_ZONA conserva una fila por combinación ZONA, BOROUGH
-- y SERVICE_ZONE para evitar perder información.
-- La lluvia se almacena una sola vez por fecha en DIM_FECHA.
--
-- OBJETIVO:
-- Cargar los datos en las tablas del modelo estrella
-- de manera reproducible.
-- ============================================================

USE WAREHOUSE COMPUTE_WH;
USE DATABASE CURSO;
USE SCHEMA T1;

-- ============================================================
-- 1. CARGA DE DIM_FECHA
-- ============================================================

TRUNCATE TABLE CURSO.T1.DIM_FECHA;
INSERT INTO CURSO.T1.DIM_FECHA
WITH CALENDARIO AS (
    SELECT
        DATEADD(DAY, SEQ4(), '2024-01-01'::DATE) AS FECHA
    FROM TABLE(GENERATOR(ROWCOUNT => 91))
)
SELECT
    C.FECHA,
    YEAR(C.FECHA) AS ANIO,
    MONTH(C.FECHA) AS MES,
    DAY(C.FECHA) AS DIA,
    DAYNAME(C.FECHA) AS DIA_SEMANA,
    CASE
        WHEN DAYOFWEEKISO(C.FECHA) IN (6, 7)
        THEN TRUE
        ELSE FALSE
    END AS ES_FIN_SEMANA,
    CASE
        WHEN F.FECHA IS NOT NULL
        THEN TRUE
        ELSE FALSE
    END AS ES_FESTIVO,
    MAX(V.LLUVIA_MM) AS LLUVIA_MM
FROM CALENDARIO AS C
LEFT JOIN CURSO.LAB4.FESTIVOS_2024 AS F
    ON C.FECHA = F.FECHA
LEFT JOIN CURSO.LAB4.DAILY_ZONE_METRICS AS V
    ON C.FECHA = V.FECHA
GROUP BY
    C.FECHA,
    F.FECHA;

    -- ============================================================
-- 2. CARGA DE DIM_ZONA
-- ============================================================

TRUNCATE TABLE CURSO.T1.DIM_ZONA;
INSERT INTO CURSO.T1.DIM_ZONA
SELECT DISTINCT
    ZONA,
    BOROUGH,
    SERVICE_ZONE
FROM CURSO.LAB4.DIM_ZONA;

-- ============================================================
-- 3. CARGA DE DIM_EMPRESA
-- ============================================================

TRUNCATE TABLE CURSO.T1.DIM_EMPRESA;
INSERT INTO CURSO.T1.DIM_EMPRESA
SELECT DISTINCT
    EMPRESA
FROM CURSO.LAB4.DAILY_ZONE_METRICS;

-- ============================================================
-- 4. CARGA DE FACT_VIAJES_DIA
-- Una fila por fecha, zona y empresa.
-- ============================================================

TRUNCATE TABLE CURSO.T1.FACT_VIAJES_DIA;
INSERT INTO CURSO.T1.FACT_VIAJES_DIA
SELECT
    FECHA,
    ZONA,
    EMPRESA,
    SUM(VIAJES) AS VIAJES,
    SUM(INGRESO_TOTAL) AS INGRESO_TOTAL,
    SUM(PROPINA_PROMEDIO * VIAJES) AS PROPINA_TOTAL,
    SUM(DISTANCIA_PROMEDIO * VIAJES) AS DISTANCIA_TOTAL
FROM CURSO.LAB4.DAILY_ZONE_METRICS
GROUP BY
    FECHA,
    ZONA,
    EMPRESA;

    -- ============================================================
-- PASO 47: CONTROL DE LA CARGA
-- ============================================================

SELECT
    COUNT(*) AS TOTAL_REGISTROS,
    SUM(VIAJES) AS TOTAL_VIAJES
FROM CURSO.T1.FACT_VIAJES_DIA;

-- RESULTADO ESPERADO:
-- FILAS: 46715
-- VIAJES: 60268466
