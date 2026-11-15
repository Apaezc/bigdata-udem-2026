# Controles contra el origen y trampas · Taller 1

Equipo: Andrea Páez Cardona (analista, anfitriona), Ana María Montealegre (modeladora), Manuela Restrepo Céspedes (ingeniera de datos), Julian Olaya (calidad y costos) · Caso A · Competencia entre plataformas

Responsable de este archivo: **Julian Olaya, Calidad y costos**.

El archivo `05_calidad.sql` corre todos los controles en un solo `SELECT` (Run All). Devuelve una fila por control con `OBTENIDO`, `ESPERADO` y `RESULTADO` (`OK`, `REVISAR` o `INFO`), y una fila `RESUMEN` al principio. Complementa los cuatro chequeos de `04_chequeos.sql` y la autoverificación del curso (`verificar_t1.sql`), que no miran el origen fila por fila ni las trampas.

## 1. Qué se compara contra el origen

| Bloque | Qué comprueba | Por qué |
|---|---|---|
| 1 Origen | El gold `CURSO.LAB4.DAILY_ZONE_METRICS` tiene 46 715 filas, 60 268 466 viajes, grano único, 91 días y 2 empresas | `02_carga.sql` carga el hecho con `GROUP BY FECHA, ZONA, EMPRESA`: si el gold tuviera filas duplicadas, el `GROUP BY` las sumaría y el hecho pasaría el control de grano sin que nadie lo notara. Por eso el grano se comprueba **también en el origen** |
| 2 Hecho | Filas y viajes totales y **por mes** (enero 15 909 / 19 650 023; febrero 14 889 / 19 344 724; marzo 15 917 / 21 273 719); diferencia exacta de ingreso, propina total y distancia total contra el origen; comparación fila a fila con `MINUS` en los dos sentidos; llaves nulas; viajes ≤ 0 | El total puede cuadrar aunque un mes sobre y otro falte. `MINUS` encuentra cualquier fila que no sea idéntica |
| 3 Huérfanos | Cada `ZONA`, `FECHA` y `EMPRESA` del hecho existe en su dimensión; ninguna zona del gold falta en el catálogo de la TLC | Una zona sin pareja desaparece en un `JOIN` y baja los viajes |
| 4 Dimensiones | `DIM_FECHA` con 91 días seguidos, 3 festivos y 26 días de fin de semana; `DIM_ZONA` con 262 filas y 262 nombres; `DIM_EMPRESA` con las mismas empresas del gold | Una dimensión con clave repetida infla el hecho al unir |

## 2. Las trampas y cómo queda comprobada cada una

