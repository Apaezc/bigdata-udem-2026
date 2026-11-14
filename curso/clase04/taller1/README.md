# Taller 1 · Una estrella en Snowflake para la pregunta de la lluvia en NYC

Big Data e Ingeniería de Datos (UdeM) · Clase 4, 10 de noviembre de 2026 · **Entrega: domingo 15 de noviembre de 2026, 23:59 (hora de Colombia)** · Equipos de hasta 4 personas

El Taller 1 vale 100 puntos (85 de núcleo y hasta 15 de retos). Junto con el Taller 2 (29 de noviembre) forma la nota de talleres, 50 % cada uno. Se trabaja solo con GitHub y Snowsight. La única ayuda es el instructor.

## 1. Qué entregas y para quién

Eres el equipo de analítica de una autoridad de movilidad. Con los viajes de plataformas como Uber y Lyft en NYC, resumidos por día, zona y empresa de enero a marzo de 2024, debes:

1. **Diseñar una estrella** (un hecho y al menos dos dimensiones) con el grano escrito en una frase.
2. **Cargarla** en Snowflake con un conteo de control contra el paquete de datos.
3. **Responder cinco preguntas** de un caso a tu elección, con funciones de ventana.
4. **Escribir un memo de una página** para una audiencia que no es técnica.

### Palabras que usa este enunciado

| Término | Qué significa | Ejemplo con los datos |
|---|---|---|
| Tabla de hechos | La tabla que guarda lo que se mide | Una fila: 2024-01-24, JFK Airport, Lyft, 1 965 viajes, ingreso 153 097.03 |
| Dimensión | Una tabla que describe por qué cosa se mide | Zonas (distrito, tipo de zona), fechas (día de la semana, lluvia), empresas |
| Grano | Qué representa una fila de la tabla de hechos | «Una fecha en una zona para una empresa» |
| Huérfano | Fila del hecho cuya clave no existe en la dimensión | Una zona del gold que no está en `DIM_ZONA` |
| Función de ventana | Calcula sobre un grupo de filas sin colapsarlas | `SUM(VIAJES) OVER (PARTITION BY ZONA)` pone el total de la zona en cada fila |
| QUALIFY | Filtra el resultado de una ventana sin anidar la consulta | `QUALIFY RANK() OVER (...) <= 3` |
| Promedio ponderado | Promedio de promedios con el peso de cada grupo | `SUM(PROMEDIO * VIAJES) / SUM(VIAJES)` |
| Borough | Distrito de NYC (Manhattan, Brooklyn, Queens, Bronx, Staten Island); la columna también trae `EWR` (Newark), `Unknown` y `N/A` | Columna `BOROUGH` de `DIM_ZONA` |
| Núcleo | Los siete archivos que todo equipo entrega en `taller1/` | `01_estrella.sql`, `memo.md` |
| Fork | Copia personal de un repositorio de GitHub; la del anfitrión es el repositorio del equipo | `github.com/<anfitrión>/<repositorio>` |
| Anfitrión | Integrante dueño del fork donde vive el trabajo del equipo | Quien añade a los demás en Settings > Collaborators |
| Query Profile | Desglose por operador de una consulta, en Snowsight | Pestaña Query Profile de una consulta |

## 2. Antes de empezar

1. Termina el **Lab 4**: debes tener en `CURSO.LAB4` la tabla `DAILY_ZONE_METRICS` con **46 715 filas**, y las tablas `DIM_ZONA` y `FESTIVOS_2024`.
2. Ubica tu equipo (hasta 4 personas) en la lista que proyecta el instructor, armada con el formulario de perfil de la clase 1. Elijan un **anfitrión**: su fork de GitHub (la copia personal del repositorio del curso) es el repositorio del equipo.
3. El anfitrión añade a los demás: en su fork, **Settings > Collaborators > Add people**. Cada integrante acepta la invitación.
4. El anfitrión crea la carpeta `taller1/` en su fork: **Add file > Create new file**, nombre `taller1/README.md`, y escribe ahí los integrantes, el caso elegido y los roles. Este enunciado se queda en el repositorio del curso. Los esqueletos de los entregables están en `curso/clase04/taller1/plantilla/`: para cada archivo, **Copy raw file** y, en `taller1/`, **Add file > Create new file** con el mismo nombre; pega y guarda con **Commit changes**.
5. Cada integrante trabaja en su propio Snowsight, con el rol `ACCOUNTADMIN` y el warehouse `COMPUTE_WH` del curso:

