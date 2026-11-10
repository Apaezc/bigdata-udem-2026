USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE SCHEMA CURSO.LAB4;
-- No necesitas leer este archivo: pégalo y pulsa Run All.

-- =====================================================================
-- LAB 4 · VERIFICACIÓN (autoverificación; Big Data UdeM · Clase 4)
-- =====================================================================
-- QUÉ HACE
--   Comprueba tu stage LAKE_PUBLICO (E1), tu tabla DAILY_ZONE_METRICS (E3) y tus vistas EJ2, EJ4,
--   EJ5, EJ6 y EJ7 (en CURSO.LAB4) contra la respuesta esperada. Devuelve una fila por ejercicio
--   y una fila de resumen.
--
-- CÓMO LEER EL RESULTADO
--   OK         = tu objeto da el mismo resultado (mismos valores y mismos nombres de columna en el
--                mismo orden).
--   REVISAR    = tu objeto existe pero no coincide. Lee la PISTA y compara TUS_COLUMNAS con
--                COLUMNAS_ESPERADAS.
--   PENDIENTE  = el objeto no existe (E1, E3) o la vista todavía tiene la línea
--                SELECT NULL AS PENDIENTE (E2, E4, E5, E6, E7).
--   RESUMEN    = cuántos de los 6 ★ están en OK. Meta: RESUMEN = OK y "6 de 6 ★ en OK".
--                PENDIENTE en E7 (★★) es normal si no hiciste el reto.
--   TUS_COLUMNAS y COLUMNAS_ESPERADAS = aparecen solo en las filas REVISAR, para comparar los
--                nombres de columnas.
--
-- REQUISITOS
--   - Haber corrido el PASO 0 de lab4.sql (rol, warehouse, CURSO.LAB4).
--
-- NOTA
--   Este archivo solo crea vistas «marcador» (PENDIENTE) si todavía no existen, para que la
--   verificación nunca falle por una vista faltante. No cambia tus objetos existentes.
--   La respuesta esperada son los conteos de control del paquete público: 15909, 14889 y 15917
--   filas por mes (46715 en total) y sus viajes; no usa tus tablas ni tus vistas.
-- =====================================================================

-- Marcadores: si una vista aún no existe, se crea con la línea PENDIENTE.
CREATE VIEW IF NOT EXISTS EJ2          AS SELECT NULL AS PENDIENTE;
CREATE VIEW IF NOT EXISTS EJ4          AS SELECT NULL AS PENDIENTE;
CREATE VIEW IF NOT EXISTS EJ5          AS SELECT NULL AS PENDIENTE;
CREATE VIEW IF NOT EXISTS EJ6          AS SELECT NULL AS PENDIENTE;
CREATE VIEW IF NOT EXISTS EJ7          AS SELECT NULL AS PENDIENTE;

-- =====================================================================
-- CONSULTA FINAL (una sola). Las X4..X6 son la respuesta esperada.
-- =====================================================================
WITH

-- E1 ★ · el stage, desde el catálogo (no lo lee: solo mira su tipo y su URL)
S AS (
  SELECT COUNT(*) AS N, MAX(STAGE_TYPE) AS T, MAX(STAGE_URL) AS U
  FROM CURSO.INFORMATION_SCHEMA.STAGES
  WHERE STAGE_SCHEMA = 'LAB4' AND STAGE_NAME = 'LAKE_PUBLICO'
),

-- E2 ★ · filas, viajes y días de tu vista EJ2 (por nombre de campo: si falta una columna, da NULL)
V2 AS (
  SELECT COUNT(*) AS N, SUM(O:VIAJES::NUMBER) AS VIAJES, COUNT(DISTINCT O:FECHA::DATE) AS DIAS
  FROM (SELECT OBJECT_CONSTRUCT(*) AS O FROM EJ2)
),

