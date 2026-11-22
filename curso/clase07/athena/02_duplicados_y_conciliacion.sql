-- =====================================================================
-- CLASE 7 · Athena sobre el lake · 02 · Duplicados y conciliación (demo del instructor)
-- =====================================================================
--
-- PROBLEMA
--   El pipeline corrió, todas las tareas salieron en verde y nadie recibió un error. ¿Cómo sé que
--   las cifras son las correctas? Hoy lo comprobamos de la forma más dura: reprocesamos enero a
--   propósito (reprocesar=true) con silver SIN deduplicar, y buscamos con SQL lo que el pipeline
--   no avisó: silver y gold quedan inflados.
--
-- QUÉ PASA, EN PALABRAS
--   Bronze solo agrega: cada ingesta es un lote nuevo (lote=<id>/) y nunca borra los anteriores.
--   Silver lee TODOS los lotes del mes. Si enero entró dos veces, cada fila de silver aparece
--   dos veces. Gold une viajes, zonas y clima (enriquecer); si cada una de las tres tablas de
--   silver está duplicada, cada viaje se repite una vez por cada copia de zonas y de clima:
--
--     después de la 1.ª corrida   1 lote   silver ×1   gold ×1
--     después de la 2.ª corrida   2 lotes  silver ×2   gold ×2 · ×2 · ×2 = ×8
--     después de la 3.ª corrida   3 lotes  silver ×3   gold ×3 · ×3 · ×3 = ×27
--
--   El factor de gold es el cubo del número de lotes porque enriquecer hace dos uniones (zonas y
--   clima) sobre tablas que también se repiten. Los factores ×2, ×8 y ×27 se midieron en la
--   cuenta de pruebas (ver validacion/contenido/clase07_medidas.md).
--
-- ANTES DE EMPEZAR
--   1. Ejecuta 01_tablas.sql con <CUENTA> y <ENTORNO>=dev ya reemplazados. En el editor de Athena:
--      workgroup bigdata-wg, data source AwsDataCatalog, database bigdata_lake, región us-east-2.
--   2. Una sentencia por vez. Después de cada una, lee en la barra de resultados "Data scanned"
--      y "Run time".
--   3. Este archivo lee las tablas de DEV (dev_silver_..., dev_gold_...). Para validar prod más
--      adelante, cambia dev_ por prod_ en cada consulta (Ctrl+F / Cmd+F > Reemplazar todo).
--   4. Todas las consultas filtran por mes = '2024-01': Athena solo abre esa carpeta.
--
-- CÓMO LEER LAS CIFRAS
--   Con limite=1000 cada fuente se lee recortada a 1 000 filas (las mismas siempre), así que
--   silver de viajes queda por debajo de 1 000 (los filtros descartan algunos). Los números
--   exactos de tu cuenta se anotan en el ensayo (curso/clase07/prueba_ensayo.md). Lo que debes
--   ver SIEMPRE es la RELACIÓN entre las cifras: ×1, ×2, ×8, ×27.
-- =====================================================================


-- ---------------------------------------------------------------------
-- PASO 1 · ¿Cuántas filas tiene cada tabla de silver?
-- ---------------------------------------------------------------------
-- La primera pregunta de cualquier conciliación: ¿cuántas filas hay? Un conteo no necesita leer
-- columnas (Parquet guarda el número de filas en el pie del archivo): Data scanned es casi 0.
-- Apunta las tres cifras después de CADA corrida: son la línea que crece.
-- Después de la 1.ª corrida: silver de viajes (menos de 1 000), clima (31 días) y zonas (265).
-- Después de reprocesar una vez: viajes ×2, clima ×2 (62) y zonas ×2 (530).
SELECT 'fhvhv'      AS tabla, count(*) AS filas FROM bigdata_lake.dev_silver_fhvhv      WHERE mes = '2024-01'
UNION ALL
SELECT 'clima'      AS tabla, count(*) AS filas FROM bigdata_lake.dev_silver_clima      WHERE mes = '2024-01'
UNION ALL
SELECT 'taxi_zones' AS tabla, count(*) AS filas FROM bigdata_lake.dev_silver_taxi_zones;