```sql
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
CREATE SCHEMA IF NOT EXISTS CURSO.T1;
USE SCHEMA CURSO.T1;
```

Los demás integrantes **no** reciben usuarios en el Snowflake del anfitrión. Los números finales se reportan desde la cuenta del anfitrión; el resto de las cuentas sirven para desarrollar y comprobar.

## 3. Los datos

La tabla `DAILY_ZONE_METRICS` es el resumen diario («gold») que produce el pipeline del curso a partir de los viajes de la TLC (Taxi and Limousine Commission, el regulador de taxis y plataformas de NYC). **Grano: fecha × zona × empresa.**

| Columna | Tipo | Qué es |
|---|---|---|
| `FECHA` | DATE | Día de recogida del viaje |
| `ZONA` | VARCHAR | **Nombre** de la zona de recogida (no el identificador `LocationID`) |
| `EMPRESA` | VARCHAR | Plataforma (Uber o Lyft) |
| `VIAJES` | NUMBER | Cantidad de viajes del grupo |
| `INGRESO_TOTAL` | FLOAT | Suma de lo que pagaron los pasajeros (tarifa base, peajes, cargos y propina), redondeada a 2 decimales |
| `PROPINA_PROMEDIO` | FLOAT | Promedio de propina por viaje del grupo, a 2 decimales |
| `DISTANCIA_PROMEDIO` | FLOAT | Promedio de distancia, en millas, a 2 decimales |
| `LLUVIA_MM` | FLOAT | Precipitación del día en milímetros (el máximo del día; igual en todas las filas del día) |

Dos filas reales de enero (las verás en tu tabla):

| FECHA | ZONA | EMPRESA | VIAJES | INGRESO_TOTAL | PROPINA_PROMEDIO | DISTANCIA_PROMEDIO | LLUVIA_MM |
|---|---|---|---|---|---|---|---|
| 2024-01-24 | JFK Airport | Lyft | 1965 | 153097.03 | 4.05 | 16.61 | 3.5 |
| 2024-01-24 | JFK Airport | Uber | 7265 | 602341.21 | 3.76 | 17.55 | 3.5 |

Volumen (control contra tu carga): enero, 15 909 filas y 19 650 023 viajes; febrero, 14 889 filas y 19 344 724 viajes; marzo, 15 917 filas y 21 273 719 viajes; en total, 46 715 filas y 60 268 466 viajes. El gold ya excluye los viajes con distancia, tarifa o duración fuera de rango (el pipeline los filtra en silver). Las empresas son Uber y Lyft en los tres meses. **No escribas «Uber» y «Lyft» a mano en una dimensión: constrúyela con `SELECT DISTINCT`.**

Dimensiones y tablas auxiliares:

- `DIM_ZONA` (de `datos/dim_zona.sql`, el `taxi_zone_lookup` de la TLC): `LOCATION_ID`, `BOROUGH`, `ZONA`, `SERVICE_ZONE`. 265 filas y 262 nombres de zona distintos.
- `FESTIVOS_2024` (de `datos/festivos_2024.sql`): festivos federales de 2024 (`FECHA`, `NOMBRE`), con fuente (OPM). 11 filas; de enero a marzo solo hay 3 (1 y 15 de enero y 19 de febrero), los tres lunes.
- `DIM_FECHA` y `DIM_EMPRESA`: las construye el equipo. Plantilla para generar los días con el rango del gold (ajusta el nombre de la tabla):

