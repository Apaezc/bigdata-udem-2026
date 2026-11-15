-- =====================================================================
-- TALLER 1 · 03_preguntas.sql · Las cinco preguntas del caso
-- =====================================================================
-- Caso elegido: A · Competencia entre plataformas
-- Pregunta guía: ¿hay concentración en el mercado de viajes por zona y cómo evoluciona?
-- Fuente: solo CURSO.LAB4.DAILY_ZONE_METRICS (como pide el caso A).
-- Ventanas usadas: RANK + QUALIFY (A3), SUM() OVER (A4 y A5), LAG (A5).
--
-- Definiciones del equipo (se explican también en memo.md):
--   * MES   = DATE_TRUNC('month', FECHA)  -> 2024-01-01, 2024-02-01, 2024-03-01
--   * CUOTA = viajes de la empresa / viajes de todas las empresas en esa zona y mes
--             (cuota medida en VIAJES, no en ingresos)
--   * Zona "relevante" para hablar de dominio = 1 000 viajes o más en el mes
--     (en zonas muy pequeñas una cuota de 100 % puede ser solo azar)
--   * EMPRESA se toma tal como viene en los datos; no se escribe "Uber" ni "Lyft" a mano.
-- =====================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE SCHEMA CURSO.T1;

-- ---------------------------------------------------------------------
-- Pregunta A1: Ingresos y viajes por empresa y mes
-- Técnica: GROUP BY
-- ---------------------------------------------------------------------
SELECT
    DATE_TRUNC('month', FECHA)                       AS MES,
    EMPRESA,
    SUM(VIAJES)                                      AS VIAJES,
    ROUND(SUM(INGRESO_TOTAL), 2)                     AS INGRESO_TOTAL,
    ROUND(SUM(INGRESO_TOTAL) / SUM(VIAJES), 2)       AS INGRESO_POR_VIAJE
FROM CURSO.LAB4.DAILY_ZONE_METRICS
GROUP BY MES, EMPRESA
ORDER BY MES, EMPRESA;

-- Control rápido: la suma de VIAJES de las dos empresas en cada mes debe dar
-- enero 19 650 023, febrero 19 344 724 y marzo 21 273 719 (total 60 268 466).
--
-- Resultado:
--   MES      EMPRESA  VIAJES      INGRESO_TOTAL    INGRESO_POR_VIAJE
--   2024-01  Lyft      5 222 393  151 065 543.37   28.93
--   2024-01  Uber     14 427 630  439 012 762.36   30.43
--   2024-02  Lyft      4 948 252  146 652 622.57   29.64
--   2024-02  Uber     14 396 472  442 015 343.77   30.70
--   2024-03  Lyft      5 657 133  176 930 975.63   31.28
--   2024-03  Uber     15 616 586  502 018 342.30   32.15
--   Control: la suma por mes da 19 650 023, 19 344 724 y 21 273 719 viajes (total 60 268 466). OK.
--
-- Interpretación: En el trimestre Uber hizo 44 440 688 viajes y Lyft 15 827 778: Uber hace
-- 2,8 viajes por cada viaje de Lyft (73,7 % de los viajes) y se queda con el 74,5 % del
-- ingreso. El ingreso por viaje (ticket promedio) de Uber es más alto todos los meses
-- (31,12 USD contra 29,99 USD en el trimestre) y sube en las dos empresas de enero a marzo.
-- Marzo tiene 10 % más viajes que febrero, pero también 2 días más: por día la subida es
-- solo de 2,9 % (686 249 contra 667 059 viajes diarios).
-- Qué NO dice: el ingreso es lo que paga el pasajero, no la ganancia de la empresa.

-- ---------------------------------------------------------------------
-- Pregunta A2: Propina promedio por empresa, ponderada por viajes
-- Técnica: SUM / SUM
-- ---------------------------------------------------------------------
SELECT
    EMPRESA,
    SUM(VIAJES)                                                  AS VIAJES,
    ROUND(SUM(PROPINA_PROMEDIO * VIAJES) / SUM(VIAJES), 2)       AS PROPINA_PONDERADA,
    ROUND(AVG(PROPINA_PROMEDIO), 2)                              AS PROPINA_SIMPLE_NO_USAR
