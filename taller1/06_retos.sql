-- =====================================================================
-- TALLER 1 · 06_retos.sql · Retos opcionales R2, R3 y R5
-- =====================================================================
-- Equipo: Andrea Páez Cardona (analista), Ana María Montealegre Ramírez
-- (modeladora), Manuela Restrepo Céspedes (ingeniería de datos),
-- Julian Olaya (calidad y costos) · Caso A · Competencia entre plataformas
--
-- QUÉ HACE
--   R2 (2 pts) · DIM_FECHA con festivos y fin de semana, usada en consultas.
--   R3 (3 pts) · Días de lluvia fuerte (más de 10 mm) frente a la línea base
--                del mismo día de la semana en la misma zona, con
--                AVG() OVER (PARTITION BY ZONA, DIA_SEMANA).
--   R5 (3 pts) · Rachas de alta demanda: días consecutivos por encima de un
--                umbral (el problema de «huecos e islas»).
--   R4 (3 pts) está en 05_calidad.sql. R1 y R6 no se hicieron.
--
-- CÓMO LEERLO
--   Cada consulta va seguida de su interpretación. Las tablas de resultados no
--   se copian al archivo: salen al correrlo con Run All.
--
-- REQUISITOS
--   Haber corrido 01_estrella.sql y 02_carga.sql. No depende de 03 ni de 05.
--
-- DECISIÓN COMÚN A R3 Y R5: LA SERIE DIARIA SE COMPLETA
--   El hecho no tiene fila para una zona el día en que esa zona no hizo
--   viajes. Una racha o un LAG leerían entonces la fila anterior disponible
--   y no el día anterior del calendario, que es la trampa que advierte el
--   enunciado. Por eso R3 y R5 se apoyan en la vista V_SERIE_ZONA_DIA, que
--   cruza las 91 fechas de DIM_FECHA con todas las zonas del hecho y pone
--   0 viajes donde no había fila.
-- =====================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE CURSO;
USE SCHEMA T1;


-- =====================================================================
-- 0. SERIE DIARIA COMPLETA POR ZONA (la usan R3 y R5)
-- =====================================================================

CREATE OR REPLACE VIEW CURSO.T1.V_SERIE_ZONA_DIA AS
WITH ZONAS AS (
    SELECT DISTINCT ZONA
    FROM CURSO.T1.FACT_VIAJES_DIA
),
REJILLA AS (
    SELECT
        D.FECHA,
        D.DIA_SEMANA,
        D.ES_FIN_SEMANA,
        D.ES_FESTIVO,
        D.LLUVIA_MM,
        Z.ZONA
    FROM CURSO.T1.DIM_FECHA AS D
    CROSS JOIN ZONAS AS Z
)
SELECT
    R.FECHA,
    R.ZONA,
    R.DIA_SEMANA,
    R.ES_FIN_SEMANA,
    R.ES_FESTIVO,
    R.LLUVIA_MM,
    COALESCE(R.LLUVIA_MM, 0) > 10            AS LLUVIA_FUERTE,
    COALESCE(SUM(F.VIAJES), 0)               AS VIAJES_DIA,
    COALESCE(SUM(F.INGRESO_TOTAL), 0)        AS INGRESO_DIA
FROM REJILLA AS R
LEFT JOIN CURSO.T1.FACT_VIAJES_DIA AS F
       ON F.FECHA = R.FECHA
      AND F.ZONA  = R.ZONA
GROUP BY
    R.FECHA, R.ZONA, R.DIA_SEMANA,
    R.ES_FIN_SEMANA, R.ES_FESTIVO, R.LLUVIA_MM;

-- Control de la rejilla: 91 días × zonas del hecho, y los mismos viajes que el
-- hecho (los ceros que se agregan no suman nada).
SELECT
    COUNT(*)                                                         AS FILAS,
    (SELECT 91 * COUNT(DISTINCT ZONA) FROM CURSO.T1.FACT_VIAJES_DIA) AS FILAS_ESPERADAS,
    SUM(VIAJES_DIA)                                                  AS VIAJES,
    60268466                                                         AS VIAJES_ESPERADOS,
    COUNT_IF(VIAJES_DIA = 0)                                         AS DIAS_ZONA_SIN_VIAJES