```sql
CREATE OR REPLACE TABLE DIM_FECHA AS
WITH r AS (SELECT MIN(FECHA) AS MINF, MAX(FECHA) AS MAXF FROM CURSO.LAB4.DAILY_ZONE_METRICS)
SELECT DATEADD('day', ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1, MINF) AS FECHA
FROM r, TABLE(GENERATOR(ROWCOUNT => 400))
QUALIFY FECHA <= MAXF;
```

Con los tres meses completos, la dimensión tiene 91 días (31 + 29 + 31; 2024 es bisiesto).

## 4. Cuatro trampas de los datos

Cada una produce un número que parece válido y está mal. Forman parte del aprendizaje: la rúbrica premia explicar una de ellas en el memo.

| Trampa | Qué pasa | Ejemplo real | Cómo evitarla y comprobarla |
|---|---|---|---|
| **1. La lluvia se repite** | `LLUVIA_MM` es la lluvia del día y está en todas las filas de ese día (entre 511 y 515 por día en enero). Sumarla o contar filas como días da cifras sin sentido. | 2024-01-10: 514 filas con 21.7 mm cada una. `SUM(LLUVIA_MM)` da 11 153.8; el día llovió 21.7 | Guarda la lluvia una vez por día en `DIM_FECHA` (`MAX(LLUVIA_MM)` agrupado por `FECHA`). Cuenta días con `COUNT(DISTINCT FECHA)`, no con `COUNT(*)` |
| **2. Promedios de grupos** | `PROPINA_PROMEDIO` y `DISTANCIA_PROMEDIO` son promedios de cada grupo. Promediarlos sin pesos trata igual a un grupo de 100 viajes y a uno de 10 000. | JFK, 2024-01-24: Lyft 4.05 con 1 965 viajes; Uber 3.76 con 7 265. Promedio simple 3.905; ponderado 3.82 | `SUM(PROPINA_PROMEDIO * VIAJES) / SUM(VIAJES)`. El gold ya redondeó cada promedio: el resultado es aproximado al centavo. Guarda las sumas en el hecho |
| **3. El redondeo** | Los importes están redondeados a 2 decimales y son FLOAT. Dos formas de sumar pueden diferir en el último dígito. | `0.1 + 0.2 = 0.3` da FALSE con FLOAT en Snowflake; con `ROUND(…, 2)` da TRUE | No compares con `=`. Usa `ROUND(x, 2)` o `ABS(a - b) < 0.01` |
| **4. El nombre de zona** | El gold identifica la zona por nombre. Si `DIM_ZONA` repite un nombre con dos `LOCATION_ID`, unir por nombre duplica filas del hecho y `SUM(VIAJES)` se infla. | 2 nombres repetidos en `DIM_ZONA`: Corona (LocationID 56 y 57) y Governor's Island/Ellis Island/Liberty Island (103 a 105); cada grupo comparte distrito y `SERVICE_ZONE`, así que `SELECT DISTINCT ZONA, BOROUGH, SERVICE_ZONE FROM DIM_ZONA` deja 262 filas únicas. Unir el gold por nombre agrega 196 filas y 184 265 viajes (0.3 %) | `SELECT ZONA, COUNT(*) FROM DIM_ZONA GROUP BY ZONA HAVING COUNT(*) > 1`. Decide cómo resolverlo (una fila por nombre) y deja la decisión en el memo. Cuenta las filas del hecho antes y después de unir; una zona del gold sin pareja en `DIM_ZONA` se busca con `LEFT JOIN … WHERE … IS NULL` |

Otra trampa para las ventanas: `LAG` mira la **fila** anterior, no el **día** anterior. Si una zona no tiene viajes algún día, esa fila no existe y la anterior queda más atrás. Para series diarias completa los días con `DIM_FECHA` (`LEFT JOIN` y `COALESCE(VIAJES, 0)`) antes de aplicar `LAG` o una media móvil con `ROWS`.

