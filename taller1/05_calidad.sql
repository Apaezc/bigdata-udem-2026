-- =====================================================================
-- TALLER 1 · 05_calidad.sql · Controles contra el origen y trampas
-- Rol: Calidad y costos (Julian Olaya) · Caso A · Competencia entre plataformas
-- =====================================================================
-- QUÉ HACE
--   Un solo SELECT (Run All) que compara la estrella de CURSO.T1 contra el origen
--   CURSO.LAB4.DAILY_ZONE_METRICS y contra las cifras del paquete, y comprueba las
--   cuatro trampas del enunciado (sección 4) más la trampa de LAG.
--   Devuelve una fila por control: BLOQUE, CONTROL, OBTENIDO, ESPERADO, RESULTADO.
--
-- CÓMO LEER EL RESULTADO
--   OK       = coincide con lo esperado.
--   REVISAR  = no coincide: mira la nota del control (abajo, en este archivo).
--   INFO     = cifra informativa que demuestra la trampa (no es un error).
--
-- REQUISITOS
--   Haber corrido 01_estrella.sql y 02_carga.sql. El control L2 usa la vista
--   CURSO.T1.V_CUOTA_ZONA_MES que crea 03_preguntas.sql (pregunta A4).
--
-- POR QUÉ COMPARAR CONTRA EL ORIGEN Y NO SOLO CONTRA EL PAQUETE
--   02_carga.sql carga el hecho con GROUP BY FECHA, ZONA, EMPRESA. Ese GROUP BY
--   escondería filas duplicadas del origen (las sumaría en una), así que el control
--   del grano se hace también sobre el origen (O3), y el dinero se reconcilia
--   sumando las dos tablas con NUMBER y no con FLOAT (trampa 3).
-- =====================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE CURSO;
USE SCHEMA T1;

WITH
G  AS (SELECT * FROM CURSO.LAB4.DAILY_ZONE_METRICS),   -- origen (gold)
F  AS (SELECT * FROM CURSO.T1.FACT_VIAJES_DIA),        -- hecho
DF AS (SELECT * FROM CURSO.T1.DIM_FECHA),
DZ AS (SELECT * FROM CURSO.T1.DIM_ZONA),
DE AS (SELECT * FROM CURSO.T1.DIM_EMPRESA),
Z4 AS (SELECT * FROM CURSO.LAB4.DIM_ZONA),             -- dimensión de zona sin depurar