-- ---------------------------------------------------------------------
-- PASO 2 · ¿Cuántos viajes suma gold, frente a las filas de silver?
-- ---------------------------------------------------------------------
-- Gold agrega: no tiene una fila por viaje, sino una por (fecha, barrio, franja). Lo que se
-- compara no son las filas de gold sino la SUMA de su columna viajes. Si el pipeline está sano,
-- esa suma es igual a las filas de silver de viajes (la relación es 1).
-- Después de la 1.ª corrida: relacion = 1.
-- Después de reprocesar una vez: relacion = 8. Después de la 3.ª corrida: relacion = 27.
-- Nadie avisó: las tareas terminaron en verde.
SELECT
  (SELECT sum(viajes) FROM bigdata_lake.dev_gold_tarifa_por_milla_barrio WHERE mes = '2024-01') AS viajes_en_gold,
  (SELECT count(*)    FROM bigdata_lake.dev_silver_fhvhv                 WHERE mes = '2024-01') AS filas_en_silver,
  CAST((SELECT sum(viajes) FROM bigdata_lake.dev_gold_tarifa_por_milla_barrio WHERE mes = '2024-01') AS double)
    / (SELECT count(*) FROM bigdata_lake.dev_silver_fhvhv WHERE mes = '2024-01') AS relacion;


-- ---------------------------------------------------------------------
-- PASO 3 · Buscar los duplicados sin saber de antemano que están
-- ---------------------------------------------------------------------
-- Si no tuviéramos las cifras de la 1.ª corrida, ¿cómo detectaríamos el problema? Buscando filas
-- que se repiten. Un viaje se describe por quién lo hizo, cuándo, de dónde a dónde, cuánto
-- recorrió y cuánto cobró. Si dos filas coinciden en TODO eso, casi seguro es el mismo viaje.

-- 3A. Filas frente a viajes distintos, por esas columnas. Si coinciden, no hay duplicados.
--     Con un lote, filas = distintas (o casi: dos viajes reales pueden coincidir en todo).
--     Con dos lotes, filas es el DOBLE de distintas.
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

-- 3B. Las filas repetidas, con cuántas veces aparecen. Tras reprocesar una vez, casi todas
--     aparecen 2 veces; tras la tercera corrida, 3.
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

-- 3C. Con la huella de la fila, la comprobación es una línea. Mientras bronze no agregue los
--     metadatos (problema a propósito), "_hash_fila" es NULL en todas las filas: huellas = 0.
--     Cuando tu equipo escriba agregar_metadatos y se reprocese bronze, la huella aparece: filas
--     frente a huellas distintas dice cuántas copias sobran, sin elegir columnas a mano.
SELECT
  count(*)                     AS filas,
  count("_hash_fila")          AS filas_con_huella,
  count(DISTINCT "_hash_fila") AS huellas_distintas
FROM bigdata_lake.dev_silver_fhvhv
WHERE mes = '2024-01';

-- 3D. Los lotes de bronze no se ven en Athena (las tablas de bronze leen _crudo, los archivos
--     originales), sino en S3. Desde la terminal, una carpeta lote=... por cada corrida de bronze:
--   cd ~/bigdata
--   aws s3 ls s3://bigdata-lake-<CUENTA>-us-east-2/dev/bronze/fhvhv/mes=2024-01/
-- Con una sola corrida hay una carpeta; tras reprocesar, dos; tras la tercera, tres. Silver lee
-- todas y las junta: ahí nace el duplicado.


-- ---------------------------------------------------------------------
-- PASO 4 · ¿Y el clima y las zonas? Ahí nace el ×8
-- ---------------------------------------------------------------------
-- El factor de gold sale de multiplicar tres copias. Se ve contando las filas repetidas de las
-- tablas pequeñas: si el clima de enero (31 días) tiene 62 filas, cada día aparece dos veces, y
-- cada viaje de ese día se une dos veces.
-- 4A. Días de clima, filas y días distintos.
SELECT count(*) AS filas, count(DISTINCT fecha) AS dias_distintos
FROM bigdata_lake.dev_silver_clima
WHERE mes = '2024-01';

