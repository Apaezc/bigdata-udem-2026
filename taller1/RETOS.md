# Retos opcionales · Taller 1

Equipo: Andrea Páez Cardona, Ana María Montealegre Ramírez, Manuela Restrepo Céspedes, Julian Olaya · Caso A · Competencia entre plataformas

Los retos suman hasta +15 puntos (los puntos de los seis suman 17; el máximo que se acredita es 15). Hicimos cuatro: **R2, R3, R4 y R5, que suman 11 puntos.**

| Id | Reto | Pts | ¿Hecho? | Dónde está (archivo y línea o sección) |
|---|---|---|---|---|
| R1 | Un segundo caso completo (cinco preguntas más) | 3 | no | — |
| R2 | `DIM_FECHA` con festivos y fin de semana, usada en una consulta | 2 | sí | DDL en `01_estrella.sql`, sección 3 (`ES_FESTIVO`, `ES_FIN_SEMANA`); carga en `02_carga.sql`, sección 1; consultas en `06_retos.sql`, sección **R2** (R2a festivos contra el mismo día de la semana, R2b entre semana contra fin de semana) |
| R3 | Lluvia fuerte (más de 10 mm) frente a la línea base del mismo día de la semana (`AVG() OVER (PARTITION BY ZONA, DIA_SEMANA)`) | 3 | sí | `06_retos.sql`, sección **R3** (R3a días con más de 10 mm, R3b detalle por zona, R3c resumen ponderado) |
| R4 | Suite de chequeos (grano, huérfanos, reconciliación con el conteo del paquete) en un solo archivo ejecutable | 3 | sí | `05_calidad.sql` completo: un solo `SELECT` (Run All) con 56 controles en 9 bloques y una fila de resumen; grano en H2 y O3, huérfanos en U1–U4, reconciliación contra el paquete en O1, O2, H1, H3–H9 y contra el origen fila a fila en H13 y H14 |
| R5 | Rachas de alta demanda (días consecutivos sobre un umbral; el problema de «huecos e islas») | 3 | sí | `06_retos.sql`, sección **R5** (R5a rachas por zona, R5b rachas de la ciudad) |
| R6 | Tabla externa de Athena sobre el paquete (la del Lab 4, E7) y reconciliación de conteos con Snowflake: filas por mes y viajes totales, con captura de `Data scanned` | 3 | no | — |

## Cómo correr los retos

`06_retos.sql` necesita que ya se hayan corrido `01_estrella.sql` y `02_carga.sql`. No depende de `03_preguntas.sql` ni de `05_calidad.sql`. Se abre en una hoja nueva de Snowsight y se corre con **Run All**.

El archivo crea la vista `CURSO.T1.V_SERIE_ZONA_DIA`, que R3 y R5 comparten: cruza las 91 fechas de `DIM_FECHA` con todas las zonas del hecho y pone 0 viajes donde el hecho no tiene fila. Sin esa rejilla, una racha de días consecutivos se pegaría por encima de los días en que una zona no hizo viajes, que es la trampa de las ventanas que advierte el enunciado (`LAG` y `ROWS` miran la fila anterior, no el día anterior). El control que acompaña a la vista reporta cuántos pares (zona, día) faltaban en el hecho.

## Qué aporta cada reto

**R2.** `DIM_FECHA` no quedó como una tabla de adorno: `ES_FESTIVO` sale de un `LEFT JOIN` contra `CURSO.LAB4.FESTIVOS_2024` y `ES_FIN_SEMANA` de `DAYOFWEEKISO(FECHA) IN (6, 7)`, y las dos columnas se usan en consultas. R2a compara cada uno de los tres festivos (1 y 15 de enero y 19 de febrero, los tres lunes) contra el promedio de los lunes no festivos, con el filtro en `QUALIFY` y no en `WHERE`: `WHERE` se aplica antes de la ventana y dejaría la línea base calculada solo con los festivos, es decir, comparándolos consigo mismos. R2b separa entre semana y fin de semana contando los días con `COUNT(DISTINCT FECHA)` y no con `COUNT(*)`, que daría filas del hecho y no días.

**R3.** Un día de lluvia fuerte es el que pasa de 10 mm según `LLUVIA_MM` de `DIM_FECHA`, donde la lluvia está guardada una sola vez por día. La línea base es el promedio de viajes de esa misma zona en ese mismo día de la semana, con `AVG() OVER (PARTITION BY ZONA, DIA_SEMANA)`, para no comparar un sábado lluvioso contra un martes seco. Además de la línea base que pide el reto, se calcula una depurada que excluye los propios días de lluvia fuerte, porque incluirlos contamina la referencia. El resumen de R3c divide suma entre suma y no promedia porcentajes, igual que el promedio ponderado de A2.

**R4.** `05_calidad.sql` es una sola consulta que devuelve una fila por control con `BLOQUE`, `CONTROL`, `OBTENIDO`, `ESPERADO` y `RESULTADO` (`OK`, `REVISAR` o `INFO`), más una fila de resumen que dice cuántos controles pasaron. Compara la estrella contra el origen `CURSO.LAB4.DAILY_ZONE_METRICS` y contra las cifras del paquete, comprueba el grano en las dos tablas, busca huérfanos en las tres dimensiones y demuestra las cuatro trampas del enunciado más la de `LAG`. Las comparaciones de dinero usan `NUMBER` y `ABS(a - b) < 0.01`, nunca `=` sobre `FLOAT`.

**R5.** Un día es de alta demanda para una zona si supera el 110 % del promedio diario de esa zona en el trimestre; el umbral es relativo porque un día flojo en JFK son más viajes que el mejor día de Broad Channel. Las rachas se arman con la técnica de huecos e islas: sobre los días que pasan el umbral, la diferencia entre la fecha y su `ROW_NUMBER` se mantiene constante mientras los días son consecutivos y cambia en cuanto hay un hueco, así que agrupar por esa diferencia da cada racha. R5b repite el ejercicio para toda la ciudad.

## Resultados

Los resultados de cada consulta quedan como comentario en `06_retos.sql`, debajo de la consulta que los produce. Los de R4 son la salida de `05_calidad.sql`.

## Sobre R6

No se hizo: el equipo trabajó el taller completo en Snowflake y no montó la tabla externa de Athena, así que no hay reconciliación ni captura de `Data scanned` que reportar.