FROM CURSO.T1.V_SERIE_ZONA_DIA;

-- Interpretación: La rejilla queda con 23 751 filas (91 días × 261 zonas) y los
-- mismos 60 268 466 viajes del hecho. Los 331 pares (zona, día) con 0 viajes, el
-- 1,4 % de la rejilla, son los huecos que el hecho no trae: sin completarlos, una
-- racha de R5 habría saltado por encima de ellos y los habría contado como días
-- consecutivos. DIM_ZONA tiene 262 nombres y el hecho usa 261, así que una zona
-- del catálogo no registró ningún viaje en el trimestre; eso no es un huérfano,
-- porque el control U1 mira la dirección contraria.


-- =====================================================================
-- R2 · DIM_FECHA CON FESTIVOS Y FIN DE SEMANA, USADA EN UNA CONSULTA
-- =====================================================================
-- La dimensión se define en 01_estrella.sql (ES_FESTIVO, ES_FIN_SEMANA) y se
-- carga en 02_carga.sql: ES_FESTIVO sale de un LEFT JOIN contra
-- CURSO.LAB4.FESTIVOS_2024 y ES_FIN_SEMANA de DAYOFWEEKISO(FECHA) IN (6, 7).
-- De enero a marzo hay 3 festivos federales (1 y 15 de enero y 19 de febrero)
-- y los tres caen en lunes, así que la comparación justa no es contra
-- «un día cualquiera» sino contra los demás lunes.

-- ---------------------------------------------------------------------
-- R2a. Cada festivo frente al promedio de los días NO festivos del mismo
-- día de la semana.
-- ---------------------------------------------------------------------
-- Los días se cuentan uniendo el hecho con DIM_FECHA, nunca contando filas
-- del hecho (trampa 1). El filtro va en QUALIFY y no en WHERE a propósito:
-- WHERE se aplica ANTES de la ventana y dejaría la línea base calculada solo
-- con los festivos, es decir, comparando los festivos consigo mismos.
WITH DIA AS (
    SELECT
        D.FECHA,
        D.DIA_SEMANA,
        D.ES_FESTIVO,
        SUM(F.VIAJES)        AS VIAJES_DIA,
        SUM(F.INGRESO_TOTAL) AS INGRESO_DIA
    FROM CURSO.T1.FACT_VIAJES_DIA AS F
    JOIN CURSO.T1.DIM_FECHA AS D
      ON F.FECHA = D.FECHA
    GROUP BY D.FECHA, D.DIA_SEMANA, D.ES_FESTIVO
)
SELECT
    FECHA,
    DIA_SEMANA,
    VIAJES_DIA,
    ROUND(AVG(IFF(NOT ES_FESTIVO, VIAJES_DIA, NULL))
          OVER (PARTITION BY DIA_SEMANA))                        AS BASE_MISMO_DIA_SEMANA,
    ROUND(100 * (VIAJES_DIA
                 / NULLIF(AVG(IFF(NOT ES_FESTIVO, VIAJES_DIA, NULL))
                          OVER (PARTITION BY DIA_SEMANA), 0) - 1), 1) AS DIF_PCT
FROM DIA
QUALIFY ES_FESTIVO
ORDER BY FECHA;