FROM CURSO.LAB4.DAILY_ZONE_METRICS
GROUP BY EMPRESA
ORDER BY EMPRESA;

-- La columna PROPINA_SIMPLE_NO_USAR solo está para mostrar la trampa 2 (promediar
-- promedios): trata igual a un grupo de 10 viajes que a uno de 10 000. La cifra
-- correcta es PROPINA_PONDERADA. Como el gold ya redondeó cada promedio a 2 decimales,
-- el resultado es aproximado al centavo.
--
-- Resultado:
--   EMPRESA  PROPINA_PONDERADA  PROPINA_SIMPLE_NO_USAR
--   Lyft     1.18               1.00
--   Uber     1.06               0.89
--
-- Interpretación: Por cada viaje, los pasajeros dejan en promedio 1,18 USD de propina en Lyft
-- y 1,06 USD en Uber: Lyft cobra un poco menos por viaje pero recibe más propina. Si hubiéramos
-- promediado los promedios, habríamos dicho 1,00 y 0,89 USD, es decir, unos 15 % menos en
-- las dos empresas, porque los grupos pequeños (zonas con pocos viajes y poca propina) habrían
-- pesado igual que los grandes.
-- Qué NO dice: no sabemos si la diferencia es por la empresa o por el tipo de viaje que hace
-- cada una (por ejemplo, más o menos viajes al aeropuerto).

-- ---------------------------------------------------------------------
-- Pregunta A3: Las tres zonas con más viajes de cada empresa
-- Técnica: RANK y QUALIFY
-- ---------------------------------------------------------------------
SELECT
    EMPRESA,
    ZONA,
    SUM(VIAJES)                                                  AS VIAJES,
    RANK() OVER (PARTITION BY EMPRESA ORDER BY SUM(VIAJES) DESC) AS PUESTO
FROM CURSO.LAB4.DAILY_ZONE_METRICS
GROUP BY EMPRESA, ZONA
QUALIFY PUESTO <= 3
ORDER BY EMPRESA, PUESTO;

-- Usamos RANK (no ROW_NUMBER): si dos zonas empatan, las dos quedan en el mismo puesto,
-- así que el resultado puede tener más de 3 filas por empresa. QUALIFY filtra después de
-- calcular la ventana; en WHERE daría error.
--
-- Resultado:
--   EMPRESA  PUESTO  ZONA               VIAJES
--   Lyft     1       LaGuardia Airport  295 689
--   Lyft     2       JFK Airport        247 170
--   Lyft     3       East Village       227 918
--   Uber     1       JFK Airport        810 070
--   Uber     2       LaGuardia Airport  773 675
--   Uber     3       East Village       614 619
--
-- Interpretación: Las dos empresas tienen las mismas tres zonas en su top: los dos aeropuertos
-- y East Village. Solo cambia el orden de los aeropuertos (Lyft recoge más en LaGuardia y Uber
-- en JFK). No hay "territorios" separados: compiten en los mismos lugares, y en cada uno Uber
-- hace entre 2,6 y 3,3 veces los viajes de Lyft.
-- Qué NO dice: es la zona de RECOGIDA; no dice a dónde van los pasajeros.

