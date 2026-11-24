-- =====================================================================
-- CLASE 7 · Athena sobre el lake · 02 · Qué dejó cada paso, duplicados y conciliación
-- =====================================================================
--
-- PROBLEMA
--   El pipeline corrió, las tareas salieron en verde y nadie recibió un error. ¿Cómo sé que las
--   cifras son las correctas? Mirando lo que cada paso dejó en S3, con SQL, y comparando capas.
--   Este archivo tiene las consultas de cada PUNTO DE CONTROL de la clase, en este orden:
--
--     A · después de bronze      ¿qué se ingestó? ¿cuántos lotes y cuántas filas por lote?
--     B · después de silver      ¿cuántas filas quedaron y cuántas se descartaron?
--     C · después de gold        ¿cuadran los viajes de gold con las filas de silver?
--     D · después de reprocesar  ¿hay filas duplicadas? ¿por cuánto se multiplicó cada capa?
--     E · en Snowflake           la tabla de control y la tabla cargada
--
-- ANTES DE EMPEZAR
--   1. Ejecuta 01_tablas.sql con <CUENTA> y <ENTORNO>=dev ya reemplazados. En el editor de
--      Athena: workgroup bigdata-wg, data source AwsDataCatalog, database bigdata_lake, región
--      us-east-2.
--   2. Una sentencia por vez. Después de cada una, lee en la barra de resultados "Data scanned"
--      y "Run time".
--   3. Este archivo lee las tablas de DEV (dev_bronze_..., dev_silver_..., dev_gold_...). Para
--      validar prod, cambia dev_ por prod_ en cada consulta (Ctrl+F / Cmd+F > Reemplazar todo).
--   4. Todas filtran por mes = '2024-01': Athena solo abre esa carpeta.
--   5. Repite las consultas de cada punto de control CADA VEZ que corras un paso: la
--      diferencia entre una corrida y la siguiente es lo que se mira.
--
-- DOS REGLAS PARA LEER LAS CIFRAS
--   · El límite (limite=1000) se aplica SOLO en bronze, justo después de leer el archivo de la
--     fuente y antes de transformar o escribir. Por eso bronze guarda 1 000 filas de viajes por
--     lote (las mismas siempre) y silver y gold leen TODO lo que hay en bronze, sin límite.
--   · Con reprocesar=false, correr un paso por segunda vez SE SALTA (la tabla de control es la
--     puerta): no hay lote nuevo y no hay duplicados. Los duplicados aparecen solo al forzar
--     reprocesar=true, porque entonces bronze escribe otro lote del mismo mes.
--
-- LO QUE SE ESPERA, EN UNA TABLA (relaciones, no cifras exactas: las cifras se anotan en el ensayo)
--
--     después de                          lotes   silver (viajes, clima, zonas)   gold (viajes)
--     la 1.ª ingesta, sin reprocesar        1        ×1                              ×1
--     reprocesar=true una vez               2        ×2                              ×8
--     reprocesar=true otra vez              3        ×3                              ×27
--
--   Gold crece con el cubo de los lotes porque enriquecer une los viajes con las zonas y con el
--   clima, y esas tres tablas de silver están repetidas (silver no deduplica). Los factores
--   ×2 y ×8 se midieron en el ensayo del 22 y 23 de noviembre; ×27 es lo esperado con un tercer lote.
-- =====================================================================


-- =====================================================================
-- PUNTO DE CONTROL A · después de correr bronze
-- =====================================================================

-- A1. ¿Cuántos lotes tiene bronze y cuántas filas trae cada uno? El lote sale de la ruta del
--     archivo ("$path" termina en .../lote=<id>/...). Con limite=1000, cada lote de viajes trae
--     1 000 filas. Tras la 1.ª ingesta: una fila de resultado. Tras reprocesar: dos, y así.
SELECT regexp_extract("$path", 'lote=([^/]+)', 1) AS lote, count(*) AS filas
FROM bigdata_lake.dev_bronze_fhvhv
WHERE mes = '2024-01'
GROUP BY regexp_extract("$path", 'lote=([^/]+)', 1)
ORDER BY lote;

