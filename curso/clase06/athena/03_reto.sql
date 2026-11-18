-- =====================================================================
-- CLASE 6 · Athena sobre el lake · 03 · Reto del estudiante
-- =====================================================================
--
-- PROBLEMA
--   En la demo miraste enero. Ahora el mes es MARZO (2024-03), el más grande del año: 21 280 788
--   viajes. Responde cinco preguntas sobre bronze con las mismas tablas de 01_tablas.sql
--   (workgroup bigdata-wg, database bigdata_lake). Mantén cada consulta con WHERE mes = '2024-03':
--   las tablas son las mismas y el límite de 1 GB también.
--
-- CÓMO TRABAJAR
--   Cada ejercicio trae el esqueleto y un hueco marcado `-- TU CÓDIGO AQUÍ`. Completa la consulta,
--   ejecútala y compara con "RESULTADO ESPERADO". Si tu resultado no coincide, antes de pedir
--   ayuda revisa tres cosas: el filtro de mes, las unidades (trip_time en SEGUNDOS, trip_miles en
--   MILLAS) y los operadores (<= frente a <).
--   Data scanned: los bytes esperados valen para la tabla tal como la declara 01_tablas.sql;
--   tu valor debe ser igual o muy cercano.
--   Pistas: count_if(condición) cuenta filas que cumplen la condición; CASE WHEN ... END traduce
--   códigos a nombres; la zona se une por pulocationid (número) con locationid (texto en la
--   tabla de zonas), así que hay que convertir uno de los dos con CAST.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Ejercicio 1 · ¿Qué empresa hizo cuántos viajes en marzo?
-- ---------------------------------------------------------------------
-- La licencia HV0003 es Uber y HV0005 es Lyft. Muestra la licencia, el nombre de la empresa, los
-- viajes y el porcentaje que representa cada una del total del mes (un decimal), de mayor a menor.
-- Pista: el total del mes dentro de la misma consulta se obtiene con sum(count(*)) OVER ().
--
-- RESULTADO ESPERADO (2 filas):
--   licencia | empresa | viajes   | porcentaje
--   HV0003   | Uber    | 15621998 | 73.4
--   HV0005   | Lyft    |  5658790 | 26.6
--   Data scanned: 2 599 945 bytes (2.5 MB).
SELECT
  hvfhs_license_num AS licencia
  -- TU CÓDIGO AQUÍ: el nombre de la empresa, los viajes y el porcentaje
FROM bigdata_lake.bronze_fhvhv
WHERE mes = '2024-03'
-- TU CÓDIGO AQUÍ: agrupar y ordenar
;


-- ---------------------------------------------------------------------
-- Ejercicio 2 · ¿Cuántos viajes imposibles trae marzo?
-- ---------------------------------------------------------------------
-- Una fila con el total de filas y una columna por familia de regla:
--   millas_imposibles   -> millas <= 0 o >= 100
--   duracion_imposible  -> duración de menos de 1 minuto o de más de 180 minutos
--   tarifa_imposible    -> tarifa base <= 0
--   total_imposibles    -> las filas que incumplen AL MENOS UNA de las tres
--   porcentaje          -> total_imposibles sobre el total de filas, con 3 decimales
-- Una fila puede incumplir varias reglas a la vez: total_imposibles NO es la suma de las tres.
--
-- RESULTADO ESPERADO (1 fila):
--   filas    | millas_imposibles | duracion_imposible | tarifa_imposible | total_imposibles | porcentaje
--   21280788 | 4358              | 2098               | 1183             | 7069             | 0.033
--   Data scanned: 112 124 969 bytes (107 MB).
SELECT
  count(*) AS filas
  -- TU CÓDIGO AQUÍ: las otras cinco columnas
FROM bigdata_lake.bronze_fhvhv
WHERE mes = '2024-03';