-- ---------------------------------------------------------------------
-- Pregunta A4: Cuota de mercado de cada empresa en cada zona y mes
-- Técnica: SUM() OVER (PARTITION BY ZONA, MES)
-- ---------------------------------------------------------------------
-- Guardamos el cálculo en una vista porque A5 lo reutiliza.
-- La "rejilla" crea todas las combinaciones mes × zona × empresa y pone 0 viajes donde
-- una empresa no operó ese mes. Así A5 no cae en la trampa de LAG (que mira la fila
-- anterior, no el mes anterior).
CREATE OR REPLACE VIEW CURSO.T1.V_CUOTA_ZONA_MES AS
WITH base AS (
    SELECT DATE_TRUNC('month', FECHA) AS MES, ZONA, EMPRESA, SUM(VIAJES) AS VIAJES
    FROM CURSO.LAB4.DAILY_ZONE_METRICS
    GROUP BY 1, 2, 3
),
meses   AS (SELECT DISTINCT MES FROM base),
combos  AS (SELECT DISTINCT ZONA, EMPRESA FROM base),
rejilla AS (
    SELECT m.MES, c.ZONA, c.EMPRESA, COALESCE(b.VIAJES, 0) AS VIAJES
    FROM meses m
    CROSS JOIN combos c
    LEFT JOIN base b
           ON b.MES = m.MES AND b.ZONA = c.ZONA AND b.EMPRESA = c.EMPRESA
)
SELECT
    MES, ZONA, EMPRESA, VIAJES,
    SUM(VIAJES) OVER (PARTITION BY ZONA, MES)                         AS VIAJES_ZONA_MES,
    VIAJES / NULLIF(SUM(VIAJES) OVER (PARTITION BY ZONA, MES), 0)     AS CUOTA
FROM rejilla;

-- 4a. Cuota por zona y mes (las zonas más grandes primero)
SELECT MES, ZONA, EMPRESA, VIAJES, VIAJES_ZONA_MES,
       ROUND(100 * CUOTA, 1) AS CUOTA_PCT
FROM CURSO.T1.V_CUOTA_ZONA_MES
WHERE VIAJES_ZONA_MES > 0
ORDER BY VIAJES_ZONA_MES DESC, ZONA, MES, EMPRESA;

-- 4b. Para leer el total: cuota de cada empresa en toda la ciudad por mes
SELECT MES, EMPRESA, SUM(VIAJES) AS VIAJES,
       ROUND(100 * SUM(VIAJES) / SUM(SUM(VIAJES)) OVER (PARTITION BY MES), 1) AS CUOTA_CIUDAD_PCT
FROM CURSO.T1.V_CUOTA_ZONA_MES
GROUP BY MES, EMPRESA
ORDER BY MES, EMPRESA;

-- Control: en cada zona y mes las cuotas de las empresas deben sumar 100 %.
SELECT COUNT(*) AS ZONA_MES_QUE_NO_SUMAN_100
FROM (
    SELECT ZONA, MES, SUM(CUOTA) AS S
    FROM CURSO.T1.V_CUOTA_ZONA_MES
    WHERE VIAJES_ZONA_MES > 0
    GROUP BY ZONA, MES
)
WHERE ABS(S - 1) >= 0.0001;   -- esperado: 0 (no se compara con "=", trampa 3)

-- Resultado 4b (cuota en toda la ciudad):
--   MES      Lyft    Uber
--   2024-01  26.6 %  73.4 %
--   2024-02  25.6 %  74.4 %
--   2024-03  26.6 %  73.4 %
--
-- Interpretación: Uber tiene cerca de tres de cada cuatro viajes en toda la ciudad, y esa
-- proporción casi no se mueve: sube un punto en febrero y vuelve a 73,4 % en marzo. El mercado
-- de plataformas está concentrado y estable. Zona por zona la concentración es todavía mayor
-- (ver A5).
-- Qué NO dice: solo mide Uber y Lyft; los taxis amarillos y verdes no están en los datos,
-- así que "mercado" aquí es el de plataformas, no todo el transporte.

-- ---------------------------------------------------------------------
-- Pregunta A5: Variación mensual de la cuota y zonas donde una empresa pasa de 70 %
-- Técnica: LAG
-- ---------------------------------------------------------------------
-- 5a. Detalle: zonas relevantes (>= 1 000 viajes en el mes) donde una empresa supera 70 %,
-- con su cuota del mes anterior y la variación en puntos porcentuales (pp).
SELECT
    MES, ZONA, EMPRESA, VIAJES, VIAJES_ZONA_MES,
    ROUND(100 * CUOTA, 1)                                                     AS CUOTA_PCT,
    ROUND(100 * LAG(CUOTA) OVER (PARTITION BY ZONA, EMPRESA ORDER BY MES), 1) AS CUOTA_MES_ANT_PCT,
    ROUND(100 * (CUOTA - LAG(CUOTA) OVER (PARTITION BY ZONA, EMPRESA ORDER BY MES)), 1) AS VARIACION_PP