C (K, BLOQUE, CONTROL, OBTENIDO, ESPERADO) AS (

  -- ------------------------------------------------------------------
  -- 1. ORIGEN: el gold cuadra con el paquete y no trae duplicados
  -- ------------------------------------------------------------------
  SELECT  1, '1 Origen', 'O1 filas del gold',            (SELECT COUNT(*) FROM G), 46715
  UNION ALL SELECT  2, '1 Origen', 'O2 viajes del gold', (SELECT SUM(VIAJES) FROM G), 60268466
  UNION ALL SELECT  3, '1 Origen', 'O3 grano único en el gold (fecha, zona, empresa)',
                   (SELECT COUNT(DISTINCT FECHA, ZONA, EMPRESA) FROM G), 46715
  UNION ALL SELECT  4, '1 Origen', 'O4 días distintos en el gold', (SELECT COUNT(DISTINCT FECHA) FROM G), 91
  UNION ALL SELECT  5, '1 Origen', 'O5 empresas distintas en el gold', (SELECT COUNT(DISTINCT EMPRESA) FROM G), 2

  -- ------------------------------------------------------------------
  -- 2. HECHO CONTRA PAQUETE Y ORIGEN (los cuatro chequeos + reconciliación)
  -- ------------------------------------------------------------------
  UNION ALL SELECT 10, '2 Hecho', 'H1 filas del hecho',  (SELECT COUNT(*) FROM F), 46715
  UNION ALL SELECT 11, '2 Hecho', 'H2 grano único del hecho',
                   (SELECT COUNT(DISTINCT FECHA, ZONA, EMPRESA) FROM F), 46715
  UNION ALL SELECT 12, '2 Hecho', 'H3 viajes del hecho', (SELECT SUM(VIAJES) FROM F), 60268466
  UNION ALL SELECT 13, '2 Hecho', 'H4 filas enero',   (SELECT COUNT(*) FROM F WHERE FECHA BETWEEN '2024-01-01' AND '2024-01-31'), 15909
  UNION ALL SELECT 14, '2 Hecho', 'H5 filas febrero', (SELECT COUNT(*) FROM F WHERE FECHA BETWEEN '2024-02-01' AND '2024-02-29'), 14889
  UNION ALL SELECT 15, '2 Hecho', 'H6 filas marzo',   (SELECT COUNT(*) FROM F WHERE FECHA BETWEEN '2024-03-01' AND '2024-03-31'), 15917
  UNION ALL SELECT 16, '2 Hecho', 'H7 viajes enero',   (SELECT SUM(VIAJES) FROM F WHERE FECHA BETWEEN '2024-01-01' AND '2024-01-31'), 19650023
  UNION ALL SELECT 17, '2 Hecho', 'H8 viajes febrero', (SELECT SUM(VIAJES) FROM F WHERE FECHA BETWEEN '2024-02-01' AND '2024-02-29'), 19344724
  UNION ALL SELECT 18, '2 Hecho', 'H9 viajes marzo',   (SELECT SUM(VIAJES) FROM F WHERE FECHA BETWEEN '2024-03-01' AND '2024-03-31'), 21273719
  -- Reconciliación de dinero y sumas contra el origen: diferencia exacta con NUMBER (trampa 3).
  UNION ALL SELECT 19, '2 Hecho', 'H10 diferencia de INGRESO_TOTAL hecho - origen (USD)',
                   (SELECT SUM(ROUND(INGRESO_TOTAL, 2)::NUMBER(18,2)) FROM F)
                 - (SELECT SUM(ROUND(INGRESO_TOTAL, 2)::NUMBER(18,2)) FROM G), 0
  UNION ALL SELECT 20, '2 Hecho', 'H11 diferencia de PROPINA_TOTAL hecho - origen (USD)',
                   (SELECT SUM(ROUND(PROPINA_TOTAL, 2)::NUMBER(18,2)) FROM F)
                 - (SELECT SUM(ROUND(PROPINA_PROMEDIO * VIAJES, 2)::NUMBER(18,2)) FROM G), 0
  UNION ALL SELECT 21, '2 Hecho', 'H12 diferencia de DISTANCIA_TOTAL hecho - origen (millas)',
                   (SELECT SUM(ROUND(DISTANCIA_TOTAL, 2)::NUMBER(18,2)) FROM F)
                 - (SELECT SUM(ROUND(DISTANCIA_PROMEDIO * VIAJES, 2)::NUMBER(18,2)) FROM G), 0
  -- Fila a fila: filas del origen que no aparecen igual en el hecho (y al revés).
  UNION ALL SELECT 22, '2 Hecho', 'H13 filas del origen que faltan o difieren en el hecho',
                   (SELECT COUNT(*) FROM (SELECT FECHA, ZONA, EMPRESA, VIAJES FROM G
                                          MINUS SELECT FECHA, ZONA, EMPRESA, VIAJES FROM F)), 0
  UNION ALL SELECT 23, '2 Hecho', 'H14 filas del hecho que no existen en el origen',
                   (SELECT COUNT(*) FROM (SELECT FECHA, ZONA, EMPRESA, VIAJES FROM F
                                          MINUS SELECT FECHA, ZONA, EMPRESA, VIAJES FROM G)), 0
  UNION ALL SELECT 24, '2 Hecho', 'H15 llaves nulas en el hecho',
                   (SELECT COUNT_IF(FECHA IS NULL OR ZONA IS NULL OR EMPRESA IS NULL) FROM F), 0
  UNION ALL SELECT 25, '2 Hecho', 'H16 viajes cero o negativos en el hecho',
                   (SELECT COUNT_IF(VIAJES <= 0) FROM F), 0

  -- ------------------------------------------------------------------
  -- 3. HUÉRFANOS: cada llave del hecho existe en su dimensión
  -- ------------------------------------------------------------------
  UNION ALL SELECT 30, '3 Huérfanos', 'U1 hecho sin zona en DIM_ZONA',
                   (SELECT COUNT(*) FROM F LEFT JOIN DZ ON F.ZONA = DZ.ZONA WHERE DZ.ZONA IS NULL), 0
  UNION ALL SELECT 31, '3 Huérfanos', 'U2 hecho sin fecha en DIM_FECHA',
                   (SELECT COUNT(*) FROM F LEFT JOIN DF ON F.FECHA = DF.FECHA WHERE DF.FECHA IS NULL), 0
  UNION ALL SELECT 32, '3 Huérfanos', 'U3 hecho sin empresa en DIM_EMPRESA',
                   (SELECT COUNT(*) FROM F LEFT JOIN DE ON F.EMPRESA = DE.EMPRESA WHERE DE.EMPRESA IS NULL), 0
  UNION ALL SELECT 33, '3 Huérfanos', 'U4 zonas del gold sin pareja en DIM_ZONA del Lab 4',
                   (SELECT COUNT(DISTINCT G.ZONA) FROM G LEFT JOIN Z4 ON G.ZONA = Z4.ZONA WHERE Z4.ZONA IS NULL), 0

  -- ------------------------------------------------------------------
  -- 4. DIMENSIONES: tamaño y clave única
  -- ------------------------------------------------------------------
  UNION ALL SELECT 40, '4 Dimensiones', 'D1 filas de DIM_FECHA (31+29+31)', (SELECT COUNT(*) FROM DF), 91
  UNION ALL SELECT 41, '4 Dimensiones', 'D2 fechas únicas en DIM_FECHA', (SELECT COUNT(DISTINCT FECHA) FROM DF), 91
  UNION ALL SELECT 42, '4 Dimensiones', 'D3 días entre MIN y MAX de DIM_FECHA',
                   (SELECT DATEDIFF('day', MIN(FECHA), MAX(FECHA)) + 1 FROM DF), 91
  UNION ALL SELECT 43, '4 Dimensiones', 'D4 festivos en DIM_FECHA (1 y 15 ene, 19 feb)',
                   (SELECT COUNT_IF(ES_FESTIVO) FROM DF), 3
  UNION ALL SELECT 44, '4 Dimensiones', 'D5 días de fin de semana en DIM_FECHA',
                   (SELECT COUNT_IF(ES_FIN_SEMANA) FROM DF), 26
  UNION ALL SELECT 45, '4 Dimensiones', 'D6 filas de DIM_ZONA (una por nombre)', (SELECT COUNT(*) FROM DZ), 262
  UNION ALL SELECT 46, '4 Dimensiones', 'D7 nombres únicos en DIM_ZONA', (SELECT COUNT(DISTINCT ZONA) FROM DZ), 262
  UNION ALL SELECT 47, '4 Dimensiones', 'D8 filas de DIM_EMPRESA = empresas del gold',
                   (SELECT COUNT(*) FROM DE), (SELECT COUNT(DISTINCT EMPRESA) FROM G)

  -- ------------------------------------------------------------------
  -- 5. TRAMPA 1 · La lluvia se repite en cada fila del día
  -- ------------------------------------------------------------------
  UNION ALL SELECT 50, '5 Trampa 1 lluvia', 'T1a días del gold con más de un valor de lluvia',
                   (SELECT COUNT(*) FROM (SELECT FECHA FROM G GROUP BY FECHA
                                          HAVING COUNT(DISTINCT LLUVIA_MM) > 1)), 0
  UNION ALL SELECT 51, '5 Trampa 1 lluvia', 'T1b días donde DIM_FECHA no tiene la lluvia del gold',
                   (SELECT COUNT(*) FROM DF JOIN (SELECT FECHA, MAX(LLUVIA_MM) AS L FROM G GROUP BY FECHA) O
                                         ON DF.FECHA = O.FECHA
                    WHERE DF.LLUVIA_MM IS NULL OR ABS(DF.LLUVIA_MM - O.L) >= 0.01), 0
  UNION ALL SELECT 52, '5 Trampa 1 lluvia', 'T1c lluvia en el hecho (columnas LLUVIA_MM)',
                   (SELECT COUNT(*) FROM CURSO.INFORMATION_SCHEMA.COLUMNS
                    WHERE TABLE_SCHEMA = 'T1' AND TABLE_NAME = 'FACT_VIAJES_DIA' AND COLUMN_NAME = 'LLUVIA_MM'), 0
  UNION ALL SELECT 53, '5 Trampa 1 lluvia', 'T1d lluvia del 2024-01-10 en DIM_FECHA (mm, correcto)',
                   (SELECT LLUVIA_MM FROM DF WHERE FECHA = '2024-01-10'), 21.7
  UNION ALL SELECT 54, '5 Trampa 1 lluvia', 'T1e INFO: SUM(LLUVIA_MM) del 2024-01-10 en el gold (mal)',
                   (SELECT ROUND(SUM(LLUVIA_MM), 1) FROM G WHERE FECHA = '2024-01-10'), NULL
  UNION ALL SELECT 55, '5 Trampa 1 lluvia', 'T1f INFO: COUNT(*) del gold (filas, no días)',
                   (SELECT COUNT(*) FROM G), NULL

  -- ------------------------------------------------------------------
  -- 6. TRAMPA 2 · Promediar promedios
  --    Ejemplo del enunciado: JFK Airport, 2024-01-24 (Lyft 4.05 con 1 965 viajes; Uber 3.76 con 7 265)
  -- ------------------------------------------------------------------
  UNION ALL SELECT 60, '6 Trampa 2 promedios', 'T2a propina ponderada JFK 2024-01-24 desde el gold',
                   (SELECT ROUND(SUM(PROPINA_PROMEDIO * VIAJES) / SUM(VIAJES), 2) FROM G
                    WHERE FECHA = '2024-01-24' AND ZONA = 'JFK Airport'), 3.82
  UNION ALL SELECT 61, '6 Trampa 2 promedios', 'T2b propina ponderada JFK 2024-01-24 desde el hecho',
                   (SELECT ROUND(SUM(PROPINA_TOTAL) / SUM(VIAJES), 2) FROM F
                    WHERE FECHA = '2024-01-24' AND ZONA = 'JFK Airport'), 3.82
  UNION ALL SELECT 62, '6 Trampa 2 promedios', 'T2c INFO: promedio simple JFK 2024-01-24 (mal)',
                   (SELECT ROUND(AVG(PROPINA_PROMEDIO), 3) FROM G
                    WHERE FECHA = '2024-01-24' AND ZONA = 'JFK Airport'), NULL
  -- La propina ponderada por empresa (pregunta A2) sale igual desde el gold y desde el hecho.
  UNION ALL SELECT 63, '6 Trampa 2 promedios', 'T2d empresas cuya propina ponderada difiere gold vs hecho',
                   (SELECT COUNT(*) FROM
                      (SELECT EMPRESA, SUM(PROPINA_PROMEDIO * VIAJES) / SUM(VIAJES) AS P FROM G GROUP BY EMPRESA) A
                      JOIN (SELECT EMPRESA, SUM(PROPINA_TOTAL) / SUM(VIAJES) AS P FROM F GROUP BY EMPRESA) B
                        ON A.EMPRESA = B.EMPRESA
                    WHERE ABS(A.P - B.P) >= 0.01), 0

  -- ------------------------------------------------------------------
  -- 7. TRAMPA 3 · El redondeo de FLOAT
  -- ------------------------------------------------------------------
  UNION ALL SELECT 70, '7 Trampa 3 redondeo', 'T3a INFO: 0.1 + 0.2 = 0.3 con FLOAT (1 = TRUE, 0 = FALSE)',
                   IFF(0.1::FLOAT + 0.2::FLOAT = 0.3::FLOAT, 1, 0), NULL
  UNION ALL SELECT 71, '7 Trampa 3 redondeo', 'T3b ROUND(0.1 + 0.2, 2) = 0.3 (1 = TRUE)',
                   IFF(ROUND(0.1::FLOAT + 0.2::FLOAT, 2) = 0.3, 1, 0), 1
  UNION ALL SELECT 72, '7 Trampa 3 redondeo', 'T3c ABS(diferencia FLOAT de ingreso hecho - gold) < 0.01 (1 = TRUE)',
                   IFF(ABS((SELECT SUM(INGRESO_TOTAL) FROM F) - (SELECT SUM(INGRESO_TOTAL) FROM G)) < 0.01, 1, 0), 1

  -- ------------------------------------------------------------------
  -- 8. TRAMPA 4 · El nombre de zona repetido
  -- ------------------------------------------------------------------
  UNION ALL SELECT 80, '8 Trampa 4 zona', 'T4a nombres repetidos en DIM_ZONA del Lab 4',
                   (SELECT COUNT(*) FROM (SELECT ZONA FROM Z4 GROUP BY ZONA HAVING COUNT(*) > 1)), 2
  UNION ALL SELECT 81, '8 Trampa 4 zona', 'T4b nombres repetidos con distrito o tipo de zona distinto',
                   (SELECT COUNT(*) FROM (SELECT ZONA FROM Z4 GROUP BY ZONA
                                          HAVING COUNT(DISTINCT BOROUGH, SERVICE_ZONE) > 1)), 0
  UNION ALL SELECT 82, '8 Trampa 4 zona', 'T4c INFO: filas al unir el gold con DIM_ZONA del Lab 4 por nombre (mal)',
                   (SELECT COUNT(*) FROM G JOIN Z4 ON G.ZONA = Z4.ZONA), NULL
  UNION ALL SELECT 83, '8 Trampa 4 zona', 'T4d INFO: filas que sobran con esa unión (enunciado: 196)',
                   (SELECT COUNT(*) FROM G JOIN Z4 ON G.ZONA = Z4.ZONA) - (SELECT COUNT(*) FROM G), NULL
  UNION ALL SELECT 84, '8 Trampa 4 zona', 'T4e INFO: viajes que sobran con esa unión (enunciado: 184 265)',
                   (SELECT SUM(G.VIAJES) FROM G JOIN Z4 ON G.ZONA = Z4.ZONA) - (SELECT SUM(VIAJES) FROM G), NULL
  UNION ALL SELECT 85, '8 Trampa 4 zona', 'T4f filas al unir el hecho con DIM_ZONA depurada (correcto)',
                   (SELECT COUNT(*) FROM F JOIN DZ ON F.ZONA = DZ.ZONA), 46715
  UNION ALL SELECT 86, '8 Trampa 4 zona', 'T4g viajes al unir el hecho con DIM_ZONA depurada (correcto)',
                   (SELECT SUM(F.VIAJES) FROM F JOIN DZ ON F.ZONA = DZ.ZONA), 60268466

  -- ------------------------------------------------------------------
  -- 9. TRAMPA DE LAG · LAG mira la fila anterior, no el mes anterior
  --    A5 usa LAG por zona y empresa sobre la vista V_CUOTA_ZONA_MES (03_preguntas.sql),
  --    que completa con 0 los meses sin viajes. Si la rejilla está completa, cada
  --    (zona, empresa) tiene exactamente 3 meses y LAG compara meses seguidos.
  -- ------------------------------------------------------------------
  UNION ALL SELECT 90, '9 Trampa LAG', 'L1 INFO: parejas (zona, empresa) del gold a las que les falta algún mes',
                   (SELECT COUNT(*) FROM (SELECT ZONA, EMPRESA FROM G GROUP BY ZONA, EMPRESA
                                          HAVING COUNT(DISTINCT DATE_TRUNC('month', FECHA)) < 3)), NULL
  UNION ALL SELECT 91, '9 Trampa LAG', 'L2 filas de V_CUOTA_ZONA_MES = 3 meses x parejas (zona, empresa)',
                   (SELECT COUNT(*) FROM CURSO.T1.V_CUOTA_ZONA_MES),
                   (SELECT 3 * COUNT(DISTINCT ZONA, EMPRESA) FROM G)
  UNION ALL SELECT 92, '9 Trampa LAG', 'L3 viajes en V_CUOTA_ZONA_MES (los ceros no suman)',
                   (SELECT SUM(VIAJES) FROM CURSO.T1.V_CUOTA_ZONA_MES), 60268466
)

