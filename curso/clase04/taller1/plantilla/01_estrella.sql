-- GRANO: <escribe aquí, en una frase, qué representa una fila de FACT_VIAJES_DIA. Sugerido: «una fila por fecha, zona y empresa»>
-- =====================================================================
-- TALLER 1 · 01_estrella.sql · DDL de la estrella (esqueleto)
-- Equipo: <nombres> · Anfitrión: <nombre> · Caso elegido: <A, B o C>
-- =====================================================================
-- CÓMO USAR ESTE ARCHIVO
--   1. Copia esta carpeta (plantilla/) a taller1/ en el fork del anfitrión: Add file > Create new
--      file, o Upload files.
--   2. Reemplaza cada línea «TODO» por tu sentencia. Todo se crea en CURSO.T1, con estos nombres:
--      FACT_VIAJES_DIA, DIM_FECHA, DIM_ZONA y DIM_EMPRESA.
--   3. La primera línea de este archivo es el grano. Si cambias el grano sugerido, justifícalo en el memo.
--   4. Cada integrante corre este archivo y 02_carga.sql en su propia cuenta de Snowflake.
--
-- RECORDATORIOS DEL ENUNCIADO (taller1/README.md, secciones 3, 4 y 6)
--   - El hecho guarda medidas aditivas: VIAJES, INGRESO_TOTAL y las sumas que permiten rehacer los
--     promedios (promedio x viajes). La lluvia no va en el hecho.
--   - Cada dimensión tiene una clave única. DIM_ZONA del Lab 4 repite 2 nombres de zona: decide
--     cómo dejar una fila por nombre.
--   - DIM_EMPRESA se construye con SELECT DISTINCT; no escribas los nombres de las empresas a mano.
-- =====================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
CREATE SCHEMA IF NOT EXISTS CURSO.T1;
USE SCHEMA CURSO.T1;

-- TODO · DIM_EMPRESA: clave y nombre de la empresa.
-- CREATE OR REPLACE TABLE DIM_EMPRESA ( ... );

-- TODO · DIM_ZONA: clave única, zona, distrito (BOROUGH) y tipo de zona (SERVICE_ZONE).
-- CREATE OR REPLACE TABLE DIM_ZONA ( ... );

-- TODO · DIM_FECHA: un día por fila, con día de la semana, fin de semana, festivo y la lluvia del día.
-- CREATE OR REPLACE TABLE DIM_FECHA ( ... );

-- TODO · FACT_VIAJES_DIA: las llaves de las dimensiones y las medidas aditivas.
-- CREATE OR REPLACE TABLE FACT_VIAJES_DIA ( ... );

-- Claves (una línea por dimensión): cómo se une cada dimensión con el hecho y por qué esa clave es única.
--   DIM_EMPRESA: <...>
--   DIM_ZONA:    <...>
--   DIM_FECHA:   <...>