-- A2. Lo mismo para el clima (31 filas por lote) y las zonas (265 por lote).
SELECT 'clima' AS tabla, regexp_extract("$path", 'lote=([^/]+)', 1) AS lote, count(*) AS filas
FROM bigdata_lake.dev_bronze_clima
WHERE mes = '2024-01'
GROUP BY regexp_extract("$path", 'lote=([^/]+)', 1)
UNION ALL
SELECT 'taxi_zones', regexp_extract("$path", 'lote=([^/]+)', 1), count(*)
FROM bigdata_lake.dev_bronze_taxi_zones
GROUP BY regexp_extract("$path", 'lote=([^/]+)', 1)
ORDER BY 1, 2;

-- A3. ¿Qué trae cada fila de bronze? Cinco columnas de metadatos (_fecha_ingesta, _id_lote,
--     _hash_fila, _fuente, _archivo_origen) SI agregar_metadatos las agregó. Mientras esa función
--     no haga nada, count("_hash_fila") es 0: bronze no dice de qué lote ni de qué archivo vino
--     cada fila, ni tiene huella para reconocer una fila repetida. Es el primer problema.
SELECT
  count(*)                     AS filas,
  count("_hash_fila")          AS filas_con_huella,
  count("_id_lote")            AS filas_con_lote,
  min(pickup_datetime)         AS primera_recogida,
  max(pickup_datetime)         AS ultima_recogida
FROM bigdata_lake.dev_bronze_fhvhv
WHERE mes = '2024-01';

-- A4. Unas filas de muestra, con el archivo del que salen.
SELECT pickup_datetime, hvfhs_license_num, pulocationid, trip_miles, base_passenger_fare,
       "$path" AS archivo
FROM bigdata_lake.dev_bronze_fhvhv
WHERE mes = '2024-01'
LIMIT 5;

-- A5. Opcional: el archivo crudo completo frente a lo que bronze guardó (por el límite). Requiere
--     la tabla dev_crudo_fhvhv del bloque 9 de 01_tablas.sql. Un conteo no lee columnas:
--     Data scanned es casi 0.
SELECT
  (SELECT count(*) FROM bigdata_lake.dev_crudo_fhvhv WHERE mes = '2024-01') AS filas_del_archivo,
  (SELECT count(*) FROM bigdata_lake.dev_bronze_fhvhv WHERE mes = '2024-01') AS filas_en_bronze;


-- =====================================================================
-- PUNTO DE CONTROL B · después de correr silver
-- =====================================================================

-- B1. Silver lee TODOS los lotes de bronze del mes y deja los viajes que pasan los filtros.
--     filas_en_bronze menos filas_en_silver son los descartes. Con un lote: pocos o ninguno en
--     1 000 viajes. Con dos lotes, silver tiene el doble que con uno: nadie avisó.
SELECT
  (SELECT count(*) FROM bigdata_lake.dev_bronze_fhvhv WHERE mes = '2024-01') AS filas_en_bronze,
  (SELECT count(*) FROM bigdata_lake.dev_silver_fhvhv WHERE mes = '2024-01') AS filas_en_silver;

-- B2. Las tres tablas de silver. Si el pipeline está sano, taxi_zones tiene 265 filas y clima 31
--     por mes, y no más: una tabla de referencia no puede crecer. Con dos lotes: 530 y 62.
SELECT 'fhvhv' AS tabla, count(*) AS filas
FROM bigdata_lake.dev_silver_fhvhv WHERE mes = '2024-01'
UNION ALL
SELECT 'clima', count(*) FROM bigdata_lake.dev_silver_clima WHERE mes = '2024-01'
UNION ALL
SELECT 'taxi_zones', count(*) FROM bigdata_lake.dev_silver_taxi_zones;

-- B3. Silver conserva la huella y el lote SI bronze los agregó. Sin metadatos: 0 y 0.
SELECT count(*) AS filas, count("_hash_fila") AS con_huella, count("_id_lote") AS con_lote
FROM bigdata_lake.dev_silver_fhvhv
WHERE mes = '2024-01';