## 5. Los tres casos

Elige **un** caso: los tres tienen el mismo alcance técnico y la misma rúbrica. Cada uno tiene cinco preguntas: dos básicas y tres con ventana. Entre las cinco debes usar al menos `RANK` con `QUALIFY`, `LAG` y una agregación de ventana (`SUM` o `AVG` con `OVER`). El caso A es el recomendado para equipos con mayoría de perfil no técnico.

### Caso A · Competencia entre plataformas
Pregunta guía: **¿hay concentración en el mercado de viajes por zona y cómo evoluciona?** Usa solo `DAILY_ZONE_METRICS`.

| # | Pregunta | Técnica |
|---|---|---|
| A1 | Ingresos y viajes por empresa y mes | `GROUP BY` |
| A2 | Propina promedio por empresa, **ponderada** por viajes | `SUM / SUM` |
| A3 | Las tres zonas con más viajes de cada empresa | `RANK` y `QUALIFY` |
| A4 | Cuota de mercado de cada empresa en cada zona y mes | `SUM() OVER (PARTITION BY ZONA, MES)` |
| A5 | Variación mensual de la cuota y zonas donde una empresa pasa de 70 % | `LAG` |

### Caso B · Clima y festivos
Pregunta guía: **¿cuándo se dispara o se cae la demanda?** Usa `DAILY_ZONE_METRICS`, `DIM_FECHA` y `FESTIVOS_2024`.

| # | Pregunta | Técnica |
|---|---|---|
| B1 | Viajes por día con lluvia y sin lluvia, sin contar filas como días | `GROUP BY` sobre `DIM_FECHA` |
| B2 | Días con un salto de más de 50 % frente al día anterior | `LAG` |
| B3 | Media móvil de 7 días de viajes por zona | `AVG() OVER (... ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)` |
| B4 | Las tres zonas con más viajes por día de la semana | `RANK` y `QUALIFY` |
| B5 | Viajes en festivos frente al promedio del mismo día de la semana | `GROUP BY` con `FESTIVOS_2024` |

En B5, de enero a marzo solo hay 3 festivos (1 y 15 de enero y 19 de febrero, los tres lunes): la comparación tiene n = 3. Dilo en el memo.

### Caso C · Aeropuertos y distritos
Pregunta guía: **¿dónde se concentra el servicio y cómo se comparan los distritos?** Usa `DAILY_ZONE_METRICS` y `DIM_ZONA`. Las zonas de aeropuerto se identifican con `SERVICE_ZONE = 'Airports'`, que deja JFK y LaGuardia. Newark Airport tiene `SERVICE_ZONE = 'EWR'` y `BOROUGH = 'EWR'`: decide si lo cuentas como aeropuerto y deja la decisión en el memo. `BOROUGH` también incluye `Unknown` y `N/A`.

| # | Pregunta | Técnica |
|---|---|---|
| C1 | Viajes por distrito (`BOROUGH`) y mes | `GROUP BY` |
| C2 | Ranking de zonas dentro de cada distrito | `RANK() OVER (PARTITION BY BOROUGH ...)` |
| C3 | Propina promedio por distrito y empresa, **ponderada** | `SUM / SUM` |
| C4 | Media móvil de 7 días de las zonas de aeropuerto frente al resto | `AVG() OVER` |
| C5 | Participación de cada zona en su distrito y su cambio frente al mes anterior | `SUM() OVER` y `LAG` |

## 6. La estrella

