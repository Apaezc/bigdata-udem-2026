USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
CREATE SCHEMA IF NOT EXISTS CURSO.T1;
USE SCHEMA CURSO.T1;
-- No necesitas leer este archivo: pégalo y pulsa Run All.

-- =====================================================================
-- TALLER 1 · AUTOVERIFICACIÓN (Big Data UdeM · Clase 4)
-- =====================================================================
-- QUÉ HACE
--   Comprueba, en CURSO.T1 de la cuenta de quien lo corre, que la estrella existe y cuadra con el
--   paquete de datos. Devuelve una fila por control y una fila RESUMEN. No exige nombres de llaves
--   ni de dimensiones: solo el nombre del hecho (FACT_VIAJES_DIA) y su columna VIAJES.
--
-- CÓMO CORRERLO
--   1. En Snowsight abre una hoja nueva (+ SQL Worksheet o + > SQL File).
--   2. Pega todo este archivo y pulsa Run All. No elijas rol ni warehouse: las tres primeras
--      líneas los fijan.
--   3. Copia la tabla de resultados (EJERCICIO... CONTROL, RESULTADO, PISTA) en
--      taller1/autoverificacion.txt de tu fork.
--
-- CÓMO LEER EL RESULTADO
--   OK         = el control coincide con el paquete.
--   REVISAR    = el objeto existe y no coincide. Lee la PISTA.
--   PENDIENTE  = todavía no existe lo que se comprueba (por ejemplo, el hecho).
--   AVISO      = informativo: no cuenta como error.
--   RESUMEN    = OK cuando los cuatro controles obligatorios están en OK.
--
-- CONTROLES
--   hecho FACT_VIAJES_DIA      existe en CURSO.T1
--   filas del hecho            COUNT(*) = 46715 (las filas del gold: una por fecha, zona y empresa)
--   viajes del hecho           SUM(VIAJES) = 60268466 (los viajes del gold de enero a marzo)
--   dimensiones                al menos 2 tablas más en CURSO.T1
--   lluvia fuera del hecho     (aviso) el hecho no debería traer la columna LLUVIA_MM
--
-- NOTA
--   Esta verificación no comprueba el grano, los huérfanos ni tus respuestas: eso lo hacen los
--   cuatro chequeos de tu 04_chequeos.sql y la revisión de quien califica.
-- =====================================================================

EXECUTE IMMEDIATE $$
DECLARE
  hecho   NUMBER DEFAULT 0;
  dims    NUMBER DEFAULT 0;
  lluvia  NUMBER DEFAULT 0;
  filas   NUMBER;
  viajes  NUMBER;
  res     RESULTSET;