-- Interpretación: «Festivo» no es una sola cosa. El 1 de enero hace 12,4 % más
-- viajes que un lunes normal, porque su madrugada es el final de la fiesta del 31
-- de diciembre. En cambio el Día de Martin Luther King y el de los Presidentes se
-- quedan 1,5 % y 2,7 % por debajo: son lunes corrientes en los que parte de la
-- ciudad no trabaja, y lo que se pierde en viajes de oficina se recupera en ocio.
--
-- La línea base por día de la semana no es un adorno. El lunes es el día más flojo
-- (567 813 viajes contra 662 290 del promedio diario del trimestre, un 14 % menos).
-- Comparar los tres festivos contra el promedio de todos los días habría dado
-- -3,7 %, -15,6 % y -16,6 %, y la conclusión falsa de que los festivos hunden la
-- demanda; lo que se estaría midiendo es que los tres cayeron en lunes.
--
-- Qué NO dice: son solo 3 festivos (n = 3) y los tres en invierno. Dos de ellos
-- caen en semanas atípicas por el Año Nuevo, así que la diferencia no se puede
-- atribuir solo a que sea festivo.

-- ---------------------------------------------------------------------
-- R2b. Entre semana contra fin de semana, por empresa.
-- ---------------------------------------------------------------------
-- Usa ES_FIN_SEMANA y cuenta los días con COUNT(DISTINCT FECHA): el hecho
-- tiene cientos de filas por día y COUNT(*) daría filas, no días (trampa 1).
-- Control: DIAS debe dar 65 entre semana y 26 en fin de semana (91 en total).
SELECT
    IFF(D.ES_FIN_SEMANA, 'Fin de semana', 'Entre semana')            AS TIPO_DIA,
    F.EMPRESA,
    COUNT(DISTINCT D.FECHA)                                          AS DIAS,
    SUM(F.VIAJES)                                                    AS VIAJES,
    ROUND(SUM(F.VIAJES) / COUNT(DISTINCT D.FECHA))                   AS VIAJES_POR_DIA,
    ROUND(SUM(F.INGRESO_TOTAL) / SUM(F.VIAJES), 2)                   AS INGRESO_POR_VIAJE,
    ROUND(SUM(F.PROPINA_TOTAL) / SUM(F.VIAJES), 2)                   AS PROPINA_PONDERADA
FROM CURSO.T1.FACT_VIAJES_DIA AS F
JOIN CURSO.T1.DIM_FECHA AS D
  ON F.FECHA = D.FECHA
GROUP BY TIPO_DIA, F.EMPRESA
ORDER BY TIPO_DIA, F.EMPRESA;

-- Interpretación: El fin de semana la ciudad hace 729 444 viajes por día contra
-- 635 430 entre semana, un 14,8 % más, y las dos empresas crecen casi igual: la
-- cuota de Lyft pasa de 26,2 % a 26,5 %. El reparto del mercado que encontramos en
-- A4 no depende del tipo de día; el fin de semana hay más torta, no una torta
-- repartida distinto. Lo que sí cambia es el precio: la ventaja que Uber tiene
-- entre semana (1,65 USD más por viaje) desaparece el fin de semana, con las dos
-- en 29,59 USD. La propina se mueve al revés, cae en las dos pero mucho más en
-- Uber (-15,3 %) que en Lyft (-6,6 %), así que la brecha entre ambas se duplica.
--
-- Control cruzado con A2: rehaciendo el promedio ponderado desde estas cuatro
-- filas sale 1,18 USD en Lyft y 1,06 en Uber, las mismas cifras de A2 calculadas
-- sobre otro corte. Es la ventaja de guardar PROPINA_TOTAL en el hecho y no el
-- promedio: el ponderado se rehace en cualquier nivel.
--
-- Qué NO dice: que los dos queden en 29,59 USD el fin de semana es una
-- coincidencia al centavo entre dos promedios ponderados, no una señal sobre cómo
-- fijan sus precios. Y el ingreso por viaje es lo que paga el pasajero, no la
-- ganancia de la empresa ni lo que recibe el conductor.


-- =====================================================================
-- R3 · LLUVIA FUERTE FRENTE A LA LÍNEA BASE DEL MISMO DÍA DE LA SEMANA
-- =====================================================================
-- «Lluvia fuerte» = más de 10 mm en el día, según LLUVIA_MM de DIM_FECHA,
-- que guarda la lluvia UNA sola vez por día (trampa 1: en el gold el mismo
-- valor se repite en las ~513 filas del día).
-- La línea base es el promedio de viajes de ESA zona en ESE día de la semana,
-- con AVG() OVER (PARTITION BY ZONA, DIA_SEMANA), para que no se compare un
-- sábado lluvioso contra un martes seco.

