-- =====================================================================
-- festivos_2024 · Festivos federales de EE. UU. en 2024
-- =====================================================================
-- FUENTE
--   U.S. Office of Personnel Management (OPM), "Federal Holidays 2024"
--   https://www.opm.gov/policy-data-oversight/pay-leave/federal-holidays/
--   Fechas confirmadas contra esa página (consulta del 2026-11-10).
--
-- FILAS
--   11 festivos federales, uno por fila. Son solo los festivos federales
--   oficiales; no incluye fechas estatales ni locales.
--
-- NOTA
--   "Washington's Birthday" es el nombre que usa la ley federal para el
--   tercer lunes de febrero (muchas instituciones lo llaman Presidents' Day).
--
-- COLUMNAS
--   FECHA   fecha del festivo (tipo DATE)
--   NOMBRE  nombre oficial del festivo en inglés, tal como lo publica OPM
--
-- CÓMO USARLO
--   Ejecuta todo el archivo en una worksheet de Snowsight con el esquema
--   donde quieres la tabla ya seleccionado. Es reejecutable: CREATE OR
--   REPLACE vuelve a crear la tabla desde cero.
-- =====================================================================

CREATE OR REPLACE TABLE festivos_2024 (
  FECHA  DATE NOT NULL,
  NOMBRE VARCHAR
);

INSERT INTO festivos_2024 (FECHA, NOMBRE) VALUES
  (DATE '2024-01-01', 'New Year''s Day'),
  (DATE '2024-01-15', 'Birthday of Martin Luther King, Jr.'),
  (DATE '2024-02-19', 'Washington''s Birthday'),
  (DATE '2024-05-27', 'Memorial Day'),
  (DATE '2024-06-19', 'Juneteenth National Independence Day'),
  (DATE '2024-07-04', 'Independence Day'),
  (DATE '2024-09-02', 'Labor Day'),
  (DATE '2024-10-14', 'Columbus Day'),
  (DATE '2024-11-11', 'Veterans Day'),
  (DATE '2024-11-28', 'Thanksgiving Day'),
  (DATE '2024-12-25', 'Christmas Day');

-- Verificación rápida: debe devolver 11
SELECT COUNT(*) AS filas FROM festivos_2024;
