-- =====================================================================
-- TALLER 1 · 02_carga.sql · Carga reproducible desde el Lab 4 (esqueleto)
-- =====================================================================
-- CÓMO USAR ESTE ARCHIVO
--   Reemplaza cada línea «TODO» por tu sentencia (INSERT INTO ... SELECT o CREATE TABLE ... AS
--   SELECT). El archivo se puede correr más de una vez y deja siempre el mismo resultado: carga
--   las dimensiones primero y el hecho después. Los datos de partida están en CURSO.LAB4:
--   DAILY_ZONE_METRICS (46715 filas), DIM_ZONA (265 filas) y FESTIVOS_2024 (11 filas).
--
-- ANTES DE CARGAR EL HECHO
--   Si unes el gold con DIM_ZONA por el nombre de la zona, cuenta las filas antes y después de
--   unir: 46715 antes (trampa 4 del enunciado).
-- =====================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE SCHEMA CURSO.T1;

-- TODO · Carga de DIM_EMPRESA.
-- TODO · Carga de DIM_ZONA (una fila por nombre de zona).
-- TODO · Carga de DIM_FECHA (los días entre el primero y el último del gold; la lluvia del día una sola vez).
-- TODO · Carga de FACT_VIAJES_DIA.

-- TODO · Conteo de control contra el paquete: 46715 filas y 60268466 viajes.
-- SELECT COUNT(*) AS FILAS, SUM(VIAJES) AS VIAJES FROM CURSO.T1.FACT_VIAJES_DIA;