-- ---------------------------------------------------------------------
-- R3a. Qué días llovió fuerte y cuánta lluvia cayó.
-- ---------------------------------------------------------------------
SELECT
    FECHA,
    DIA_SEMANA,
    LLUVIA_MM,
    ES_FIN_SEMANA,
    ES_FESTIVO
FROM CURSO.T1.DIM_FECHA
WHERE LLUVIA_MM > 10
ORDER BY LLUVIA_MM DESC;

-- Interpretación: Son 13 días de los 91, repartidos en 5 de enero, 2 de febrero y
-- 6 de marzo, con un máximo de 63,6 mm el 23 de marzo. El 10 de enero aparece con
-- 21,7 mm, el mismo valor del ejemplo del enunciado (ese día el gold repite 21,7
-- en sus 514 filas y SUM(LLUVIA_MM) daría 11 153,8): es la comprobación de que
-- DIM_FECHA guardó la lluvia una sola vez por día y con el valor correcto, lo
-- mismo que verifica el control T1d de 05_calidad.
--
-- Ninguno de los 13 días es festivo, así que la lluvia no se confunde con el
-- efecto de los festivos. Pero 6 de los 13 caen en fin de semana, y ese desbalance
-- es justo la razón de comparar contra la línea base del mismo día de la semana.

-- ---------------------------------------------------------------------
-- R3b. Detalle por zona y día de lluvia fuerte.
-- ---------------------------------------------------------------------
-- Se dan dos líneas base: la que pide el reto, AVG() OVER (ZONA, DIA_SEMANA)
-- sobre todos los días, y una depurada que excluye los propios días de lluvia
-- fuerte (AVG ignora los NULL), porque incluirlos contamina la referencia.
-- Solo se miran zonas con 10 000 viajes o más en el trimestre: en una zona de
-- 5 viajes al día una caída del 40 % es ruido.
SELECT
    FECHA,
    ZONA,
    DIA_SEMANA,
    LLUVIA_MM,
    VIAJES_DIA,
    ROUND(AVG(VIAJES_DIA) OVER (PARTITION BY ZONA, DIA_SEMANA), 1)   AS BASE_DIA_SEMANA,
    ROUND(AVG(IFF(NOT LLUVIA_FUERTE, VIAJES_DIA, NULL))
          OVER (PARTITION BY ZONA, DIA_SEMANA), 1)                   AS BASE_SIN_LLUVIA_FUERTE,
    ROUND(100 * (VIAJES_DIA
                 / NULLIF(AVG(IFF(NOT LLUVIA_FUERTE, VIAJES_DIA, NULL))
                          OVER (PARTITION BY ZONA, DIA_SEMANA), 0) - 1), 1) AS DIF_PCT
FROM CURSO.T1.V_SERIE_ZONA_DIA
QUALIFY LLUVIA_FUERTE
    AND SUM(VIAJES_DIA) OVER (PARTITION BY ZONA) >= 10000
ORDER BY ABS(DIF_PCT) DESC
LIMIT 20;