- **Grano.** Escríbelo en una frase. Sugerido: «una fila por fecha, zona y empresa». Si agregas o cambias el grano, justifícalo.
- **Hecho.** Sugerido: `FACT_VIAJES_DIA` con las llaves de las dimensiones y medidas **aditivas**: `VIAJES`, `INGRESO_TOTAL` y las sumas que permiten rehacer los promedios (`PROPINA_PROMEDIO * VIAJES`, `DISTANCIA_PROMEDIO * VIAJES`). La lluvia no va en el hecho.
- **Dimensiones.** Al menos dos. Sugeridas: `DIM_FECHA` (fecha, año, mes, día de la semana, fin de semana, festivo y lluvia del día), `DIM_ZONA` (zona, distrito, tipo de zona) y `DIM_EMPRESA`.
- **Claves.** Declara cómo se une cada dimensión con el hecho y por qué esa clave es única en la dimensión.
- **Esquema.** Crea todo en `CURSO.T1` con estos nombres de tabla: `FACT_VIAJES_DIA`, `DIM_FECHA`, `DIM_ZONA` (puede ser una copia depurada de la del Lab 4) y `DIM_EMPRESA`.

## 7. Núcleo (todos los equipos)

1. Diagrama y DDL de la estrella (1 hecho y al menos 2 dimensiones), con el grano en una frase.
2. Carga reproducible desde el Lab 4 (`INSERT INTO ... SELECT` o `CREATE TABLE ... AS SELECT`), con un conteo de control igual al del paquete.
3. Las cinco preguntas de tu caso, cada una con un comentario que interprete el resultado.
4. Un chequeo de integridad por escrito: filas, grano único, sin huérfanos y viajes totales contra el origen.
5. Memo de una página con hallazgos, supuestos y **una trampa evitada** (la sección 4).
6. `costos.md` con los créditos usados y una captura del Query Profile de la consulta más pesada.

## 8. Entregables

Todo en la carpeta `taller1/` de la rama principal del fork del anfitrión.

| Archivo | Contenido | Formato |
|---|---|---|
| `01_estrella.sql` | DDL de hecho y dimensiones; el grano escrito como comentario en la primera línea | SQL |
| `diagrama.md` (o `diagrama.png`) | Diagrama de la estrella | Mermaid en Markdown, o imagen |
| `02_carga.sql` | Carga de hecho y dimensiones y el conteo de control | SQL |
| `03_preguntas.sql` | Las cinco preguntas del caso, cada una precedida por su enunciado y seguida del comentario con su interpretación | SQL |
| `04_chequeos.sql` | Los cuatro controles de la sección 15 | SQL |
| `memo.md` | Una página: hallazgos, supuestos, trampa evitada | Markdown, español claro |
| `costos.md` | Créditos usados y consulta más pesada, con `query_profile.png` | Markdown e imagen |
| `RETOS.md` | Qué retos se hicieron y dónde está cada uno | Markdown |
| `autoverificacion.txt` | Salida de `verificar_t1.sql` (Run All) | Texto |
| Coevaluación | Una por integrante, con el enlace que da el instructor | Formulario |

**Cómo subir archivos sin terminal.** En el fork del anfitrión: carpeta `taller1/` > **Add file > Create new file** (para texto) o **Upload files** (para imágenes) > **Commit changes**. Los colaboradores tienen permiso de escritura.

**Cómo medir los créditos y capturar el Query Profile.**

```sql
USE ROLE ACCOUNTADMIN;      -- rol administrador de tu cuenta de prueba: puede ver el consumo
USE WAREHOUSE COMPUTE_WH;   -- el cómputo que ejecuta la consulta
USE DATABASE CURSO;         -- INFORMATION_SCHEMA pertenece a una base: sin esta línea da
                            -- «Invalid identifier INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY»
SELECT ROUND(SUM(CREDITS_USED), 4) AS CREDITOS
FROM TABLE(INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY(
       DATE_RANGE_START => '2026-11-10'::DATE,
       WAREHOUSE_NAME => 'COMPUTE_WH'));
```

Alternativa sin base activa (tarda hasta 3 h en reflejar el consumo):

