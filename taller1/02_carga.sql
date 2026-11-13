
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
-- Esta descripción corresponde a los datos de origen.
-- En la dimensión de destino se conserva una sola fila
-- por nombre de zona. Los registros repetidos identificados
-- tienen los mismos valores de BOROUGH y SERVICE_ZONE.
-- La lluvia se almacena una sola vez por fecha en DIM_FECHA.
--
-- OBJETIVO:
-- Cargar los datos en las tablas del modelo estrella
-- de manera reproducible.
-- ============================================================


-- ============================================================
-- CONFIGURACIÓN DEL ENTORNO
-- ============================================================

USE WAREHOUSE COMPUTE_WH;

USE DATABASE CURSO;

USE SCHEMA T1;


-- ============================================================
-- 1. CARGA DE DIM_FECHA
-- ============================================================

TRUNCATE TABLE CURSO.T1.DIM_FECHA;

INSERT INTO CURSO.T1.DIM_FECHA
(
    FECHA,
    ANIO,
    MES,
    DIA,
    DIA_SEMANA,
    ES_FIN_SEMANA,
    ES_FESTIVO,
    LLUVIA_MM
)

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
(
    ZONA,
    BOROUGH,
    SERVICE_ZONE
)
SELECT
    ZONA,
    BOROUGH,
    SERVICE_ZONE
FROM CURSO.LAB4.DIM_ZONA
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY ZONA
    ORDER BY BOROUGH, SERVICE_ZONE
) = 1;

-- ============================================================
-- 3. CARGA DE DIM_EMPRESA
-- ============================================================

TRUNCATE TABLE CURSO.T1.DIM_EMPRESA;

INSERT INTO CURSO.T1.DIM_EMPRESA
(
    EMPRESA
)
SELECT DISTINCT
    EMPRESA
FROM CURSO.LAB4.DAILY_ZONE_METRICS;


-- ============================================================
-- 4. CARGA DE FACT_VIAJES_DIA
-- Una fila por fecha, zona y empresa.
-- ============================================================

TRUNCATE TABLE CURSO.T1.FACT_VIAJES_DIA;

INSERT INTO CURSO.T1.FACT_VIAJES_DIA
(
    FECHA,
    ZONA,
    EMPRESA,
    VIAJES,
    INGRESO_TOTAL,
    PROPINA_TOTAL,
    DISTANCIA_TOTAL
)

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
    COUNT(DISTINCT CONCAT(
        FECHA, '|', ZONA, '|', EMPRESA
    )) AS COMBINACIONES_UNICAS,
    SUM(VIAJES) AS TOTAL_VIAJES

FROM CURSO.T1.FACT_VIAJES_DIA;


-- ============================================================
-- CONTROL DE LAS DIMENSIONES
-- ============================================================

SELECT 'DIM_FECHA' AS DIMENSION, COUNT(*) AS TOTAL
FROM CURSO.T1.DIM_FECHA

UNION ALL

SELECT 'DIM_ZONA', COUNT(*)
FROM CURSO.T1.DIM_ZONA

UNION ALL

SELECT 'DIM_EMPRESA', COUNT(*)
FROM CURSO.T1.DIM_EMPRESA;

-- ============================================================
-- CONTROL DE DUPLICADOS EN FACT_VIAJES_DIA
-- ============================================================

SELECT
    COUNT(*) AS GRUPOS_DUPLICADOS
FROM (
    SELECT
        FECHA,
        ZONA,
        EMPRESA
    FROM CURSO.T1.FACT_VIAJES_DIA
    GROUP BY
        FECHA,
        ZONA,
        EMPRESA
    HAVING COUNT(*) > 1
);


-- ============================================================
-- CONTROL DE ZONAS SIN DIMENSIÓN
-- ============================================================

SELECT
    COUNT(*) AS ZONAS_SIN_DIMENSION
FROM CURSO.T1.FACT_VIAJES_DIA AS F
LEFT JOIN CURSO.T1.DIM_ZONA AS D
    ON F.ZONA = D.ZONA
WHERE D.ZONA IS NULL;


-- ============================================================
-- CONTROL DE FECHAS SIN DIMENSIÓN
-- ============================================================

SELECT
    COUNT(*) AS FECHAS_SIN_DIMENSION
FROM CURSO.T1.FACT_VIAJES_DIA AS F
LEFT JOIN CURSO.T1.DIM_FECHA AS D
    ON F.FECHA = D.FECHA
WHERE D.FECHA IS NULL;


-- ============================================================
-- CONTROL DE EMPRESAS SIN DIMENSIÓN
-- ============================================================

SELECT
    COUNT(*) AS EMPRESAS_SIN_DIMENSION
FROM CURSO.T1.FACT_VIAJES_DIA AS F
LEFT JOIN CURSO.T1.DIM_EMPRESA AS D
    ON F.EMPRESA = D.EMPRESA
WHERE D.EMPRESA IS NULL;
