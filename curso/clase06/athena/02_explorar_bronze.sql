-- =====================================================================
-- CLASE 6 · Athena sobre el lake · 02 · Explorar bronze (demo del instructor)
-- =====================================================================
--
-- QUÉ DATOS LEE ESTE ARCHIVO
--   Athena lee el bronze del año completo (239 470 448 viajes) que `make muestra` dejó en TU
--   bucket de S3 (bigdata-lake-<CUENTA>-us-east-2/bronze/) en la clase 4. No lee lo que
--   escriben tus funciones de ingesta: esas escriben en el disco del Code Editor
--   (~/datos_clase05/bronze_alumno, con solo 1 000 viajes), adonde Athena no llega. Los
--   archivos son los mismos originales de la TLC que trae tu ingesta; aquí se miran completos.
--   En la clase 7 tus funciones correrán en Glue y escribirán tu propio bronze en S3.
--
-- PROBLEMA
--   La ingesta de la clase 5 copia los archivos de la fuente tal cual llegaron. "Tal cual" no
--   significa "bueno": antes de construir silver hay que saber qué trae bronze y qué hay que limpiar.
--   Esta demo hace seis preguntas a los datos, en orden, y al final choca contra el límite de
--   1 GB del workgroup para ver por qué conviene filtrar por mes.
--
-- ANTES DE EMPEZAR
--   Ejecuta 01_tablas.sql (con <CUENTA> reemplazado). En el editor de Athena:
--   workgroup bigdata-wg, data source AwsDataCatalog, database bigdata_lake, región us-east-2.
--   Una sentencia por vez. Después de cada una, lee en la barra de resultados "Data scanned" y
--   "Run time": son lo que se compara a lo largo de la demo.
--
-- IDEA CENTRAL
--   Athena cobra y limita por BYTES LEÍDOS, no por filas devueltas. Parquet guarda los datos por
--   columnas: una consulta que usa 3 columnas lee 3 columnas, no las 24. Y la carpeta mes=AAAA-MM
--   permite no abrir los otros meses. Las dos palancas para gastar menos: pedir pocas columnas y
--   filtrar por mes.
--
-- CIFRAS
--   Los comentarios "Se midió" son de la cuenta de pruebas (ver validacion/contenido/
--   clase06_medidas.md). Tu Data scanned debe dar igual: son los mismos archivos del TLC.
--   El tiempo varía de una corrida a otra.
-- =====================================================================


-- ---------------------------------------------------------------------
-- PASO 1 · ¿Cuántas filas trajo la ingesta, mes por mes?
-- ---------------------------------------------------------------------
-- Es la primera pregunta de cualquier ingesta: ¿llegó todo? Sin filtro de mes, Athena abre los
-- 12 archivos, pero un conteo no necesita leer columnas: Parquet guarda el número de filas en el
-- pie del archivo y Athena lo usa. Por eso Data scanned da 0 bytes aunque son ~239 millones de filas.
-- Se midió: 12 meses, de 19 128 392 (agosto) a 21 280 788 (marzo) filas; 0 bytes.
SELECT mes, count(*) AS viajes
FROM bigdata_lake.bronze_fhvhv
GROUP BY mes
ORDER BY mes;


-- ---------------------------------------------------------------------
-- PASO 2 · Poda de particiones: lo mismo con y sin filtro de mes
-- ---------------------------------------------------------------------
-- Esta consulta sí lee una columna (pickup_datetime). 2A solo abre mes=2024-01; 2B abre los 12.
-- La poda ocurre porque mes es la columna de partición: Athena calcula la ruta
-- .../mes=2024-01/ y no toca las otras once carpetas.
-- Se midió: 2A 56 002 135 bytes (53 MB, un mes), 2B 671 711 446 bytes (641 MB, el año): 12 veces
-- más bytes para la misma pregunta.

-- 2A. Con filtro de mes.
SELECT mes, min(pickup_datetime) AS primer_viaje, max(pickup_datetime) AS ultimo_viaje
FROM bigdata_lake.bronze_fhvhv
WHERE mes = '2024-01'
GROUP BY mes;

-- 2B. Sin filtro de mes.
SELECT mes, min(pickup_datetime) AS primer_viaje, max(pickup_datetime) AS ultimo_viaje
FROM bigdata_lake.bronze_fhvhv
GROUP BY mes
ORDER BY mes;

-- 2C. Qué archivo leyó 2A. "$path" es una columna oculta con la ruta del archivo de cada fila.
-- Debe aparecer un solo archivo: .../mes=2024-01/fhvhv_tripdata_2024-01.parquet
SELECT "$path" AS archivo, count(*) AS filas
FROM bigdata_lake.bronze_fhvhv
WHERE mes = '2024-01'
GROUP BY "$path";