```sql
USE ROLE ACCOUNTADMIN;      -- único rol con acceso a SNOWFLAKE.ACCOUNT_USAGE en tu cuenta
USE WAREHOUSE COMPUTE_WH;
SELECT ROUND(SUM(CREDITS_USED), 4) AS CREDITOS
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE WAREHOUSE_NAME = 'COMPUTE_WH' AND START_TIME >= '2026-11-10'::DATE;
```

**Rol:** `ACCOUNTADMIN`. Leer el consumo de créditos exige el privilegio `MONITOR USAGE` (primera consulta) o acceso a la base `SNOWFLAKE` (alternativa); en tu cuenta de prueba los tiene `ACCOUNTADMIN`. Con otro rol, como `PUBLIC`, la consulta falla o devuelve vacío.


La fecha es el día de la clase; ajústala si mides otro día. Para el Query Profile (el desglose por operador de una consulta): Snowsight > **Monitoring > Query History** > abre tu consulta más pesada > pestaña **Query Profile** > captura de pantalla > guárdala como `query_profile.png`. Comenta en `costos.md` qué operador concentra el tiempo y qué harías. Referencia de presupuesto (estimación del pensum, no medida): hasta 0.3 créditos el Lab 4 y hasta 0.8 el taller en clase.

**Autoverificación.** Antes de entregar, el anfitrión corre `verificar_t1.sql` (en `curso/clase04/taller1/verificar_t1.sql` del repositorio del curso): **Copy raw file**, pégalo en una hoja nueva de Snowsight, **Run All**, y copia la tabla de resultados en `taller1/autoverificacion.txt`. Comprueba en `CURSO.T1` que el hecho `FACT_VIAJES_DIA` existe, que tiene 46 715 filas y 60 268 466 viajes, y que hay al menos dos tablas más (las dimensiones); no exige nombres de llaves ni de dimensiones. Salida esperada de una estrella correcta:

| CONTROL | RESULTADO | PISTA |
|---|---|---|
| hecho FACT_VIAJES_DIA | OK | Existe CURSO.T1.FACT_VIAJES_DIA |
| filas del hecho | OK | Tiene 46715 filas, como el paquete |
| viajes del hecho | OK | Suma 60268466 viajes, como el paquete |
| dimensiones | OK | Hay 3 tablas más en CURSO.T1 (las dimensiones) |
| lluvia fuera del hecho (aviso) | OK | La lluvia no está en el hecho |
| RESUMEN | OK | 4 de 4 controles en OK |

`PENDIENTE` quiere decir que todavía no existe lo que se comprueba; `REVISAR`, que existe y no coincide (la pista dice cuánto da); `AVISO` es informativo y no cuenta como error. No sustituye los cuatro chequeos de `04_chequeos.sql`: no mira el grano ni los huérfanos.

## 9. Cómo se entrega

1. Todos los archivos del núcleo en `taller1/`, en la rama principal del fork del anfitrión.
2. El anfitrión crea un **release** con la etiqueta `t1-entrega`: en GitHub, **Releases > Draft a new release > Choose a tag**, escribe `t1-entrega`, **Create new tag** y **Publish release**.
3. Cada integrante entrega su coevaluación.
4. Fecha límite: **domingo 15 de noviembre de 2026, 23:59 (hora de Colombia)**. Cuenta el release `t1-entrega` publicado antes de esa hora.

## 10. Roles

Cuatro roles que rotan en el Taller 2. Reparten responsabilidad; todos ejecutan SQL en su cuenta.

| Rol | Responde por |
|---|---|
| Analista | La pregunta del caso, las definiciones (por ejemplo, qué es un día con lluvia) y el memo |
| Modelador | La estrella y las consultas con ventanas |
| Ingeniero de datos | La carga y los chequeos |
| Calidad y costos | Los controles contra el origen, las trampas y `costos.md` |