FROM CURSO.T1.V_CUOTA_ZONA_MES
QUALIFY CUOTA > 0.70
    AND VIAJES_ZONA_MES >= 1000
ORDER BY ZONA, EMPRESA, MES;

-- El filtro va en QUALIFY y no en WHERE a propósito: QUALIFY se aplica DESPUÉS de calcular
-- LAG, así el mes anterior se lee aunque ese mes no pase el filtro de 70 %.
-- En enero la variación sale NULL porque no hay diciembre en los datos.

-- 5b. Resumen: cuántas zonas relevantes domina cada empresa (> 70 %) en cada mes
SELECT MES, EMPRESA, COUNT(*) AS ZONAS_DOMINADAS
FROM CURSO.T1.V_CUOTA_ZONA_MES
WHERE CUOTA > 0.70
  AND VIAJES_ZONA_MES >= 1000
GROUP BY MES, EMPRESA
ORDER BY MES, EMPRESA;

-- 5c. Las zonas relevantes donde más cambió la cuota de enero a marzo
SELECT ZONA, EMPRESA,
       ROUND(100 * CUOTA_ENE, 1)              AS CUOTA_ENE_PCT,
       ROUND(100 * CUOTA, 1)                  AS CUOTA_MAR_PCT,
       ROUND(100 * (CUOTA - CUOTA_ENE), 1)    AS CAMBIO_PP
FROM (
    SELECT ZONA, EMPRESA, MES, CUOTA, VIAJES_ZONA_MES,
           LAG(CUOTA, 2) OVER (PARTITION BY ZONA, EMPRESA ORDER BY MES) AS CUOTA_ENE
    FROM CURSO.T1.V_CUOTA_ZONA_MES
)
WHERE MES = '2024-03-01' AND VIAJES_ZONA_MES >= 1000 AND CUOTA_ENE IS NOT NULL
QUALIFY RANK() OVER (PARTITION BY EMPRESA ORDER BY ABS(CUOTA - CUOTA_ENE) DESC) <= 5
ORDER BY EMPRESA, ABS(CAMBIO_PP) DESC;

-- Resultado 5b (zonas con 1 000 viajes o más en el mes donde una empresa pasa de 70 %):
--   MES      ZONAS_RELEVANTES  Uber > 70 %   Lyft > 70 %
--   2024-01  249               194 (77.9 %)  1
--   2024-02  249               224 (90.0 %)  1
--   2024-03  250               211 (84.4 %)  1
-- Cambio medio de la cuota frente al mes anterior en esas zonas: 1,44 pp en febrero y
-- 0,97 pp en marzo.
-- Resultado 5c (zonas donde más cambió la cuota de enero a marzo; las cinco son ganancias de Uber):
--   Marine Park/Floyd Bennett Field  69.4 % -> 74.4 %  (+5.0 pp)
--   Bloomfield/Emerson Hill          65.2 % -> 69.8 %  (+4.7 pp)
--   Mariners Harbor                  63.6 % -> 67.9 %  (+4.3 pp)
--   Broad Channel                    77.6 % -> 81.8 %  (+4.2 pp)
--   Rosedale                         69.2 % -> 73.4 %  (+4.1 pp)
--
-- Interpretación: Uber pasa del 70 % de los viajes en la gran mayoría de las zonas relevantes:
-- 194 de 249 en enero, 224 en febrero y 211 de 250 en marzo. Lyft solo domina una zona. La
-- cuota de cada zona se mueve poco de un mes a otro (en promedio entre 1 y 1,5 puntos), y el
-- cambio más grande de enero a marzo fue de 5 puntos. Esos cambios grandes son todos a favor de
-- Uber y en zonas de las afueras (Staten Island, el sur de Brooklyn y Queens), algunas de las
-- cuales cruzaron justo la línea del 70 %.
-- Qué NO dice: tres meses son pocos para hablar de tendencia; un cambio de un mes puede ser
-- estacional (invierno) o por un evento puntual. El umbral de 1 000 viajes es una decisión
-- nuestra: con otro umbral el conteo de zonas cambia.