-- ---------------------------------------------------------------------
-- PASO 3 · Nulos en las columnas clave
-- ---------------------------------------------------------------------
-- Un nulo en una columna que silver necesita (cuándo, dónde, cuánto) obliga a decidir: ¿se
-- descarta la fila o se rellena? Aquí solo se mide. count_if cuenta las filas que cumplen la
-- condición. Las dos últimas columnas no son clave: se miran porque salen distintas.
-- Se midió (2024-01, 19 663 930 filas): 0 nulos en licencia, pickup, dropoff, zonas, millas,
-- duración, tarifa y pago. originating_base_num y on_scene_datetime sí tienen 5 218 737 nulos
-- (26.5 %): casi todos son de Lyft (HV0005: 5 218 737 de sus 5 231 175 viajes) y ninguno de Uber
-- (HV0003). No es un error de la ingesta: es una propiedad de la fuente, y por eso silver no usa
-- esas dos columnas.
-- Data scanned 345 333 249 bytes (329 MB).
SELECT
  count(*)                                       AS filas,
  count_if(hvfhs_license_num IS NULL)            AS n_licencia,
  count_if(pickup_datetime IS NULL)              AS n_pickup,
  count_if(dropoff_datetime IS NULL)             AS n_dropoff,
  count_if(pulocationid IS NULL)                 AS n_zona_recogida,
  count_if(dolocationid IS NULL)                 AS n_zona_destino,
  count_if(trip_miles IS NULL)                   AS n_millas,
  count_if(trip_time IS NULL)                    AS n_duracion,
  count_if(base_passenger_fare IS NULL)          AS n_tarifa,
  count_if(driver_pay IS NULL)                   AS n_pago_conductor,
  count_if(originating_base_num IS NULL)         AS n_base_origen,
  count_if(on_scene_datetime IS NULL)            AS n_llegada_al_sitio
FROM bigdata_lake.bronze_fhvhv
WHERE mes = '2024-01';


-- ---------------------------------------------------------------------
-- PASO 4 · Viajes imposibles
-- ---------------------------------------------------------------------
-- Valores que no pueden ser reales: 0 millas o negativas, viajes de más de 100 millas, de menos
-- de un minuto o de más de 3 horas, tarifas de 0 o negativas, un destino anterior al origen.
-- trip_time viene en SEGUNDOS y trip_miles en MILLAS. Los umbrales son los de silver
-- (src/pipeline/silver.py: 0 < millas < 100, 1 a 180 minutos, tarifa > 0).
-- La última columna cuenta las filas que incumplen AL MENOS UNA regla: no es la suma de las
-- anteriores porque una fila puede incumplir varias.
-- Se midió (2024-01): 3 286 con millas <= 0; 1 660 con 100 millas o más; 1 640 de menos de 1 minuto;
-- 791 de más de 3 h; 191 con tarifa negativa y 7 143 con tarifa 0; 2 con destino anterior al origen;
-- 137 con pago al conductor negativo. En total 13 907 filas (0.07 %) que silver descartará.
-- Data scanned 249 460 975 bytes (238 MB).
SELECT
  count(*)                                                     AS filas,
  count_if(trip_miles <= 0)                                    AS millas_cero_o_negativas,
  count_if(trip_miles >= 100)                                  AS millas_100_o_mas,
  count_if(trip_time < 60)                                     AS menos_de_1_min,
  count_if(trip_time > 180 * 60)                               AS mas_de_3_horas,
  count_if(base_passenger_fare < 0)                            AS tarifa_negativa,
  count_if(base_passenger_fare = 0)                            AS tarifa_cero,
  count_if(dropoff_datetime <= pickup_datetime)                AS destino_antes_del_origen,
  count_if(driver_pay < 0)                                     AS pago_negativo,
  count_if(trip_miles <= 0 OR trip_miles >= 100
           OR trip_time < 60 OR trip_time > 180 * 60
           OR base_passenger_fare <= 0)                        AS incumple_alguna_regla_de_silver
FROM bigdata_lake.bronze_fhvhv
WHERE mes = '2024-01';

-- 4B. Los extremos, para ver que no son redondeos. Se midió: el viaje más largo tiene 417.62
-- millas y 14.5 horas es la mayor duración, la tarifa más baja es -43.09 y el pago más bajo
-- al conductor es -67.76. Data scanned 136 392 266 bytes (130 MB).
SELECT
  max(trip_miles)               AS max_millas,
  max(trip_time) / 3600.0       AS max_horas,
  min(base_passenger_fare)      AS min_tarifa,
  min(driver_pay)               AS min_pago_conductor
