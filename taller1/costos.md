# Costos · Taller 1

Equipo: Andrea Páez Cardona, Ana María Montealegre, Manuela Restrepo Céspedes, Julian Olaya · Responsable: Julian Olaya (calidad y costos)

Cuenta medida: **la de Julian Olaya**, el 15 de noviembre de 2026. En esa cuenta se reprodujo todo desde cero: Lab 4, estrella del equipo y controles de calidad. El enunciado pide reportar desde la cuenta de la anfitriona (Andrea Páez). Si ella corre las consultas de la sección 2, su fila se agrega a la tabla; las cifras de esta cuenta sirven como medida de cuánto cuesta reproducir el taller completo.

## 1. Warehouse

Configuración comprobada con `SHOW WAREHOUSES LIKE 'COMPUTE_WH'`:

| Warehouse | Tamaño | Suspensión automática | Reanudación automática |
|---|---|---|---|
| COMPUTE_WH | X-Small (1 crédito por hora encendido) | 60 s | Sí |

```sql
-- Configuración usada (la deja así el Paso 0 del Lab 4):
ALTER WAREHOUSE COMPUTE_WH SET WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE;
-- Al terminar una sesión de trabajo, si se quiere apagar de inmediato:
ALTER WAREHOUSE COMPUTE_WH SUSPEND;
```

Por qué XS: el gold tiene 46 715 filas, y la consulta más pesada leyó solo 4,4 MB. Un warehouse más grande cuesta el doble por cada talla y a este volumen no acelera nada: el tiempo se va en compilar y arrancar, no en procesar datos. Con suspensión a 60 s el warehouse se apaga solo al minuto sin consultas, así que no se paga el tiempo muerto entre consulta y consulta.

## 2. Créditos usados

```sql
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE CURSO;
SELECT TO_DATE(START_TIME) AS DIA, ROUND(SUM(CREDITS_USED), 4) AS CREDITOS
FROM TABLE(INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY(
       DATE_RANGE_START => '2026-11-10'::DATE,
       WAREHOUSE_NAME => 'COMPUTE_WH'))
GROUP BY DIA
ORDER BY DIA;
```

| Día medido | Cuenta | Warehouse | Tamaño | Créditos |
|---|---|---|---|---|
| 2026-11-14 | Julian Olaya | COMPUTE_WH | XS | 0,0642 |
| 2026-11-15 (carga del Lab 4, estrella y controles) | Julian Olaya | COMPUTE_WH | XS | 0,0738 |
| **Total desde 2026-11-10** | Julian Olaya | COMPUTE_WH | XS | **0,1381** |
| Total desde 2026-11-10 | Andrea Páez (anfitriona) | COMPUTE_WH | XS | <pendiente: valor de su cuenta> |

Referencia de presupuesto (estimación del pensum, no medida): hasta 0,3 créditos el Lab 4 y hasta 0,8 el taller en clase. **Reproducir todo el taller en una cuenta nueva costó menos de 0,14 créditos**, menos de una quinta parte del presupuesto del taller. Esta consulta puede tardar unos minutos en reflejar el consumo más reciente, así que la cifra del 15 de noviembre puede subir un poco.

Los créditos se cobran por el tiempo que el warehouse está encendido, no por consulta: el mínimo es 1 minuto cada vez que se enciende. Por eso conviene correr las consultas seguidas (Run All) y no de a una con pausas largas entre ellas.

## 3. Consulta más pesada

Encontrada con esta consulta (equivale a Monitoring > Query History > ordenar por duración):

```sql
SELECT QUERY_ID, LEFT(QUERY_TEXT, 80) AS INICIO,
       ROUND(TOTAL_ELAPSED_TIME / 1000, 2) AS SEGUNDOS,
       ROUND(COMPILATION_TIME / 1000, 2)   AS COMPILACION_S,
       ROUND(EXECUTION_TIME / 1000, 2)     AS EJECUCION_S,
       ROUND(BYTES_SCANNED / 1e6, 2)       AS MB_LEIDOS
FROM TABLE(CURSO.INFORMATION_SCHEMA.QUERY_HISTORY_BY_WAREHOUSE(
       WAREHOUSE_NAME => 'COMPUTE_WH',
       END_TIME_RANGE_START => '2026-11-10'::TIMESTAMP_LTZ,
       RESULT_LIMIT => 1000))
WHERE EXECUTION_STATUS = 'SUCCESS'
ORDER BY TOTAL_ELAPSED_TIME DESC
LIMIT 10;
```

Las tres más pesadas:

| # | Consulta | Total | Compilación | Ejecución | MB leídos |
|---|---|---|---|---|---|
| 1 | `05_calidad.sql` (los 56 controles en un solo `SELECT`) | 5,66 s | 4,17 s (74 %) | 1,28 s | 4,42 |
| 2 | `COPY INTO DAILY_ZONE_METRICS` del Lab 4 | 2,33 s | 0,50 s | 0,82 s | 0,66 |
| 3 | `SELECT * FROM EJ1` (Lab 4) | 1,84 s | 1,39 s | 0,21 s | 10,74 |

- Consulta más pesada: la de controles de calidad, `05_calidad.sql` (Query ID `01c86e25-0209-db96-0012-b1ea000ac10e`).
- Captura del Query Profile: [`query_profile.png`](query_profile.png).

## 4. Lectura del Query Profile

- **Dónde se va el tiempo:** casi tres cuartas partes del tiempo total (4,17 de 5,66 s) son **compilación**, no ejecución. La consulta tiene unas 60 subconsultas, y el plan resultante tiene **384 operadores**, que Snowflake debe optimizar antes de leer un solo dato.
- **Operadores que concentran la ejecución** (paso 3 de 3, 1,0 s): `TableScan [10]` con el 33,3 %, y `TableScan [152]` y `TableScan [32]` con el 16,7 % cada uno. En total, la **lectura de tablas suma dos tercios** de la ejecución, porque cada control vuelve a leer el gold o el hecho. Les siguen dos `CartesianJoin` (4,2 % cada uno), que unen los resultados de una fila de cada subconsulta escalar.
- **Desglose de la ejecución:** sincronización 50 %, lectura de disco remoto 20,8 %, inicialización 20,8 % y procesamiento solo 8,3 %. Es decir, el warehouse casi no "piensa": coordina y lee.
- **Qué haríamos para reducirlo:**
  1. Calcular los conteos del gold y del hecho **una sola vez** en dos CTE agregadas (`COUNT(*)`, `SUM(VIAJES)`, sumas por mes con `COUNT_IF` y `SUM(IFF(...))`), en lugar de una subconsulta por control. Así se pasaría de decenas de `TableScan` a unos pocos y bajaría mucho la compilación.
  2. No subir el tamaño del warehouse: leyó 4,4 MB y el procesamiento es el 8 % del tiempo, así que un warehouse más grande solo dobla el costo.
  3. Aceptarlo tal como está. Son 5,7 s una vez antes de entregar, y a cambio todos los controles quedan en una sola corrida. Dividirlos en muchas consultas sueltas encendería el warehouse más veces y costaría más.

## 5. Resumen

Reproducir el taller completo en una cuenta nueva (Lab 4, estrella, vista de A4 y 56 controles de calidad) costó 0,14 créditos con un warehouse XS que se suspende a los 60 s, muy por debajo del presupuesto de 0,8. La consulta más pesada fue la de controles de calidad (5,7 s): el 74 % fue compilación de un plan de 384 operadores. La mejora concreta sería leer el gold y el hecho una sola vez en CTE agregadas, no agrandar el warehouse.