-- =====================================================================
-- PUNTO DE CONTROL C · después de correr gold
-- =====================================================================

-- C1. Gold agrega: no tiene una fila por viaje sino una por (fecha, barrio, franja). Lo que se
--     compara es la SUMA de su columna viajes contra las filas de silver. Si el pipeline está
--     sano, la relación vale 1. Tras reprocesar una vez, vale 4 (8 contra la cifra limpia).
SELECT
  (SELECT sum(viajes) FROM bigdata_lake.dev_gold_tarifa_por_milla_barrio
   WHERE mes = '2024-01') AS viajes_en_gold,
  (SELECT count(*) FROM bigdata_lake.dev_silver_fhvhv
   WHERE mes = '2024-01') AS filas_en_silver,
  CAST((SELECT sum(viajes) FROM bigdata_lake.dev_gold_tarifa_por_milla_barrio
        WHERE mes = '2024-01') AS double)
    / (SELECT count(*) FROM bigdata_lake.dev_silver_fhvhv
       WHERE mes = '2024-01') AS relacion;

-- C2. Las filas de gold (una por fecha, barrio y franja) y el rango de fechas.
SELECT count(*) AS filas_de_gold, min(fecha) AS desde, max(fecha) AS hasta
FROM bigdata_lake.dev_gold_tarifa_por_milla_barrio
WHERE mes = '2024-01';


-- =====================================================================
-- PUNTO DE CONTROL D · detectar los duplicados (después de reprocesar=true)
-- =====================================================================

-- D1. Sin saber de antemano que hay un problema, ¿cómo se detecta? Buscando filas que se
--     repiten. Un viaje se describe por cuándo empezó y terminó, de dónde a dónde, quién lo hizo,
--     cuánto recorrió y cuánto cobró; dos filas iguales en todo eso son casi seguro el mismo
--     viaje. filas_de_mas es cuántas filas sobran. Con un lote: casi 0 (dos viajes reales pueden
--     coincidir en todo). Con dos lotes: casi igual a las filas del primer lote.
SELECT
  count(*) AS filas,
  count(*) - (
    SELECT count(*) FROM (
      SELECT DISTINCT pickup_datetime, dropoff_datetime, pu_location_id, do_location_id,
                      empresa, distancia_mi, tarifa_base, total_pagado
      FROM bigdata_lake.dev_silver_fhvhv
      WHERE mes = '2024-01'
    )
  ) AS filas_de_mas
FROM bigdata_lake.dev_silver_fhvhv
WHERE mes = '2024-01';

-- D2. Las filas repetidas, con cuántas veces aparece cada una. Tras reprocesar una vez, casi
--     todas aparecen 2 veces; tras la tercera corrida, 3.
SELECT veces, count(*) AS grupos
FROM (
  SELECT count(*) AS veces
  FROM bigdata_lake.dev_silver_fhvhv
  WHERE mes = '2024-01'
  GROUP BY pickup_datetime, dropoff_datetime, pu_location_id, do_location_id,
           empresa, distancia_mi, tarifa_base, total_pagado
)
GROUP BY veces
ORDER BY veces;

-- D3. Con la huella de la fila la comprobación es una línea: filas frente a huellas distintas.
--     Mientras bronze no agregue los metadatos, "_hash_fila" es NULL (huellas = 0): ese NULL es la
--     prueba de que falta agregar_metadatos. Cuando tu equipo la escriba y se reprocese, filas
--     menos huellas_distintas dice cuántas copias sobran, sin elegir columnas a mano.
SELECT
  count(*)                     AS filas,
  count(DISTINCT "_hash_fila") AS huellas_distintas
FROM bigdata_lake.dev_silver_fhvhv
WHERE mes = '2024-01';