| Trampa | Dónde la evita el equipo | Control en `05_calidad.sql` | Lo que debe salir |
|---|---|---|---|
| **1. La lluvia se repite** | `02_carga.sql` guarda `MAX(LLUVIA_MM)` una vez por día en `DIM_FECHA`; el hecho no tiene lluvia | T1a: ningún día del gold tiene dos valores de lluvia. T1b: `DIM_FECHA` tiene la lluvia de cada día. T1c: el hecho no tiene `LLUVIA_MM`. T1d/T1e: el 10 de enero llovió 21,7 mm; sumar la columna en el gold da 11 153,8 mm (cifra sin sentido) | T1a–T1d en OK; T1e informativo |
| **2. Promedios de grupos** | El hecho guarda `PROPINA_TOTAL` y `DISTANCIA_TOTAL` (promedio × viajes); A2 usa `SUM / SUM` | T2a/T2b: JFK 24-ene da 3,82 ponderado desde el gold y desde el hecho. T2c: el promedio simple daría 3,905. T2d: la propina ponderada por empresa es igual desde el gold y desde el hecho | OK; T2c informativo |
| **3. El redondeo** | El control de A4 compara con `ABS(S - 1) >= 0.0001`, no con `=` | T3a: `0.1 + 0.2 = 0.3` es falso con FLOAT. T3b: con `ROUND` es verdadero. T3c y H10–H12: el dinero se compara sumando con `NUMBER(18,2)` y con tolerancia de 0,01. Todo el archivo usa `ABS(OBTENIDO - ESPERADO) < 0.01` | OK; T3a informativo (sale 0) |
| **4. El nombre de zona** | `02_carga.sql` deja una fila por nombre en `DIM_ZONA` (`ROW_NUMBER() ... = 1`) y el hecho se une por nombre | T4a: hay 2 nombres repetidos en la dimensión del Lab 4 (Corona; Governor's Island/Ellis Island/Liberty Island). T4b: los repetidos tienen el mismo distrito y tipo de zona, así que quedarse con una fila no pierde información. T4c–T4e: unir el gold con la dimensión sin depurar agrega 196 filas y 184 265 viajes (0,3 %). T4f/T4g: con la dimensión depurada quedan 46 715 filas y 60 268 466 viajes | OK; T4c–T4e informativos |
| **LAG mira la fila anterior** | A4 crea la vista `V_CUOTA_ZONA_MES` con una rejilla mes × zona × empresa y `COALESCE(VIAJES, 0)`; A5 aplica `LAG` sobre esa rejilla y filtra en `QUALIFY` (después de calcular el `LAG`) | L1: cuántas parejas (zona, empresa) no tienen viajes algún mes (son las que romperían `LAG` sin la rejilla). L2: la vista tiene exactamente 3 meses por pareja. L3: los ceros agregados no cambian el total de viajes | L2–L3 en OK; L1 informativo |

## 3. Resultados

Corrido el 15 de noviembre de 2026 en la cuenta de Julian Olaya, después de cargar desde cero el Lab 4 (`COPY INTO` desde el bucket público, `datos/dim_zona.sql` y `datos/festivos_2024.sql`) y de correr sin cambios `01_estrella.sql`, `02_carga.sql` y la vista `V_CUOTA_ZONA_MES` de `03_preguntas.sql` del equipo. Así queda probado que la carga del equipo es **reproducible** en una cuenta distinta a la de la anfitriona.

**RESUMEN: 48 de 48 controles en OK.**

| Bloque | Control | Obtenido | Esperado | Resultado |
|---|---|---|---|---|
| 1 Origen | O1 filas del gold | 46 715 | 46 715 | OK |
| 1 Origen | O2 viajes del gold | 60 268 466 | 60 268 466 | OK |
| 1 Origen | O3 grano único en el gold | 46 715 | 46 715 | OK |
| 1 Origen | O4 días distintos en el gold | 91 | 91 | OK |
| 1 Origen | O5 empresas distintas en el gold | 2 | 2 | OK |
| 2 Hecho | H1 filas del hecho | 46 715 | 46 715 | OK |
| 2 Hecho | H2 grano único del hecho | 46 715 | 46 715 | OK |
| 2 Hecho | H3 viajes del hecho | 60 268 466 | 60 268 466 | OK |
| 2 Hecho | H4–H6 filas enero / febrero / marzo | 15 909 / 14 889 / 15 917 | 15 909 / 14 889 / 15 917 | OK |
| 2 Hecho | H7–H9 viajes enero / febrero / marzo | 19 650 023 / 19 344 724 / 21 273 719 | 19 650 023 / 19 344 724 / 21 273 719 | OK |
| 2 Hecho | H10 diferencia de ingreso hecho − origen | 0,00 USD | 0 | OK |
| 2 Hecho | H11 diferencia de propina total | 0,00 USD | 0 | OK |
| 2 Hecho | H12 diferencia de distancia total | 0,00 millas | 0 | OK |
| 2 Hecho | H13 filas del origen que faltan o difieren en el hecho | 0 | 0 | OK |
| 2 Hecho | H14 filas del hecho que no existen en el origen | 0 | 0 | OK |
| 2 Hecho | H15 llaves nulas · H16 viajes ≤ 0 | 0 · 0 | 0 · 0 | OK |
| 3 Huérfanos | U1 sin zona · U2 sin fecha · U3 sin empresa | 0 · 0 · 0 | 0 · 0 · 0 | OK |
| 3 Huérfanos | U4 zonas del gold sin pareja en el catálogo TLC | 0 | 0 | OK |
| 4 Dimensiones | D1–D3 `DIM_FECHA`: filas, fechas únicas, días seguidos | 91 · 91 · 91 | 91 | OK |
| 4 Dimensiones | D4 festivos · D5 días de fin de semana | 3 · 26 | 3 · 26 | OK |
| 4 Dimensiones | D6–D7 `DIM_ZONA`: filas y nombres únicos | 262 · 262 | 262 | OK |
| 4 Dimensiones | D8 `DIM_EMPRESA` = empresas del gold | 2 | 2 | OK |
| 5 Trampa 1 | T1a días con más de un valor de lluvia | 0 | 0 | OK |
| 5 Trampa 1 | T1b días donde `DIM_FECHA` no tiene la lluvia del gold | 0 | 0 | OK |
| 5 Trampa 1 | T1c columna `LLUVIA_MM` en el hecho | 0 | 0 | OK |
| 5 Trampa 1 | T1d lluvia del 2024-01-10 en `DIM_FECHA` | 21,7 mm | 21,7 | OK |
| 5 Trampa 1 | T1e `SUM(LLUVIA_MM)` del 2024-01-10 en el gold (mal) | 11 153,8 mm | — | INFO |
| 5 Trampa 1 | T1f `COUNT(*)` del gold (filas, no días) | 46 715 | — | INFO |
| 6 Trampa 2 | T2a / T2b propina ponderada JFK 24-ene (gold / hecho) | 3,82 / 3,82 | 3,82 | OK |
| 6 Trampa 2 | T2c promedio simple JFK 24-ene (mal) | 3,905 | — | INFO |
| 6 Trampa 2 | T2d empresas con propina ponderada distinta gold vs hecho | 0 | 0 | OK |
| 7 Trampa 3 | T3a `0.1 + 0.2 = 0.3` con FLOAT | 0 (FALSE) | — | INFO |
| 7 Trampa 3 | T3b `ROUND(0.1 + 0.2, 2) = 0.3` | 1 (TRUE) | 1 | OK |
| 7 Trampa 3 | T3c ingreso FLOAT hecho vs gold con `ABS(...) < 0.01` | 1 (TRUE) | 1 | OK |
| 8 Trampa 4 | T4a nombres repetidos en `DIM_ZONA` del Lab 4 | 2 | 2 | OK |
| 8 Trampa 4 | T4b repetidos con distrito o tipo de zona distinto | 0 | 0 | OK |
| 8 Trampa 4 | T4c filas al unir el gold con la dimensión sin depurar (mal) | 46 911 | — | INFO |
| 8 Trampa 4 | T4d / T4e filas y viajes que sobran con esa unión | 196 / 184 265 | — | INFO |
| 8 Trampa 4 | T4f / T4g unión con `DIM_ZONA` depurada: filas / viajes | 46 715 / 60 268 466 | 46 715 / 60 268 466 | OK |
| 9 Trampa LAG | L1 parejas (zona, empresa) a las que les falta algún mes | 3 | — | INFO |
| 9 Trampa LAG | L2 filas de `V_CUOTA_ZONA_MES` = 3 × parejas | 1 563 | 1 563 | OK |
| 9 Trampa LAG | L3 viajes en `V_CUOTA_ZONA_MES` | 60 268 466 | 60 268 466 | OK |

**Lectura.** La estrella reproduce el origen fila por fila y centavo por centavo. Las cuatro trampas tienen el efecto que describe el enunciado y el equipo las evita todas:

- **Lluvia:** sumarla daría 11 153,8 mm en un día en que llovieron 21,7 mm.
- **Propina:** el promedio simple daría 3,905 USD en lugar de 3,82.
- **Zona:** unir por nombre con la dimensión sin depurar inflaría el hecho en 196 filas y 184 265 viajes.
- **LAG:** hay 3 parejas (zona, empresa) a las que les falta algún mes. Sin la rejilla de A4, el `LAG` de A5 compararía con dos meses atrás en esos casos. Con la rejilla, cada pareja tiene sus 3 meses (1 563 filas = 3 × 521 parejas).

## 4. Observaciones de calidad sobre los archivos del equipo

Revisé los archivos de `taller1/` sin modificarlos. No encontré errores en las cifras; dejo estas observaciones para quien sea responsable de cada archivo:

1. **Faltan archivos que pide el enunciado** (sección 8) en `taller1/`: `diagrama.md`, `RETOS.md`, `costos.md` y `autoverificacion.txt`. Este archivo y `costos.md` cubren mi parte; `05_calidad.sql` también puede contar como el reto **R4** (suite de chequeos en un solo archivo ejecutable), si el equipo lo pone en `RETOS.md`.
2. Los números finales deben reportarse también desde la cuenta de la anfitriona (sección 2 del enunciado). Basta con que Andrea corra `05_calidad.sql` y compruebe que la fila RESUMEN da 48 de 48.
3. `02_carga.sql` genera `DIM_FECHA` con 91 días fijos desde `2024-01-01`. Coincide con el gold, pero no sale del rango del gold como en la plantilla del enunciado. Los controles D1–D3 y U2 lo detectarían si el rango cambiara.
4. `02_carga.sql` usa `TRUNCATE` + `INSERT`, así que se puede volver a correr (carga idempotente). Depende de que `01_estrella.sql` se haya corrido antes, porque las tablas deben existir. Lo comprobé en una cuenta nueva y dio los mismos conteos.
5. Las preguntas de `03_preguntas.sql` leen directo del gold (lo permite el caso A). El control T2d y la fila a fila H13/H14 demuestran que leer el hecho daría las mismas cifras.
6. `04_chequeos.sql` reconcilia solo totales. `05_calidad.sql` agrega la reconciliación por mes, el dinero y la comparación fila a fila.