-- E3 ★ · la tabla, desde el catálogo (filas, columnas y tipos)
T3 AS (
  SELECT (SELECT COUNT(*) FROM CURSO.INFORMATION_SCHEMA.TABLES
          WHERE TABLE_SCHEMA = 'LAB4' AND TABLE_NAME = 'DAILY_ZONE_METRICS' AND TABLE_TYPE = 'BASE TABLE') AS N,
         (SELECT MAX(ROW_COUNT) FROM CURSO.INFORMATION_SCHEMA.TABLES
          WHERE TABLE_SCHEMA = 'LAB4' AND TABLE_NAME = 'DAILY_ZONE_METRICS' AND TABLE_TYPE = 'BASE TABLE') AS FILAS,
         COALESCE((SELECT LISTAGG(COLUMN_NAME, ',') WITHIN GROUP (ORDER BY ORDINAL_POSITION)
                   FROM CURSO.INFORMATION_SCHEMA.COLUMNS
                   WHERE TABLE_SCHEMA = 'LAB4' AND TABLE_NAME = 'DAILY_ZONE_METRICS'), '') AS COLS,
         COALESCE((SELECT LISTAGG(DATA_TYPE, ',') WITHIN GROUP (ORDER BY ORDINAL_POSITION)
                   FROM CURSO.INFORMATION_SCHEMA.COLUMNS
                   WHERE TABLE_SCHEMA = 'LAB4' AND TABLE_NAME = 'DAILY_ZONE_METRICS'), '') AS TIPOS
),

-- E4 ★ · respuesta esperada
X4 AS (
  SELECT '2024-01' AS MES, 15909 AS FILAS, 19650023 AS VIAJES
  UNION ALL SELECT '2024-02', 14889, 19344724
  UNION ALL SELECT '2024-03', 15917, 21273719
),

-- E5 ★ · respuesta esperada
X5 AS (
  SELECT 46715 AS FILAS, 6 AS ARCHIVOS_CARGADOS
),

-- E6 ★ · respuesta esperada
X6 AS (
  SELECT 'zonas' AS CONTROL, 265 AS VALOR
  UNION ALL SELECT 'festivos', 11
  UNION ALL SELECT 'nombres_repetidos', 2
),

-- E7 ★★ · tu vista EJ7, leída por nombre de campo
V7 AS (SELECT COUNT(*) AS N FROM EJ7),
V7_O AS (SELECT OBJECT_CONSTRUCT(*) AS O FROM EJ7),