-- D4. El factor de cada capa, juntando los puntos de control. lotes sale de bronze; los factores
--     de silver y de gold se calculan contra las filas de UN lote de bronze (con limite=1000,
--     los viajes de un lote son 1 000 antes de los filtros). Debe dar lotes, lotes y lotes al
--     cubo: 1 / 2 / 3 en silver y 1 / 8 / 27 en gold.
SELECT
  (SELECT count(DISTINCT regexp_extract("$path", 'lote=([^/]+)', 1))
   FROM bigdata_lake.dev_bronze_fhvhv WHERE mes = '2024-01') AS lotes_en_bronze,
  (SELECT count(*) FROM bigdata_lake.dev_silver_taxi_zones) AS filas_de_zonas_en_silver,
  (SELECT count(*) FROM bigdata_lake.dev_silver_clima
   WHERE mes = '2024-01') AS filas_de_clima_en_silver,
  (SELECT sum(viajes) FROM bigdata_lake.dev_gold_tarifa_por_milla_barrio
   WHERE mes = '2024-01') AS viajes_en_gold,
  (SELECT count(*) FROM bigdata_lake.dev_silver_fhvhv
   WHERE mes = '2024-01') AS filas_de_viajes_en_silver;

-- D5. Después de que tu equipo escriba agregar_metadatos y deduplicar, resetea dev y repite el
--     pipeline y los reprocesos: silver debe quedar igual con 1, 2 o 3 lotes y la relación de
--     C1 debe ser SIEMPRE 1. Ese es el criterio de que silver es idempotente: pase lo que pase
--     en bronze, silver es el reflejo de la fuente, sin duplicados.


-- =====================================================================
-- PUNTO DE CONTROL E · Snowflake (NO es Athena: va en una hoja de Snowsight)
-- =====================================================================
-- Pega los bloques de uno en uno. Las tres primeras líneas eligen rol, warehouse y base de datos
-- y se escriben siempre: con ACCOUNTADMIN no puedes crear ni alterar en BIGDATA.DEV.
--
--   USE ROLE BIGDATA_DEV;
--   USE WAREHOUSE BIGDATA_WH;
--   USE DATABASE BIGDATA;
--
-- E1. Todo lo que anotó el pipeline en dev, en orden. Cada paso terminado deja una fila: FILAS
--     son las filas ESCRITAS y LEIDAS las leídas (solo informativa). Mírala después de cada
--     tarea: es lo que hace la llamada a la tabla de control.
--   SELECT TABLA, CAPA, MES, FILAS, LEIDAS, COMPUTO, LIMITE, REPROCESAR, INICIO
--   FROM BIGDATA.CONTROL_DEV.WATERMARK
--   ORDER BY INICIO;
--
-- E2. La conciliación usa el ÚLTIMO registro por (tabla, capa, mes): reprocesar no borra la
--     historia, así que una misma clave puede tener varias filas.
--   SELECT TABLA, CAPA, MES, FILAS, LEIDAS, COMPUTO, INICIO
--   FROM BIGDATA.CONTROL_DEV.WATERMARK
--   QUALIFY ROW_NUMBER() OVER (PARTITION BY TABLA, CAPA, MES ORDER BY INICIO DESC) = 1
--   ORDER BY CAPA, TABLA, MES;
--
-- E3. Gold en Snowflake frente a lo que registró el paso gold. FILAS son filas de gold (una por
--     fecha, barrio y franja); los viajes se comparan con SUM(VIAJES).
--   SELECT COUNT(*) AS filas, SUM(VIAJES) AS viajes, MIN(FECHA) AS desde, MAX(FECHA) AS hasta
--   FROM BIGDATA.DEV.TARIFA_POR_MILLA_BARRIO;
--
-- Qué debe cuadrar (sin reprocesar): FILAS de gold en el registro = filas de la tabla de
-- Snowflake = filas de dev_gold_tarifa_por_milla_barrio en Athena (C2). Y SUM(VIAJES) en
-- Snowflake = viajes_en_gold (C1) = filas de silver de viajes (B1). Con silver sin deduplicar y
-- un reproceso, la última igualdad se rompe por el factor ×8: así se descubre.
--
-- Para prod, la misma conciliación con CONTROL_PROD y BIGDATA.PROD (con el rol BIGDATA_DEV solo
-- se puede LEER, no escribir: pruébalo) y con las tablas prod_* de Athena.