-- ---------------------------------------------------------------------
-- Ejercicio 3 · ¿Hay duplicados por huella de negocio?
-- ---------------------------------------------------------------------
-- La huella es: empresa (hvfhs_license_num), pickup_datetime, dropoff_datetime, pulocationid y
-- dolocationid. Cuenta cuántos grupos de esa huella aparecen más de una vez y cuántas filas
-- sobran (filas del grupo menos una). Si no hay grupos, la suma da NULL: usa COALESCE para
-- mostrar 0.
--
-- RESULTADO ESPERADO (1 fila):
--   grupos_repetidos | filas_sobrantes
--   33               | 33
--   Data scanned: 167 847 657 bytes (160 MB).
SELECT
  count(*) AS grupos_repetidos
  -- TU CÓDIGO AQUÍ: filas_sobrantes
FROM (
  -- TU CÓDIGO AQUÍ: la subconsulta que agrupa por la huella y deja los grupos con más de una fila
);


-- ---------------------------------------------------------------------
-- Ejercicio 4 · Las cinco zonas con más recogidas, con su nombre
-- ---------------------------------------------------------------------
-- En bronze_fhvhv las zonas son números (pulocationid). El nombre está en bronze_taxi_zones.
-- Une las dos tablas y muestra zona, barrio y viajes, las cinco primeras.
--
-- RESULTADO ESPERADO (5 filas):
--   zona                       | barrio    | viajes
--   LaGuardia Airport          | Queens    | 388326
--   JFK Airport                | Queens    | 371026
--   East Village               | Manhattan | 297394
--   Crown Heights North        | Brooklyn  | 290327
--   Times Sq/Theatre District  | Manhattan | 259277
--   Data scanned: 23 254 176 bytes (22 MB).
SELECT
  z.zone AS zona
  -- TU CÓDIGO AQUÍ: barrio y viajes
FROM bigdata_lake.bronze_fhvhv v
-- TU CÓDIGO AQUÍ: la unión con bronze_taxi_zones (recuerda el CAST)
WHERE v.mes = '2024-03'
-- TU CÓDIGO AQUÍ: agrupar, ordenar y limitar a 5
;


-- ---------------------------------------------------------------------
-- Ejercicio 5 · Marzo frente al año: el costo de no filtrar
-- ---------------------------------------------------------------------
-- La misma pregunta (las cinco zonas de recogida con más viajes, solo por número de zona) dos
-- veces: 5A con filtro de marzo y 5B sin filtro. Ejecuta las dos y anota el Data scanned de cada
-- una. Después responde en una línea: ¿cuántas veces más bytes lee 5B y por qué sigue por debajo
-- de 1 GB?
--
-- RESULTADO ESPERADO:
--   5A: 5 filas (138, 132, 79, 61, 230 con 388326, 371026, 297394, 290327, 259277 viajes).
--       Data scanned: 23 241 845 bytes (22 MB).
--   5B: 5 filas (138, 132, 79, 61, 230 con 4738335, 4331163, 3172444, 3136821, 2940406 viajes).
--       Data scanned: 261 409 931 bytes (249 MB), unas 11 veces más.
--   Respuesta: 5B abre los 12 archivos en vez de uno; pasa de 22 MB a 249 MB. No llega a 1 GB
--   porque lee UNA sola columna de 24: en Parquet, pedir pocas columnas también ahorra bytes.

-- 5A. Con filtro de mes.
SELECT pulocationid, count(*) AS viajes
FROM bigdata_lake.bronze_fhvhv
-- TU CÓDIGO AQUÍ: el filtro de marzo
GROUP BY pulocationid
ORDER BY viajes DESC
LIMIT 5;

-- 5B. Sin filtro de mes.
SELECT pulocationid, count(*) AS viajes
FROM bigdata_lake.bronze_fhvhv
-- TU CÓDIGO AQUÍ: ¿qué debe cambiar respecto de 5A?
GROUP BY pulocationid
ORDER BY viajes DESC
LIMIT 5;


-- ---------------------------------------------------------------------
-- Para pensar (sin código)
-- ---------------------------------------------------------------------
-- Marzo trae 7 069 filas imposibles (0.033 %) y 33 posibles duplicados por huella de negocio, de
-- 21 millones de filas. ¿Son suficientes para que silver las descarte? ¿Y para que la ingesta
-- se considere fallida? Escribe tu respuesta y el porcentaje que la sostiene. El lab de silver y
-- gold aplica estas mismas reglas.