Cada equipo tiene al menos una persona con perfil técnico (SQL o Python con nivel 2 o más) y como máximo dos con perfil no técnico. La evidencia individual es el historial de cambios (commits) del fork y la coevaluación (1 a 5 por criterio), que no puntúa aparte: solo puede ajustar hasta ±10 % la nota individual.

## 11. Trabajo en clase: hitos (95 minutos, desde las 2:15)

| Minuto del bloque (reloj de la clase) | Debe existir |
|---|---|
| Min 15 (2:30) | Caso elegido, roles asignados, colaboradores agregados al fork y el grano escrito en una frase |
| Min 35 (2:50) | Estrella creada y cargada en la cuenta del anfitrión; el conteo del hecho coincide con 46 715. Los demás integrantes la replican después corriendo `01_estrella.sql` y `02_carga.sql` del fork |
| Min 65 (3:20) | Preguntas 1 a 3 con consulta y resultado |
| Min 85 (3:40) | Preguntas 4 y 5 en borrador y los cuatro chequeos corriendo |
| Min 95 (3:50) | Todo subido al fork y los pendientes con responsable, antes de la entrega |

Fuera de clase se estiman hasta 3 horas de equipo.

## 12. Rúbrica

Núcleo: 85 puntos. Cada criterio tiene cuatro niveles: sobresaliente (100 % de los puntos del criterio), logrado (75 %), en proceso (40 %) y no logrado (0 %). Aprobar (60 o más) es posible solo con el núcleo.

| Criterio | Pts | Sobresaliente | Logrado | En proceso | No logrado |
|---|---|---|---|---|---|
| Datos cargados y reproducibles | 8 | Carga idempotente, conteos iguales al paquete, se puede volver a correr | Carga correcta, sin demostrar que se puede repetir | Carga parcial o conteos distintos sin explicar | No carga |
| Modelo estrella | 18 | Grano explícito, hecho y al menos 2 dimensiones, claves, DDL claro, diagrama | Estrella correcta con grano ambiguo | Tablas sin relación clara o grano mezclado | Sin modelo |
| Preguntas (corrección e interpretación) | 22 | 5 de 5 correctas con resultado interpretado | 4 de 5, o interpretación pobre | 2 o 3 de 5 | 1 o ninguna |
| Técnica SQL | 15 | Al menos 3 ventanas distintas bien elegidas y comentadas | 2 ventanas bien usadas | 1 ventana o uso incorrecto | Ninguna |
| Memo y comunicación | 9 | Claro; supuestos y trampa evitada explicados | Claro, faltan supuestos o la trampa | Confuso o técnico en exceso | Sin memo |
| Equipo (roles y aportes trazables) | 8 | Aportes balanceados y trazables | Aportes desiguales menores | Una persona hace casi todo | Sin evidencia |
| Costo y eficiencia | 5 | Créditos reportados, warehouse bien usado (XS, suspensión automática) y Query Profile comentado | Reportado sin análisis | Reporte incompleto | Sin reporte |
| **Núcleo** | **85** | | | | |
| Retos | hasta 15 | Según la sección 13 | | | |

## 13. Retos opcionales (hasta +15 puntos)

| Id | Reto | Pts |
|---|---|---|
| R1 | Un segundo caso completo (cinco preguntas más) | 3 |
| R2 | `DIM_FECHA` con festivos y fin de semana, usada en una consulta | 2 |
| R3 | Lluvia fuerte (más de 10 mm) frente a la línea base del mismo día de la semana (`AVG() OVER (PARTITION BY ZONA, DIA_SEMANA)`) | 3 |
| R4 | Suite de chequeos (grano, huérfanos, reconciliación con el conteo del paquete) en un solo archivo ejecutable | 3 |
| R5 | Rachas de alta demanda (días consecutivos sobre un umbral; el problema de «huecos e islas») | 3 |
| R6 | Tabla externa de Athena sobre el paquete (la del Lab 4, E7) y reconciliación de conteos con Snowflake: filas por mes y viajes totales, con captura de `Data scanned` | 3 |