FROM bigdata_lake.bronze_fhvhv
WHERE mes = '2024-01';


-- ---------------------------------------------------------------------
-- PASO 5 · Duplicados
-- ---------------------------------------------------------------------
-- Un reintento o una reingesta mal hecha puede dejar la misma fila dos veces. Dos preguntas:
-- 5A, ¿hay filas idénticas en las 24 columnas (duplicado exacto)? 5B, ¿hay viajes con la misma
-- empresa, hora de recogida y de bajada y zonas (la "huella de negocio")? Si 5A da 0 y 5B no,
-- los repetidos difieren en algo (precio, base) y son viajes distintos que coinciden por azar.
-- Esta es la razón por la que silver deduplica por huella de toda la fila (_hash_fila) y no por
-- una huella parcial: con la parcial se perderían viajes reales.
--
-- 5A. Duplicado exacto, las 24 columnas. COALESCE(..., 0) porque la suma sin grupos da NULL.
-- Se midió (2024-01): 0 grupos, 0 filas sobrantes. Data scanned 472 684 581 bytes (451 MB, las 24 columnas).
SELECT
  count(*)                       AS grupos_repetidos,
  COALESCE(sum(c - 1), 0)        AS filas_sobrantes
FROM (
  SELECT count(*) AS c
  FROM bigdata_lake.bronze_fhvhv
  WHERE mes = '2024-01'
  GROUP BY hvfhs_license_num, dispatching_base_num, originating_base_num, request_datetime,
           on_scene_datetime, pickup_datetime, dropoff_datetime, pulocationid, dolocationid,
           trip_miles, trip_time, base_passenger_fare, tolls, bcf, sales_tax,
           congestion_surcharge, airport_fee, tips, driver_pay, shared_request_flag,
           shared_match_flag, access_a_ride_flag, wav_request_flag, wav_match_flag
  HAVING count(*) > 1
);

-- 5B. Huella de negocio: empresa, recogida, bajada y zonas. Data scanned 158 393 434 bytes (151 MB).
-- Se midió (2024-01): 38 grupos de 2 filas, 38 filas sobrantes, ninguna es duplicado exacto.
SELECT
  count(*)                       AS grupos_repetidos,
  COALESCE(sum(c - 1), 0)        AS filas_sobrantes,
  max(c)                         AS max_repeticiones
FROM (
  SELECT count(*) AS c
  FROM bigdata_lake.bronze_fhvhv
  WHERE mes = '2024-01'
  GROUP BY hvfhs_license_num, pickup_datetime, dropoff_datetime, pulocationid, dolocationid
  HAVING count(*) > 1
);


-- ---------------------------------------------------------------------
-- PASO 6 · Fechas fuera del mes del archivo
-- ---------------------------------------------------------------------
-- El archivo de enero debería traer viajes de enero. Si trae otros, o el archivo se mezcló, o la
-- fuente tiene filas mal fechadas, y silver las descartaría por el filtro del mes. Se compara
-- cada fecha contra el rango [1 de enero, 1 de febrero).
-- 6A. Enero. Se midió: 0 recogidas fuera de enero (primer viaje 2024-01-01 00:00:00, último
-- 2024-01-31 23:59:59). Las otras dos columnas muestran que "fuera del mes" no siempre es un error:
-- 6 584 viajes terminan en febrero (empezaron antes de la medianoche del 31) y 858 se pidieron
-- en diciembre (pedido el 31 de diciembre, recogida el 1 de enero). Por eso silver filtra por la
-- fecha de RECOGIDA y no por la de bajada. Data scanned 169 202 942 bytes (161 MB).
SELECT
  count_if(pickup_datetime < TIMESTAMP '2024-01-01 00:00:00'
        OR pickup_datetime >= TIMESTAMP '2024-02-01 00:00:00')  AS recogida_fuera_de_enero,
  count_if(dropoff_datetime >= TIMESTAMP '2024-02-01 00:00:00') AS bajada_en_febrero,
  count_if(request_datetime <  TIMESTAMP '2024-01-01 00:00:00') AS pedido_en_diciembre,
  max(dropoff_datetime)                                         AS ultima_bajada
FROM bigdata_lake.bronze_fhvhv
WHERE mes = '2024-01';

