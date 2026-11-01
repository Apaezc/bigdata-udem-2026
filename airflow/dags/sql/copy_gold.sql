-- Carga la capa gold (Parquet escrito por Glue) a Snowflake, en el esquema del entorno.
-- dev -> BIGDATA.DEV, prod -> BIGDATA.PROD. Stage BIGDATA.<ESQUEMA>.LAKE_GOLD -> s3://<lake>/<entorno>/gold/
-- (infra/snowflake). Layout: daily_zone_metrics/mes=YYYY-MM/*.parquet; la columna `fecha` va
-- dentro de los archivos. Orden y tipos = contrato de gold (src/pipeline/gold.py, COLUMNAS).
--
-- Idempotencia: con params.mes se reemplaza ese mes; sin mes se recarga todo el entorno.
-- FORCE = TRUE porque Snowflake recuerda 64 días los archivos ya cargados (sin FORCE, repetir la
-- carga de archivos que no cambiaron cargaría 0 filas después del DELETE).
{%- set esquema = 'PROD' if params.entorno == 'prod' else 'DEV' %}
{%- set tabla = 'BIGDATA.' ~ esquema ~ '.DAILY_ZONE_METRICS' %}

CREATE TABLE IF NOT EXISTS {{ tabla }} (
    FECHA               DATE,
    ZONA                VARCHAR,
    EMPRESA             VARCHAR,
    VIAJES              NUMBER(38, 0),
    INGRESO_TOTAL       FLOAT,
    PROPINA_PROMEDIO    FLOAT,
    DISTANCIA_PROMEDIO  FLOAT,
    LLUVIA_MM           FLOAT
);

{% if params.mes -%}
DELETE FROM {{ tabla }}
WHERE FECHA >= TO_DATE('{{ params.mes }}-01')
  AND FECHA < DATEADD(MONTH, 1, TO_DATE('{{ params.mes }}-01'));
{%- else -%}
TRUNCATE TABLE {{ tabla }};
{%- endif %}

COPY INTO {{ tabla }}
FROM '@BIGDATA.{{ esquema }}.LAKE_GOLD/daily_zone_metrics/{% if params.mes %}mes={{ params.mes }}/{% endif %}'
FILE_FORMAT = (TYPE = PARQUET)
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
PATTERN = '.*[.]parquet'
FORCE = TRUE;