SELECT
    BLOQUE,
    CONTROL,
    OBTENIDO,
    ESPERADO,
    CASE
        WHEN ESPERADO IS NULL                    THEN 'INFO'
        WHEN OBTENIDO IS NULL                    THEN 'REVISAR'
        WHEN ABS(OBTENIDO - ESPERADO) < 0.01     THEN 'OK'      -- nunca "=" con decimales (trampa 3)
        ELSE 'REVISAR'
    END AS RESULTADO
FROM C
UNION ALL
SELECT
    '0 RESUMEN',
    'controles en OK / controles con valor esperado',
    COUNT_IF(ESPERADO IS NOT NULL AND OBTENIDO IS NOT NULL AND ABS(OBTENIDO - ESPERADO) < 0.01),
    COUNT_IF(ESPERADO IS NOT NULL),
    IFF(COUNT_IF(ESPERADO IS NOT NULL AND OBTENIDO IS NOT NULL AND ABS(OBTENIDO - ESPERADO) < 0.01)
        = COUNT_IF(ESPERADO IS NOT NULL), 'OK', 'REVISAR')
FROM C
ORDER BY BLOQUE, CONTROL;

-- =====================================================================
-- NOTAS PARA LEER UN «REVISAR»
--   O1/O2/O3   El gold del Lab 4 no está completo o tiene duplicados: rehacer el Lab 4.
--   H1/H3      Más filas o viajes de lo esperado: carga corrida dos veces o unión por nombre
--              repetido (trampa 4). Menos: una unión interna perdió filas.
--   H2 < H1    Hay duplicados en el grano del hecho.
--   H4–H9      La carga quedó incompleta en algún mes.
--   H10–H12    El hecho no reproduce el dinero o las sumas del origen; si la diferencia es de
--              centavos, revisa que se sume con ROUND/NUMBER y no con FLOAT.
--   H13/H14    Hay filas distintas entre hecho y origen (MINUS compara fila a fila).
--   U1–U3      Huérfanos: una llave del hecho no existe en su dimensión.
--   U4         Una zona del gold no está en el catálogo de la TLC (se perdería en una unión).
--   D1–D3      DIM_FECHA no tiene los 91 días seguidos (02_carga.sql genera 91 días desde
--              2024-01-01; si el gold cambia de rango, hay que cambiar esa fecha).
--   D4/D5      Festivos o fines de semana mal marcados.
--   D6/D7      DIM_ZONA repite nombres: la unión por nombre inflaría el hecho.
--   T1a        La lluvia no es única por día en el gold: no se puede guardar una vez por día.
--   T1b–T1d    DIM_FECHA no guarda la lluvia del día del gold.
--   T2a/T2b    El hecho no permite rehacer el promedio ponderado.
--   T4b        Dos filas con el mismo nombre de zona tienen distinto distrito: quedarse con
--              una sola pierde información y habría que decidir de otro modo.
--   L2/L3      La rejilla de A4/A5 no está completa: LAG compararía meses no seguidos.
-- =====================================================================