-- Interpretación: Dieciséis de las veinte filas son subidas. El 23 de marzo, el
-- día más lluvioso del trimestre, aparece seis veces y las seis son subidas de
-- entre 38 % y 47 %, incluida Williamsburg (North Side), que con 15 859 viajes es
-- una zona grande y no un caso de poco volumen: ahí la lluvia fuerte sí mueve la
-- aguja. Las cuatro bajadas se concentran en dos días, el 13 de febrero y el 28 de
-- enero, y las cuatro ocurren en parques o zonas residenciales de las afueras
-- (Flushing Meadows, Prospect Park, Riverdale, Bronx Park): lugares a los que se
-- va por gusto y no por obligación.
--
-- Las dos líneas base casi no se diferencian (11 390,6 contra 10 968,6 en
-- Williamsburg, un 3,8 %), así que excluir los días de lluvia fuerte de la
-- referencia cambia poco y la conclusión no depende de esa decisión.
--
-- Qué NO dice: esta tabla está ordenada por tamaño del cambio, no por importancia,
-- y los porcentajes más grandes salen de zonas chicas. Rockaway Park, con +314 %,
-- pasa de 447 a 1 851 viajes en un solo sábado: es un caso atípico sobre el que no
-- se puede construir ninguna conclusión. La respuesta agregada y ponderada es la
-- de R3c. Y LLUVIA_MM no distingue el tipo de precipitación: que el 13 de febrero
-- y el 28 de enero vayan en dirección contraria al resto es compatible con que
-- parte de esos milímetros de invierno cayeran como nieve, que no afecta la
-- demanda igual que la lluvia, pero estos datos no permiten comprobarlo.

-- ---------------------------------------------------------------------
-- R3c. Resumen: ¿la lluvia fuerte sube o baja los viajes?
-- ---------------------------------------------------------------------
-- Compara los viajes observados en los días de lluvia fuerte contra los que
-- se esperaban según la línea base de cada zona y día de la semana. Es un
-- cociente de sumas, no un promedio de porcentajes: así las zonas grandes
-- pesan lo que deben (la misma lógica del promedio ponderado de A2).
WITH BASE AS (
    SELECT
        FECHA,
        ZONA,
        LLUVIA_FUERTE,
        VIAJES_DIA,
        AVG(IFF(NOT LLUVIA_FUERTE, VIAJES_DIA, NULL))
            OVER (PARTITION BY ZONA, DIA_SEMANA) AS ESPERADOS
    FROM CURSO.T1.V_SERIE_ZONA_DIA
)
SELECT
    COUNT(DISTINCT FECHA)                                   AS DIAS_LLUVIA_FUERTE,
    COUNT(DISTINCT ZONA)                                    AS ZONAS,
    SUM(VIAJES_DIA)                                         AS VIAJES_OBSERVADOS,
    ROUND(SUM(ESPERADOS))                                   AS VIAJES_ESPERADOS,
    ROUND(100 * (SUM(VIAJES_DIA) / NULLIF(SUM(ESPERADOS), 0) - 1), 1) AS DIF_PCT
FROM BASE
WHERE LLUVIA_FUERTE
  AND ESPERADOS IS NOT NULL;

-- Interpretación: En los 13 días con más de 10 mm la ciudad hizo 9 249 736 viajes
-- contra los 8 844 431 que se esperaban según lo que hace cada zona en ese mismo
-- día de la semana: 405 305 viajes de más, un 4,6 %, unos 31 000 por día lluvioso.
-- La lluvia fuerte sube la demanda de plataformas, pero la mueve poco: no cambia
-- el tamaño del mercado, lo empuja un 5 %.
--
-- La línea base explica la diferencia con el número ingenuo. Los días lluviosos
-- promediaron 711 518 viajes, un 7,4 % por encima del promedio diario del
-- trimestre; reportar ese 7,4 % habría sido un error, porque 6 de los 13 días
-- cayeron en fin de semana, que ya es más movido de por sí. Comparar cada zona
-- contra su mismo día de la semana descuenta ese sesgo y deja el efecto en 4,6 %.
--
-- Qué NO dice: es una asociación, no una causa. El 4,6 % es un promedio que
-- esconde comportamientos opuestos (ver R3b). Trece días son pocos para separar la
-- lluvia de lo que pasaba ese día en la ciudad, y LLUVIA_MM no dice si cayó como
-- lluvia o como nieve.