-- 6B. Los 12 archivos a la vez: ¿algún mes trae recogidas de otro mes? Compara el mes de la
-- carpeta (mes) con el mes de la fecha. Una sola columna, así que entra bajo 1 GB.
-- Se midió: 0 filas, ningún archivo trae recogidas ajenas. Data scanned 671 711 446 bytes (641 MB).
SELECT mes, count(*) AS recogidas_de_otro_mes
FROM bigdata_lake.bronze_fhvhv
WHERE date_format(pickup_datetime, '%Y-%m') <> mes
GROUP BY mes
ORDER BY mes;


-- ---------------------------------------------------------------------
-- PASO 7 · El clima: el JSON se "despliega"
-- ---------------------------------------------------------------------
-- El archivo de clima trae tres listas paralelas (fechas, lluvia, temperatura). UNNEST las
-- convierte en una fila por día. Se espera una fila por día del año: 366.
-- Se midió: 366 días en el año (2024 es bisiesto), del 2024-01-01 al 2024-12-31, sin nulos en
-- lluvia ni temperatura. Data scanned 12 433 bytes (12 KB): doce archivos de ~1 KB.
SELECT
  count(*)                              AS dias,
  count_if(d.lluvia IS NULL)            AS n_lluvia,
  count_if(d.temp IS NULL)              AS n_temperatura,
  min(d.fecha)                          AS primer_dia,
  max(d.fecha)                          AS ultimo_dia
FROM bigdata_lake.bronze_clima
CROSS JOIN UNNEST(daily.time, daily.precipitation_sum, daily.temperature_2m_mean)
           AS d(fecha, lluvia, temp);


-- ---------------------------------------------------------------------
-- PASO 8 · Chocar con el límite de 1 GB
-- ---------------------------------------------------------------------
-- El workgroup bigdata-wg cancela cualquier consulta que lea más de 1 GB (1 073 741 824 bytes).
-- 8A lee 7 columnas de UN mes. 8B es la MISMA consulta sin filtro de mes: Athena intenta abrir
-- los 12 archivos, pasa de 1 GB y se cancela. El límite protege tu cuenta de una consulta
-- descuidada: a US$5 por TB, 1 GB cuesta medio centavo de dólar, no es un problema de dinero
-- sino de hábito.
--
-- 8A. Con mes. Se midió: 147 803 040 bytes (141 MB), 2 filas (HV0003 Uber y HV0005 Lyft; Juno y Via ya no operan).
SELECT hvfhs_license_num, count(*) AS viajes,
       round(sum(driver_pay), 0)             AS pago_total,
       round(sum(tips), 0)                   AS propinas,
       round(sum(base_passenger_fare), 0)    AS tarifa_total,
       round(avg(trip_miles), 2)             AS millas_prom,
       round(avg(trip_time) / 60.0, 1)       AS min_prom
FROM bigdata_lake.bronze_fhvhv
WHERE mes = '2024-01'
GROUP BY hvfhs_license_num
ORDER BY viajes DESC;

-- 8B. Sin mes. ERROR ESPERADO: la consulta queda en estado CANCELLED con el mensaje
--   "Bytes scanned limit was exceeded"
-- y Data scanned queda en 1 073 741 824 bytes (1 GB): lo que alcanzó a leer antes de cortarse.
-- No devuelve filas. Arreglo: agregar WHERE mes = '2024-01' (o un rango de meses).
SELECT hvfhs_license_num, count(*) AS viajes,
       round(sum(driver_pay), 0)             AS pago_total,
       round(sum(tips), 0)                   AS propinas,
       round(sum(base_passenger_fare), 0)    AS tarifa_total,
       round(avg(trip_miles), 2)             AS millas_prom,
       round(avg(trip_time) / 60.0, 1)       AS min_prom
FROM bigdata_lake.bronze_fhvhv
GROUP BY hvfhs_license_num
ORDER BY viajes DESC;


-- ---------------------------------------------------------------------
-- PASO 9 · Puente al lab: lo que silver debe reproducir
-- ---------------------------------------------------------------------
-- Si ya construiste silver en dev, esta consulta cierra el círculo: enero tiene 19 663 930 filas
-- en bronze, 13 907 incumplen las reglas del paso 4 y silver conserva 19 650 023. Restando:
-- 19 663 930 - 13 907 = 19 650 023. Lo que viste con SQL es exactamente lo que el lab hace con
-- Spark. Si esa cuenta no te cuadra, algo del lab está mal.
-- (Requiere dev/silver/fhvhv_trips/ en tu bucket. Data scanned: 0 bytes.)
SELECT count(*) AS filas_silver_enero
FROM bigdata_lake.silver_fhvhv_trips
WHERE pickup_date BETWEEN '2024-01-01' AND '2024-01-31';