-- Un renglón por ejercicio, con las comprobaciones de tus objetos.
--   FILAS_OK          : mismo número de filas.
--   VALORES_OK        : mismos valores (HASH_AGG(*) o los totales esperados).
--   PEND              : el objeto no existe o todavía es el marcador SELECT NULL AS PENDIENTE.
--   COLS_ACTUALES     : nombres de columnas de tu objeto, en orden.
--   COLS_ESPERADAS    : nombres de columnas esperados, en orden.
--   EXTRA_OK          : comprobación adicional del ejercicio.
R AS (
SELECT 'E1' AS EJERCICIO, '★' AS NIVEL, 1 AS K,
    TRUE AS FILAS_OK,
    (SELECT MAX(T) FROM S) = 'External Named' AND (SELECT MAX(U) FROM S) = 's3://bigdata-udem-2026-publico/paquete/gold/daily_zone_metrics/' AS VALORES_OK,
    (SELECT N FROM S) = 0 AS PEND,
    '' AS COLS_ACTUALES,
    '' AS COLS_ESPERADAS,
    TRUE AS EXTRA_OK,
    'Revisa que la URL sea exactamente la del paquete, con la barra final, y que el stage sea externo' AS PISTA_MAL,
    '' AS PISTA_EXTRA
  UNION ALL
SELECT 'E2' AS EJERCICIO, '★' AS NIVEL, 2 AS K,
    (SELECT N FROM V2) = 15909 AS FILAS_OK,
    (SELECT VIAJES FROM V2) = 19650023 AND (SELECT DIAS FROM V2) = 31 AS VALORES_OK,
    COALESCE((SELECT LISTAGG(COLUMN_NAME, ',') WITHIN GROUP (ORDER BY ORDINAL_POSITION) FROM CURSO.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'LAB4' AND TABLE_NAME = 'EJ2'), '') = 'PENDIENTE' AS PEND,
    COALESCE((SELECT LISTAGG(COLUMN_NAME, ',') WITHIN GROUP (ORDER BY ORDINAL_POSITION) FROM CURSO.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'LAB4' AND TABLE_NAME = 'EJ2'), '') AS COLS_ACTUALES,
    'FECHA,ZONA,EMPRESA,VIAJES' AS COLS_ESPERADAS,
    TRUE AS EXTRA_OK,
    'Extrae cada columna con $1:nombre::TIPO; el nombre va en minúsculas, y usa el PATTERN de enero' AS PISTA_MAL,
    '' AS PISTA_EXTRA
  UNION ALL
SELECT 'E3' AS EJERCICIO, '★' AS NIVEL, 3 AS K,
    (SELECT FILAS FROM T3) = 46715 AS FILAS_OK,
    (SELECT TIPOS FROM T3) = 'DATE,TEXT,TEXT,NUMBER,FLOAT,FLOAT,FLOAT,FLOAT' AS VALORES_OK,
    (SELECT N FROM T3) = 0 AS PEND,
    (SELECT COLS FROM T3) AS COLS_ACTUALES,
    'FECHA,ZONA,EMPRESA,VIAJES,INGRESO_TOTAL,PROPINA_PROMEDIO,DISTANCIA_PROMEDIO,LLUVIA_MM' AS COLS_ESPERADAS,
    TRUE AS EXTRA_OK,
    CASE WHEN (SELECT FILAS FROM T3) >= 2 * 46715 THEN 'La tabla tiene el doble de filas: cargaste dos veces o usaste FORCE; recrea la tabla (CREATE OR REPLACE) y carga una vez'
         ELSE 'Falta MATCH_BY_COLUMN_NAME o el PATTERN; la tabla necesita las 8 columnas en ese orden y 46715 filas' END AS PISTA_MAL,
    'Los tipos de las columnas no coinciden con el enunciado' AS PISTA_EXTRA
  UNION ALL
SELECT 'E4' AS EJERCICIO, '★' AS NIVEL, 4 AS K,
    (SELECT COUNT(*) FROM EJ4) = 3 AS FILAS_OK,
    (SELECT HASH_AGG(*) FROM EJ4) IS NOT DISTINCT FROM (SELECT HASH_AGG(*) FROM X4) AS VALORES_OK,
    COALESCE((SELECT LISTAGG(COLUMN_NAME, ',') WITHIN GROUP (ORDER BY ORDINAL_POSITION) FROM CURSO.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'LAB4' AND TABLE_NAME = 'EJ4'), '') = 'PENDIENTE' AS PEND,
    COALESCE((SELECT LISTAGG(COLUMN_NAME, ',') WITHIN GROUP (ORDER BY ORDINAL_POSITION) FROM CURSO.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'LAB4' AND TABLE_NAME = 'EJ4'), '') AS COLS_ACTUALES,
    'MES,FILAS,VIAJES' AS COLS_ESPERADAS,
    TRUE AS EXTRA_OK,
    'Agrupa por TO_CHAR(FECHA, ''YYYY-MM'') y suma VIAJES de la tabla cargada' AS PISTA_MAL,
    '' AS PISTA_EXTRA
  UNION ALL
SELECT 'E5' AS EJERCICIO, '★' AS NIVEL, 5 AS K,
    (SELECT COUNT(*) FROM EJ5) = 1 AS FILAS_OK,
    (SELECT HASH_AGG(*) FROM EJ5) IS NOT DISTINCT FROM (SELECT HASH_AGG(*) FROM X5) AS VALORES_OK,
    COALESCE((SELECT LISTAGG(COLUMN_NAME, ',') WITHIN GROUP (ORDER BY ORDINAL_POSITION) FROM CURSO.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'LAB4' AND TABLE_NAME = 'EJ5'), '') = 'PENDIENTE' AS PEND,
    COALESCE((SELECT LISTAGG(COLUMN_NAME, ',') WITHIN GROUP (ORDER BY ORDINAL_POSITION) FROM CURSO.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'LAB4' AND TABLE_NAME = 'EJ5'), '') AS COLS_ACTUALES,
    'FILAS,ARCHIVOS_CARGADOS' AS COLS_ESPERADAS,
    TRUE AS EXTRA_OK,
    'Si las filas se duplicaron, usaste FORCE = TRUE o cargaste dos veces: recrea la tabla (CREATE OR REPLACE) y carga una vez; recrear la tabla borra la memoria del COPY, por eso el siguiente COPY carga de nuevo' AS PISTA_MAL,
    '' AS PISTA_EXTRA
  UNION ALL
SELECT 'E6' AS EJERCICIO, '★' AS NIVEL, 6 AS K,
    (SELECT COUNT(*) FROM EJ6) = 3 AS FILAS_OK,
    (SELECT HASH_AGG(*) FROM EJ6) IS NOT DISTINCT FROM (SELECT HASH_AGG(*) FROM X6) AS VALORES_OK,
    COALESCE((SELECT LISTAGG(COLUMN_NAME, ',') WITHIN GROUP (ORDER BY ORDINAL_POSITION) FROM CURSO.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'LAB4' AND TABLE_NAME = 'EJ6'), '') = 'PENDIENTE' AS PEND,
    COALESCE((SELECT LISTAGG(COLUMN_NAME, ',') WITHIN GROUP (ORDER BY ORDINAL_POSITION) FROM CURSO.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'LAB4' AND TABLE_NAME = 'EJ6'), '') AS COLS_ACTUALES,
    'CONTROL,VALOR' AS COLS_ESPERADAS,
    TRUE AS EXTRA_OK,
    'Corre primero los dos archivos de datos/ y usa los textos zonas, festivos y nombres_repetidos' AS PISTA_MAL,
    '' AS PISTA_EXTRA
  UNION ALL
SELECT 'E7' AS EJERCICIO, '★★' AS NIVEL, 7 AS K,
    (SELECT N FROM V7) = 1 AS FILAS_OK,
    COALESCE((SELECT O:FILAS_ATHENA::NUMBER = 46715
                     AND O:KB_ESCANEADOS::NUMBER >= 0
                     AND O:MB_FACTURADOS::NUMBER = GREATEST(10, CEIL(O:KB_ESCANEADOS::NUMBER / 1024))
              FROM V7_O), FALSE) AS VALORES_OK,
    COALESCE((SELECT LISTAGG(COLUMN_NAME, ',') WITHIN GROUP (ORDER BY ORDINAL_POSITION) FROM CURSO.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'LAB4' AND TABLE_NAME = 'EJ7'), '') = 'PENDIENTE' AS PEND,
    COALESCE((SELECT LISTAGG(COLUMN_NAME, ',') WITHIN GROUP (ORDER BY ORDINAL_POSITION) FROM CURSO.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'LAB4' AND TABLE_NAME = 'EJ7'), '') AS COLS_ACTUALES,
    'FILAS_ATHENA,KB_ESCANEADOS,MB_FACTURADOS' AS COLS_ESPERADAS,
    TRUE AS EXTRA_OK,
    'Revisa que los KB sean los de Data scanned y que MB_FACTURADOS sea al menos 10' AS PISTA_MAL,
    '' AS PISTA_EXTRA
),