-- =====================================================================
-- R5 · RACHAS DE ALTA DEMANDA (HUECOS E ISLAS)
-- =====================================================================
-- «Alta demanda» en una zona = un día con más del 110 % del promedio diario
-- de esa misma zona en el trimestre. El umbral es relativo a la zona porque
-- un día flojo en JFK son más viajes que el mejor día de Broad Channel.
--
-- La técnica de huecos e islas: sobre los días que SÍ pasan el umbral, la
-- diferencia entre la fecha y su número de orden (ROW_NUMBER) es constante
-- mientras los días sean consecutivos, y cambia en cuanto hay un hueco. Esa
-- diferencia es la etiqueta de la isla, y agrupando por ella sale cada racha.
-- Funciona porque la serie viene de V_SERIE_ZONA_DIA y está completa: un día
-- sin viajes existe con 0, no pasa el umbral y parte la racha, que es lo
-- correcto. Con el hecho crudo ese día no existiría y la racha se pegaría.

-- ---------------------------------------------------------------------
-- R5a. Las rachas más largas por zona.
-- ---------------------------------------------------------------------
WITH SERIE AS (
    SELECT
        ZONA,
        FECHA,
        VIAJES_DIA,
        AVG(VIAJES_DIA) OVER (PARTITION BY ZONA) AS PROMEDIO_ZONA,
        SUM(VIAJES_DIA) OVER (PARTITION BY ZONA) AS VIAJES_ZONA
    FROM CURSO.T1.V_SERIE_ZONA_DIA
),
ALTA AS (
    SELECT ZONA, FECHA, VIAJES_DIA, PROMEDIO_ZONA
    FROM SERIE
    WHERE VIAJES_ZONA >= 10000                 -- zonas con volumen suficiente
      AND VIAJES_DIA  >  1.10 * PROMEDIO_ZONA  -- umbral de alta demanda
),
ISLAS AS (
    SELECT
        ZONA,
        FECHA,
        VIAJES_DIA,
        PROMEDIO_ZONA,
        DATEADD('day',
                -ROW_NUMBER() OVER (PARTITION BY ZONA ORDER BY FECHA),
                FECHA) AS ISLA
    FROM ALTA
)
SELECT
    ZONA,
    MIN(FECHA)                                                   AS INICIO,
    MAX(FECHA)                                                   AS FIN,
    DAYNAME(MIN(FECHA))                                          AS DIA_INICIO,
    DAYNAME(MAX(FECHA))                                          AS DIA_FIN,
    COUNT(*)                                                     AS DIAS_RACHA,
    SUM(VIAJES_DIA)                                              AS VIAJES_RACHA,
    ROUND(AVG(VIAJES_DIA))                                       AS VIAJES_POR_DIA,
    ROUND(100 * (AVG(VIAJES_DIA) / MAX(PROMEDIO_ZONA) - 1), 1)   AS SOBRE_PROMEDIO_PCT
FROM ISLAS
GROUP BY ZONA, ISLA
QUALIFY RANK() OVER (ORDER BY COUNT(*) DESC, SUM(VIAJES_DIA) DESC) <= 15
ORDER BY DIAS_RACHA DESC, VIAJES_RACHA DESC;

-- Interpretación: Las rachas por zona no tienen la forma de las de la ciudad. Las
-- doce de R5b empiezan entre miércoles y viernes y terminan sábado o domingo;
-- aquí nueve de las quince van de martes a sábado. Las zonas con las rachas más
-- largas son barrios de oficina y residenciales de Manhattan (West Chelsea/Hudson
-- Yards, Garment District, Murray Hill, Upper East Side, Lenox Hill, UN/Turtle Bay,
-- Morningside Heights) y su ritmo es la semana laboral, no el fin de semana. El
-- total de la ciudad esconde eso: al sumar todas las zonas gana el patrón de fin
-- de semana, que es el de la mayoría, y desaparece el de los barrios que más
-- viajes generan entre semana.
--
-- Hay además dos semanas que se repiten en varias zonas a la vez: del 16 al 20 de
-- enero coinciden tres zonas vecinas del Upper East Side, y del 5 al 9 de marzo
-- coinciden cinco zonas distintas. No son fenómenos de barrio sino semanas movidas
-- en toda la ciudad, que se notan más en unas zonas que en otras.
--
-- Qué NO dice: una racha mide irregularidad, no tamaño. De las tres zonas con más
-- viajes de A3 (JFK, LaGuardia y East Village) solo aparece LaGuardia: en las
-- otras la demanda es alta todos los días, así que casi ningún día se despega de
-- su propio promedio. Y dos de las rachas de seis días son de zonas pequeñas,
-- Bronx Park (284 viajes al día) y Pelham Bay Park (135): ahí un +37 % son 77
-- viajes más al día y basta un evento local para producirlo.