Los puntos de los retos suman 17; el máximo que se acredita es 15.

## 14. Errores comunes

| Síntoma | Causa | Cómo evitarlo |
|---|---|---|
| `SUM(LLUVIA_MM)` da miles de milímetros | La lluvia del día está repetida en cada fila | Una vez por día en `DIM_FECHA` |
| El promedio de propina difiere del ponderado | Promediaste promedios | `SUM(PROMEDIO * VIAJES) / SUM(VIAJES)` |
| Después de unir con `DIM_ZONA`, `SUM(VIAJES)` es mayor | Un nombre de zona se repite en la dimensión | Una fila por nombre; cuenta antes y después de unir |
| `Window function ... appears outside of SELECT, QUALIFY, and ORDER BY clauses` | Escribiste una ventana en `WHERE` | Muévela a `QUALIFY` |
| `Object 'DAILY_ZONE_METRICS' does not exist` | Estás en `CURSO.T1` y la tabla está en `CURSO.LAB4` | Escribe `CURSO.LAB4.DAILY_ZONE_METRICS` |
| La media móvil de 7 días mira más de 7 días | `ROWS` cuenta filas, y faltan días en la serie | Completa los días con `DIM_FECHA` antes de la ventana |
| Tu compañero no ve tus tablas | Cada cuenta de Snowflake es independiente | Compartan los `.sql` en el fork y cada uno los corre |
| `Insufficient privileges` | El rol activo no es `ACCOUNTADMIN` | `USE ROLE ACCOUNTADMIN;` |
| `verificar_t1.sql` dice REVISAR en `filas del hecho` o `viajes del hecho` | Unión por un nombre de zona repetido, o carga hecha dos veces | Una fila por nombre en `DIM_ZONA`; `CREATE OR REPLACE TABLE` antes de cargar el hecho |
| `verificar_t1.sql` dice PENDIENTE en todo | El hecho no está en `CURSO.T1` con el nombre `FACT_VIAJES_DIA` o la hoja usa otra cuenta | Revisa el nombre, `USE SCHEMA CURSO.T1;` y que corres el archivo en la cuenta del anfitrión |
| El anfitrión no ve los cambios del colaborador | Falta el permiso de escritura o la invitación sin aceptar | Settings > Collaborators; aceptar la invitación |

## 15. Ejemplo de entrada y salida: los cuatro chequeos

Entrada (`04_chequeos.sql`, ajusta nombres):

```sql
SELECT 'filas' AS CONTROL, COUNT(*) AS HECHO, 46715 AS ESPERADO
FROM CURSO.T1.FACT_VIAJES_DIA
UNION ALL
SELECT 'grano', COUNT(DISTINCT FECHA || '|' || ZONA_KEY || '|' || EMPRESA_KEY), 46715
FROM CURSO.T1.FACT_VIAJES_DIA
UNION ALL
SELECT 'sin zona', COUNT(*), 0
FROM CURSO.T1.FACT_VIAJES_DIA F LEFT JOIN CURSO.T1.DIM_ZONA Z USING (ZONA_KEY)
WHERE Z.ZONA_KEY IS NULL
UNION ALL
SELECT 'viajes', SUM(VIAJES), 60268466
FROM CURSO.T1.FACT_VIAJES_DIA;
```

Salida esperada (cuatro filas, `HECHO` igual a `ESPERADO` en cada una):

| CONTROL | HECHO | ESPERADO |
|---|---|---|
| filas | 46 715 | 46 715 |
| grano | 46 715 | 46 715 |
| sin zona | 0 | 0 |
| viajes | 60 268 466 | 60 268 466 |

Si `filas` o `viajes` no coinciden, revisa la trampa 4; si `grano` es menor que `filas`, hay duplicados.