BEGIN
  SELECT COUNT(*) INTO :hecho
  FROM CURSO.INFORMATION_SCHEMA.TABLES
  WHERE TABLE_SCHEMA = 'T1' AND TABLE_NAME = 'FACT_VIAJES_DIA' AND TABLE_TYPE IN ('BASE TABLE', 'VIEW');

  SELECT COUNT(*) INTO :dims
  FROM CURSO.INFORMATION_SCHEMA.TABLES
  WHERE TABLE_SCHEMA = 'T1' AND TABLE_TYPE = 'BASE TABLE' AND TABLE_NAME <> 'FACT_VIAJES_DIA';

  SELECT COUNT(*) INTO :lluvia
  FROM CURSO.INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'T1' AND TABLE_NAME = 'FACT_VIAJES_DIA' AND COLUMN_NAME = 'LLUVIA_MM';

  IF (hecho > 0) THEN
    BEGIN
      SELECT COUNT(*) INTO :filas FROM CURSO.T1.FACT_VIAJES_DIA;
    EXCEPTION WHEN OTHER THEN
      filas := NULL;
    END;
    BEGIN
      SELECT SUM(VIAJES) INTO :viajes FROM CURSO.T1.FACT_VIAJES_DIA;
    EXCEPTION WHEN OTHER THEN
      viajes := NULL;
    END;
  END IF;

  res := (
    WITH P AS (SELECT :hecho AS HECHO, :filas AS FILAS, :viajes AS VIAJES, :dims AS DIMS, :lluvia AS LLUVIA),
    C AS (
      SELECT 1 AS K, 'hecho FACT_VIAJES_DIA' AS CONTROL,
             IFF(HECHO > 0, 'OK', 'PENDIENTE') AS RESULTADO,
             IFF(HECHO > 0, 'Existe CURSO.T1.FACT_VIAJES_DIA',
                 'Crea CURSO.T1.FACT_VIAJES_DIA con 01_estrella.sql y 02_carga.sql') AS PISTA
      FROM P
      UNION ALL
      SELECT 2, 'filas del hecho',
             CASE WHEN HECHO = 0 THEN 'PENDIENTE' WHEN FILAS = 46715 THEN 'OK' ELSE 'REVISAR' END,
             CASE WHEN HECHO = 0 THEN 'Primero crea y carga el hecho'
                  WHEN FILAS = 46715 THEN 'Tiene 46715 filas, como el paquete'
                  WHEN FILAS IS NULL THEN 'No pude contar las filas del hecho'
                  WHEN FILAS > 46715 THEN 'Tiene ' || FILAS || ' filas y se esperan 46715: una unión repite filas (trampa 4: un nombre de zona con dos identificadores) o cargaste dos veces'
                  ELSE 'Tiene ' || FILAS || ' filas y se esperan 46715: faltan filas (una unión interna perdió zonas o empresas, o la carga quedó incompleta)' END
      FROM P
      UNION ALL
      SELECT 3, 'viajes del hecho',
             CASE WHEN HECHO = 0 THEN 'PENDIENTE' WHEN VIAJES = 60268466 THEN 'OK' ELSE 'REVISAR' END,
             CASE WHEN HECHO = 0 THEN 'Primero crea y carga el hecho'
                  WHEN VIAJES = 60268466 THEN 'Suma 60268466 viajes, como el paquete'
                  WHEN VIAJES IS NULL THEN 'No encuentro la columna VIAJES en el hecho o la suma es nula'
                  WHEN VIAJES > 60268466 THEN 'Suma ' || VIAJES || ' y se esperan 60268466: sobran viajes (trampa 4: unión por un nombre repetido)'
                  ELSE 'Suma ' || VIAJES || ' y se esperan 60268466: faltan viajes' END
      FROM P
      UNION ALL
      SELECT 4, 'dimensiones',
             CASE WHEN HECHO = 0 AND DIMS = 0 THEN 'PENDIENTE' WHEN DIMS >= 2 THEN 'OK' ELSE 'REVISAR' END,
             CASE WHEN HECHO = 0 AND DIMS = 0 THEN 'Todavía no hay tablas en CURSO.T1'
                  WHEN DIMS >= 2 THEN 'Hay ' || DIMS || ' tablas más en CURSO.T1 (las dimensiones)'
                  ELSE 'Tablas más en CURSO.T1: ' || DIMS || '; se piden al menos 2 (las dimensiones)' END
      FROM P
      UNION ALL
      SELECT 5, 'lluvia fuera del hecho (aviso)',
             CASE WHEN HECHO = 0 THEN 'PENDIENTE' WHEN LLUVIA = 0 THEN 'OK' ELSE 'AVISO' END,
             CASE WHEN HECHO = 0 THEN 'Primero crea y carga el hecho'
                  WHEN LLUVIA = 0 THEN 'La lluvia no está en el hecho'
                  ELSE 'El hecho trae LLUVIA_MM: sumarla repite la lluvia de cada día; guárdala una vez por día en una dimensión' END
      FROM P
    )
    SELECT CONTROL, RESULTADO, PISTA FROM C
    UNION ALL
    SELECT 'RESUMEN',
           CASE WHEN (SELECT COUNT_IF(RESULTADO = 'OK') FROM C WHERE K <= 4) = 4 THEN 'OK'
                WHEN (SELECT HECHO FROM P) = 0 THEN 'PENDIENTE'
                ELSE 'REVISAR' END,
           (SELECT COUNT_IF(RESULTADO = 'OK') FROM C WHERE K <= 4) || ' de 4 controles en OK'
    ORDER BY CASE CONTROL WHEN 'RESUMEN' THEN 99
                          WHEN 'hecho FACT_VIAJES_DIA' THEN 1 WHEN 'filas del hecho' THEN 2
                          WHEN 'viajes del hecho' THEN 3 WHEN 'dimensiones' THEN 4 ELSE 5 END
  );
  RETURN TABLE(res);
END;
$$;