-- ---------------------------------------------------------------------
-- R5b. Rachas de toda la ciudad (días por encima del promedio diario).
-- ---------------------------------------------------------------------
-- A nivel de ciudad no hace falta la rejilla: los 91 días tienen filas.
WITH CIUDAD AS (
    SELECT FECHA, SUM(VIAJES) AS VIAJES_DIA
    FROM CURSO.T1.FACT_VIAJES_DIA
    GROUP BY FECHA
),
MARCADA AS (
    SELECT FECHA, VIAJES_DIA, AVG(VIAJES_DIA) OVER () AS PROMEDIO_CIUDAD
    FROM CIUDAD
),
ALTA AS (
    SELECT * FROM MARCADA WHERE VIAJES_DIA > PROMEDIO_CIUDAD
),
ISLAS AS (
    SELECT
        FECHA,
        VIAJES_DIA,
        PROMEDIO_CIUDAD,
        DATEADD('day', -ROW_NUMBER() OVER (ORDER BY FECHA), FECHA) AS ISLA
    FROM ALTA
)
SELECT
    MIN(FECHA)                                                     AS INICIO,
    MAX(FECHA)                                                     AS FIN,
    DAYNAME(MIN(FECHA))                                            AS DIA_INICIO,
    DAYNAME(MAX(FECHA))                                            AS DIA_FIN,
    COUNT(*)                                                       AS DIAS_RACHA,
    SUM(VIAJES_DIA)                                                AS VIAJES_RACHA,
    ROUND(AVG(VIAJES_DIA))                                         AS VIAJES_POR_DIA,
    ROUND(100 * (AVG(VIAJES_DIA) / MAX(PROMEDIO_CIUDAD) - 1), 1)   AS SOBRE_PROMEDIO_PCT
FROM ISLAS
GROUP BY ISLA
HAVING COUNT(*) >= 2
ORDER BY DIAS_RACHA DESC, INICIO;

-- Interpretación: Las rachas de la ciudad no son sorpresas, son el calendario
-- semanal. Las doce empiezan entre miércoles y viernes y las doce terminan sábado
-- o domingo, y hay una por semana en 12 de las 13 semanas del trimestre; la única
-- sin racha es la del 1 al 7 de enero, la de Año Nuevo. Los 45 días en racha, la
-- mitad del trimestre, concentran 32 817 613 viajes: el 54,5 % del total. Y se
-- intensifican hacia marzo, de +8,8 % la semana del 17 de enero a +12,4 % la del
-- 21 de marzo, lo que concuerda con que marzo sea el mes más alto.
--
-- Dos detalles del método: la racha del 28 de febrero al 3 de marzo cruza el
-- cambio de mes sin partirse, porque la isla se define por días consecutivos y no
-- por mes; y la del 28 al 30 de marzo se corta el domingo 31, que en 2024 fue
-- Pascua y que ES_FESTIVO no marca, porque FESTIVOS_2024 solo trae los festivos
-- federales.
--
-- Qué NO dice: una racha es una secuencia de días por encima del promedio del
-- propio trimestre, no una señal de crecimiento. Con tres meses de datos el
-- promedio se mueve con la temporada: marzo está por encima casi por definición,
-- porque es el mes más alto de los tres.

-- =====================================================================
-- FIN DEL ARCHIVO 06_retos.sql
-- =====================================================================