-- Estado de cada ejercicio: PENDIENTE, OK o REVISAR, con su pista.
F AS (
  SELECT EJERCICIO, NIVEL, K,
    CASE
      WHEN PEND THEN 'PENDIENTE'
      WHEN FILAS_OK AND VALORES_OK AND COLS_ACTUALES = COLS_ESPERADAS AND EXTRA_OK THEN 'OK'
      ELSE 'REVISAR'
    END AS RESULTADO,
    CASE
      WHEN PEND AND EJERCICIO IN ('E1', 'E3') THEN 'Pendiente: el objeto todavía no existe'
      WHEN PEND THEN 'Pendiente: escribe tu SELECT en el marcador'
      WHEN FILAS_OK AND VALORES_OK AND COLS_ACTUALES = COLS_ESPERADAS AND EXTRA_OK THEN 'Correcto'
      WHEN COLS_ACTUALES <> COLS_ESPERADAS THEN 'Nombres u orden de columnas distintos al enunciado'
      WHEN FILAS_OK AND VALORES_OK AND NOT EXTRA_OK THEN PISTA_EXTRA
      WHEN FILAS_OK AND NOT VALORES_OK AND PISTA_EXTRA <> '' THEN PISTA_EXTRA
      ELSE PISTA_MAL
    END AS PISTA,
    COLS_ACTUALES,
    COLS_ESPERADAS
  FROM R
)

-- Resultado final: una fila por ejercicio + la fila de resumen.
-- TUS_COLUMNAS y COLUMNAS_ESPERADAS solo se llenan en las filas REVISAR.
SELECT EJERCICIO, NIVEL, RESULTADO, PISTA, TUS_COLUMNAS, COLUMNAS_ESPERADAS
FROM (
  SELECT EJERCICIO, NIVEL, RESULTADO, PISTA,
    CASE WHEN RESULTADO = 'REVISAR' THEN COLS_ACTUALES END AS TUS_COLUMNAS,
    CASE WHEN RESULTADO = 'REVISAR' THEN COLS_ESPERADAS END AS COLUMNAS_ESPERADAS,
    K
  FROM F
  UNION ALL
  SELECT 'RESUMEN', '★',
    CASE WHEN COUNT_IF(RESULTADO = 'OK' AND NIVEL = '★') = 6 THEN 'OK' ELSE 'REVISAR' END,
    CAST(COUNT_IF(RESULTADO = 'OK' AND NIVEL = '★') AS VARCHAR) || ' de 6 ★ en OK',
    NULL,
    NULL,
    99
  FROM F
)
ORDER BY K;