-- 4B. Zonas, filas e identificadores distintos (deben ser 265 y 265 con un lote).
SELECT count(*) AS filas, count(DISTINCT locationid) AS zonas_distintas
FROM bigdata_lake.dev_silver_taxi_zones;


-- ---------------------------------------------------------------------
-- PASO 5 · Después de que tu equipo escriba deduplicar
-- ---------------------------------------------------------------------
-- Repite los pasos 1 y 2 después de: (a) escribir agregar_metadatos (bronze), (b) escribir
-- deduplicar (silver), (c) correr resetear_entorno en dev y (d) repetir el pipeline dos veces con
-- reprocesar=true. Silver debe quedar igual con 1, 2 o 3 lotes, y la relación del paso 2 debe
-- ser SIEMPRE 1. Ese es el criterio de que silver es idempotente: pase lo que pase en bronze,
-- silver es el reflejo de la fuente, sin duplicados.


-- ---------------------------------------------------------------------
-- PASO 6 · Conciliación con la tabla de control y con Snowflake
-- ---------------------------------------------------------------------
-- Esta parte NO es de Athena: va en Snowsight (una hoja de SQL). Pega los bloques de uno en uno.
-- Las tres primeras líneas eligen rol, warehouse y base de datos. Siempre se dicen: con
-- ACCOUNTADMIN no puedes crear ni alterar en BIGDATA.DEV.
--
--   USE ROLE BIGDATA_DEV;
--   USE WAREHOUSE BIGDATA_WH;
--   USE DATABASE BIGDATA;
--
-- 6A. Todo lo que anotó el pipeline en dev, en orden. Cada paso que termina bien deja una fila:
--     FILAS = filas ESCRITAS; LEIDAS = filas leídas (solo informativa).
--   SELECT TABLA, CAPA, MES, FILAS, LEIDAS, COMPUTO, LIMITE, REPROCESAR, INICIO
--   FROM BIGDATA.CONTROL_DEV.WATERMARK
--   ORDER BY INICIO;
--
-- 6B. La conciliación usa el ÚLTIMO registro por (tabla, capa, mes): reprocesar no borra la
--     historia, así que una misma clave puede tener varias filas.
--   SELECT TABLA, CAPA, MES, FILAS, LEIDAS, COMPUTO, INICIO
--   FROM BIGDATA.CONTROL_DEV.WATERMARK
--   QUALIFY ROW_NUMBER() OVER (PARTITION BY TABLA, CAPA, MES ORDER BY INICIO DESC) = 1
--   ORDER BY CAPA, TABLA, MES;
--
-- 6C. Gold en Snowflake frente a lo que registró el paso gold. FILAS son filas de gold (una por
--     fecha, barrio y franja); los viajes se comparan con SUM(VIAJES).
--   SELECT COUNT(*) AS filas, SUM(VIAJES) AS viajes, MIN(FECHA) AS desde, MAX(FECHA) AS hasta
--   FROM BIGDATA.DEV.TARIFA_POR_MILLA_BARRIO;
--
-- Qué debe cuadrar (sin reprocesar): FILAS de gold en el registro = filas de la tabla de
-- Snowflake = filas de dev_gold_tarifa_por_milla_barrio en Athena. Y SUM(VIAJES) en Snowflake =
-- viajes_en_gold del paso 2 = filas de silver de viajes. Con silver sin deduplicar y un
-- reproceso, la última igualdad se rompe por el factor ×8: así se descubre.
--
-- Para prod, la misma conciliación con CONTROL_PROD y BIGDATA.PROD (con el rol BIGDATA_DEV solo
-- se puede LEER, no escribir: pruébalo) y con las tablas prod_* de Athena.
