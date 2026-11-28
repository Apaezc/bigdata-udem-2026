# Informe · Taller 2 · Equipo 4

**Pregunta:** en enero de 2024, ¿los viajes largos (5 millas o más) disminuyen más que los cortos (menos de 2 millas) los días con lluvia en NYC?

**Equipo:** Andrea Páez Cardona (anfitriona, Modeladora SQL) · Manuela Restrepo Céspedes (Operadora cloud y calidad) · Ana María Montealegre · Julián Olaya
**Entorno:** dev · **Mes:** 2024-01 · **Cómputo:** `glue_small` · **Límite:** `todos`
**Tabla del equipo:** gold `equipo_4_rango_distancia` → `BIGDATA.DEV.EQUIPO_4_RANGO_DISTANCIA`

---

## 1. La respuesta

**La hipótesis no se confirma: los días con lluvia los viajes no caen en ningún rango, suben, y suben más cuanto más corto es el viaje.**

En enero de 2024 hubo 17 días secos y 14 días con lluvia (lluvia del día ≥ 1,0 mm). Comparando viajes por día:

| Rango | Viajes/día seco | Viajes/día con lluvia | Cambio (R1) | Cambio ajustado por día de la semana (R2) |
|---|---|---|---|---|
| corto (< 2 mi) | 223 922 | 240 658 | **+7,5 %** | **+4,7 %** |
| medio (2 a < 5 mi) | 206 839 | 214 002 | +3,5 % | +1,0 % |
| largo (≥ 5 mi) | 191 455 | 193 366 | **+1,0 %** | **+0,7 %** |

La comparación general (R1) se calcula sobre promedios de viajes por día, no sobre totales, porque hay más días secos que lluviosos. La segunda comparación (R2) enfrenta cada día lluvioso con el promedio de los días secos **del mismo día de la semana**, para que un martes lluvioso no se compare con un sábado seco. R2 reduce el efecto —parte de la subida de R1 era que llovió en días de mucha demanda— pero apunta al mismo lado: con lluvia, los viajes cortos crecen entre cuatro y siete veces más que los largos.

**La lectura:** la lluvia no deprime la demanda de viajes, la desplaza hacia los trayectos que con buen tiempo se harían caminando. Lo que más crece son los viajes de menos de 2 millas; los de 5 millas o más casi no se mueven. Para la autoridad de movilidad, la presión de un día de lluvia no está en los trayectos entre barrios ni hacia aeropuertos, sino en los desplazamientos urbanos cortos.

**Qué no dice esta cifra.** Es un solo mes (14 días con lluvia, 17 secos) y no se controlan festivos, eventos ni temperatura. Los resultados son agregados sobre todos los viajes de silver y no separan Uber de Lyft, porque la tabla de gold no conserva `empresa` como dimensión. La conclusión queda limitada a enero de 2024.

Consultas: [`respuesta.sql`](respuesta.sql) (R1, R2 y la comprobación R3). Evidencia: [`evidencia/respuesta_R1.jpeg`](evidencia/respuesta_R1.jpeg), [`evidencia/respuesta_R2.jpeg`](evidencia/respuesta_R2.jpeg).

---

## 2. Conciliación resumida

| Capa | Cifra | Valor | Cuadra con |
|---|---|---|---|
| Crudo (archivo de la TLC) | filas | 19 663 930 | = cada lote de bronze |
| Descartes de silver | filas, 4 tipos | 13 907 (0,07 %) | crudo − descartes = silver |
| Silver `fhvhv` | filas | 19 650 023 | igual después de reprocesar |
| Gold equipo (Athena) | suma de `viajes` | 19 650 023 | = filas de silver · 93 filas |
| Gold casa (Athena) | suma de `viajes` | 19 650 023 | = filas de silver |
| Snowflake | `SUM(VIAJES)` | 19 650 023 | = gold · 93 filas · 31 días |

**Los tres cruces cuadran.**

- **Bronze → silver.** La diferencia está explicada fila por fila, con los descartes clasificados en cascada por la primera regla de `limpiar_viajes` que no cumplen: tarifa base ≤ 0 o nula 7 331, distancia ≤ 0 o nula 3 286, distancia ≥ 100 mi 1 660, duración fuera de 1–180 min 1 630. Suman 13 907 y 19 663 930 − 13 907 = 19 650 023. No hubo viajes sin hora de recogida, sin zona ni con recogida fuera del mes.
- **Silver → gold.** 19 650 023 filas de silver = 19 650 023 viajes sumados en gold, en 93 filas (31 días × 3 rangos). La tabla del equipo no filtra: todo viaje limpio cae en corto, medio o largo. Reparto: corto 7 175 895 (36,5 %), medio 6 512 281 (33,1 %), largo 5 961 847 (30,3 %).
- **Gold → Snowflake.** 93 filas y 19 650 023 viajes en `BIGDATA.DEV.EQUIPO_4_RANGO_DISTANCIA`, las mismas que escribió gold y las mismas que registró la tabla de control (en gold, `FILAS` cuenta grupos, no viajes).

Las tablas de referencia no crecieron al reprocesar: clima 31 filas (una por día) y taxi_zones 265 (una por zona). Por eso el cruce de `enriquecer` no multiplica viajes.

La tabla de control respalda los tres cruces desde el propio pipeline. Tomando el último registro por `(TABLA, CAPA, MES)` —y filtrando con `MES IN ('2024-01', 'sin_mes')`, porque las zonas no se registran con mes nulo sino con el texto `sin_mes`— quedan diez filas, todas con `glue_small` y `limite = todos`: bronze escribió 19 663 930 viajes, 31 días de clima y 265 zonas; silver escribió 19 650 023, 31 y 265; las dos tablas de gold leyeron 19 650 023 viajes y escribieron 93 y 744 grupos; y Snowflake recibió esas mismas 93 y 744 filas.

Consultas e interpretación de cada resultado: [`conciliacion.sql`](conciliacion.sql). Evidencia: [`evidencia/conciliacion_descartes.jpeg`](evidencia/conciliacion_descartes.jpeg), [`evidencia/conciliacion_silver_gold.jpeg`](evidencia/conciliacion_silver_gold.jpeg), [`evidencia/conciliacion_rangos.jpeg`](evidencia/conciliacion_rangos.jpeg), [`evidencia/snowflake_carga.jpeg`](evidencia/snowflake_carga.jpeg).

---

## 3. Costo

> **Falta un dato: los créditos de Snowflake (sección 3.1).** Los tiempos de Glue ya están medidos. La consulta que da los créditos está abajo; las cifras estimadas no cuentan, porque la rúbrica las califica como «en proceso».

### 3.1 Créditos de Snowflake

```sql
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE BIGDATA_WH;
SELECT TO_DATE(START_TIME) AS DIA, ROUND(SUM(CREDITS_USED), 4) AS CREDITOS
FROM TABLE(INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY(
       DATE_RANGE_START => '2026-11-24'::DATE,
       WAREHOUSE_NAME => 'BIGDATA_WH'))
GROUP BY DIA
ORDER BY DIA;
```

| Día | Warehouse | Tamaño | Créditos |
|---|---|---|---|
| 2026-11-\_\_ | BIGDATA_WH | X-Small | \_\_\_\_ |
| **Total del taller** | | | **\_\_\_\_** |

El warehouse es X-Small con suspensión automática a 60 segundos: se cobra por el tiempo encendido, con un mínimo de un minuto por encendido. Conviene correr las consultas seguidas en vez de una por una con pausas. Cuota del resource monitor: 60 créditos; no se amplió.

### 3.2 Tiempo de Glue

Las tres corridas completas del mes se hicieron con `glue_small` (2 workers G.1X), `limite = todos` y `mes = 2024-01`. Las duraciones son las que registró Airflow por tarea, tomadas de las capturas del DAG; la duración del job de Glue es algo menor, porque la tarea incluye el arranque del job y la espera.

| Corrida | Hora | Total | `correr_bronze` | `correr_silver` | `correr_gold` | `cargar_snowflake` |
|---|---|---|---|---|---|---|
| Código anterior, sin las funciones del equipo | 15:28 | 11:45 | 4:01 | 3:50 | 3:33 | 0:09 |
| 1.ª con el código del equipo | 16:07 | 12:26 | 3:50 | 5:21 | 2:48 | 0:09 |
| 2.ª, reproceso del mismo mes | 16:22 | **14:11** | 4:19 | **7:21** | 2:17 | 0:10 |

Las tres terminaron con las cuatro tareas en `success`. Dos cosas se leen en esos números, y las dos tienen explicación:

- **Silver se encareció al escribir `deduplicar`**, de 3:50 a 5:21. Era esperable: `dropDuplicates` por `_hash_fila` obliga a Spark a repartir las filas entre los workers para comparar huellas, y eso es trabajo que antes no se hacía. Es el precio de la garantía de no duplicar.
- **En el reproceso, silver subió a 7:21**, casi el doble de la primera corrida con el mismo código. También es esperable: silver lee **todos** los lotes de bronze, así que en la segunda corrida procesó 39 327 860 filas en vez de 19 663 930. El costo de reprocesar se concentra en silver, no en bronze ni en gold.

**No se corrió con `glue_medium`.** El enunciado pide esa comparación solo si se hicieron ambas, y el equipo decidió no hacerla: habría significado una cuarta corrida del mes completo, con el gasto de Glue que eso implica y, sobre todo, con un tercer lote en bronze que habría invalidado toda la evidencia de conciliación ya capturada. Lo que sí se puede afirmar con lo medido es que el cuello de botella no es el paralelismo sino el volumen que silver tiene que releer, y eso no lo arregla duplicar los workers.

### 3.3 Qué configuración elegiríamos para correrlo cada mes

`glue_small` (2 workers). Un mes de FHVHV son unos 19,7 millones de filas y cerca de 450 MB de Parquet, y `glue_small` lo procesa de punta a punta en unos 12 minutos. Pagar el doble de workers para recortar unos pocos minutos no se justifica en una carga mensual que corre desatendida de noche, y menos cuando el paso más pesado —silver— se encarece por la cantidad de lotes que relee, no por falta de paralelismo. `glue_medium` se reservaría para reprocesar varios meses de una vez, que es el caso donde el volumen sí crece de verdad.

Servicios que cuestan mientras están encendidos: el Code Editor y la VM de Airflow de prod. Glue y Snowflake solo cobran mientras ejecutan. Al cerrar cada sesión se apagó todo (`make airflow-off`, `make airflow-local-down`, `make estado`); evidencia en `evidencia/apagado/`.

---

## 4. Calidad de datos: cómo aseguramos que no llegaran duplicados de silver a gold

### 4.1 Qué hace `deduplicar` y por qué en ese orden

`agregar_metadatos`, en bronze, calcula `_hash_fila` **solo con las columnas originales**, antes de añadir las otras cuatro columnas de metadatos. Por eso dos ingestas del mismo archivo producen el mismo hash fila por fila: el hash no depende del lote ni de la fecha de ingesta. Ese es el único punto donde se decide si después se podrá reconocer una copia.

`deduplicar`, en silver, deja **una fila por `_hash_fila`** (`dropDuplicates(["_hash_fila"])`). No importa cuál de las repetidas se conserva: dos filas con el mismo hash tienen exactamente los mismos valores en las columnas originales. Si la tabla no trae `_hash_fila`, la devuelve igual, para no romperse con datos de bronze sin metadatos.

El orden importa dos veces:

1. **Limpiar y después deduplicar:** `deduplicar(limpiar_viajes(df, [mes]))`. Primero se descartan las filas que no cumplen las reglas y sobre lo que queda se eliminan las copias.
2. **Deduplicar las tres tablas de silver, no solo los viajes.** La casa aplica `deduplicar` a `fhvhv`, a `clima` y a `taxi_zones`. Es lo que evita el daño grande: `enriquecer` cruza los viajes con zonas y con clima en el paso gold, y si una tabla de referencia estuviera duplicada, cada viaje se multiplicaría por el número de copias. Con las tres deduplicadas, el cruce no multiplica.

### 4.2 Evidencia antes y después

| Situación | Lotes en bronze | Filas en silver | `_hash_fila` en silver |
|---|---|---|---|
| Código viejo, 1.ª corrida completa | 2 (uno de prueba) | 19 651 023 | ninguna (nula) |
| Código viejo, `reprocesar = true` | 3 | **39 301 046** | ninguna (nula) |
| Código del equipo, 1.ª corrida (tras resetear dev) | 1 | — | todas |
| Código del equipo, `reprocesar = true` | 2 | **19 650 023** | todas |

Con el código viejo, cada reproceso sumaba otra copia completa del mes: 2 × 19 650 023 + 1 000 del lote de prueba = 39 301 046. Con `agregar_metadatos` y `deduplicar` escritos, bronze guarda los dos lotes —bronze solo agrega, eso no cambia— pero silver se queda en 19 650 023. La prueba de que `deduplicar` funciona no es que bronze no crezca, sino que silver no herede ese crecimiento.

Las consultas que lo cierran:

```sql
-- Silver a gold: filas de silver contra suma de viajes de gold.
SELECT (SELECT COUNT(*)    FROM bigdata_lake.dev_silver_fhvhv WHERE mes = '2024-01') AS filas_silver,
       (SELECT SUM(viajes) FROM bigdata_lake.dev_gold_equipo_4_rango_distancia WHERE mes = '2024-01') AS viajes_gold;
-- Resultado: 19 650 023 = 19 650 023
```

Y en Snowflake, `SELECT COUNT(*), SUM(VIAJES) FROM BIGDATA.DEV.EQUIPO_4_RANGO_DISTANCIA;` → 93 filas y 19 650 023 viajes.

**La prueba más directa la da la tabla de control.** El registro de `silver / fhvhv` dice que silver **leyó 39 327 860 filas y escribió 19 650 023**, y las cuentas cierran exactas:

- 2 lotes de bronze × 19 663 930 = **39 327 860**, justo lo leído.
- Se eliminaron 19 663 930 por duplicadas (un lote entero) + 13 907 por los filtros = **19 677 837**.
- 39 327 860 − 19 677 837 = **19 650 023**, justo lo escrito.

Las otras dos tablas de silver muestran el mismo patrón: clima leyó 62 y escribió 31, taxi_zones leyó 530 y escribió 265. Las tres se deduplicaron, que es lo que impide que el cruce de `enriquecer` multiplique los viajes.

**La unicidad, medida de otra forma.** La prueba literal que pide la rúbrica es `COUNT(*)` contra `COUNT(DISTINCT _hash_fila)`, y en este entorno no se puede correr: el workgroup `bigdata-wg` corta toda consulta que lea más de 1 GB, y esa columna —64 caracteres hexadecimales por cada una de los 19,65 millones de filas— comprime poco y lo supera ella sola. El intento quedó documentado con su captura. En su lugar se midió la unicidad por las seis columnas de negocio, que es una prueba más estricta: como `_hash_fila` se calcula sobre todas las columnas originales, dos filas con el mismo hash serían idénticas también en esas seis.

```sql
SELECT count(*) AS grupos, sum(filas) AS filas_totales, max(filas) AS max_repeticiones
FROM (
  SELECT count(*) AS filas FROM bigdata_lake.dev_silver_fhvhv WHERE mes = '2024-01'
  GROUP BY pickup_datetime, dropoff_datetime, pu_location_id,
           do_location_id, distancia_mi, total_pagado
);
-- Resultado: 19 650 021 grupos · 19 650 023 filas · máximo 2 por grupo
```

**Las dos coincidencias, y qué límite revelan.** De 19 650 023 filas salieron 19 650 021 grupos: dos parejas coinciden en las seis columnas. Se inspeccionaron una por una. Las dos filas de cada pareja vienen **del mismo lote de bronze**, lo que descarta que sean copias del reproceso, y en el crudo difieren en la hora de solicitud —una de ellas también en la hora de llegada del conductor—, columnas que silver no conserva. Sus `_hash_fila` son por tanto distintos y `deduplicar` conservó ambas, que es el comportamiento especificado.

Con todas sus letras: coinciden en zonas, hora de recogida al segundo, hora de entrega, distancia, tarifa y pago al conductor, así que lo más probable es que sean el mismo viaje reportado dos veces por el proveedor con la hora de solicitud corregida. `deduplicar` garantiza que el pipeline no cree copias al reprocesar, y eso se cumple; no detecta casi-duplicados que ya venían en el archivo de la TLC, porque la huella es de la fila completa. Son 2 casos entre 19 650 023 viajes (0,00001 %) y no alteran ninguna cifra de la respuesta.

El detalle de las seis comprobaciones, con sus consultas, resultados y capturas, está en [`evidencia/verificaciones/README.md`](evidencia/verificaciones/README.md).

Evidencia: [`evidencia/antes_silver_duplicado.jpeg`](evidencia/antes_silver_duplicado.jpeg), [`evidencia/antes_reproceso_codigo_viejo_dag.jpeg`](evidencia/antes_reproceso_codigo_viejo_dag.jpeg), [`evidencia/despues_reproceso_silver.jpeg`](evidencia/despues_reproceso_silver.jpeg), [`evidencia/antes_bronze_lotes.jpeg`](evidencia/antes_bronze_lotes.jpeg), [`evidencia/reseteo_dev.jpeg`](evidencia/reseteo_dev.jpeg).

### 4.3 Qué pasó al reprocesar el mes

Corrimos 2024-01 dos veces con `reprocesar` marcado. Bronze guardó dos lotes de 19 663 930 filas cada uno (`20261127T210739Z_b0dc77` y `20261127T212312Z_3b2b7b`): idénticos, porque es el mismo archivo. Silver siguió en 19 650 023 filas y gold siguió sumando 19 650 023 viajes en 93 filas. La tabla de control conserva las dos corridas —reprocesar no borra nada— y la lectura se hace tomando el último registro por `(TABLA, CAPA, MES)`.

Un detalle que confunde: `COUNT(DISTINCT _id_lote)` en silver da **2**, y eso no es un duplicado. De cada par de copias, `deduplicar` conserva una cualquiera; unas quedaron del primer lote y otras del segundo. Lo que se comprueba es que las filas escritas sean la mitad de las leídas menos los descartes, como muestra la tabla de control.

Evidencia: [`evidencia/corrida1_dag.jpeg`](evidencia/corrida1_dag.jpeg), [`evidencia/corrida2_dag.jpeg`](evidencia/corrida2_dag.jpeg), [`evidencia/conciliacion_bronze_lotes.jpeg`](evidencia/conciliacion_bronze_lotes.jpeg).

### 4.4 La advertencia: contar filas de gold no detecta el problema

Gold agrupa por fecha y rango, así que **tiene las mismas 93 filas con duplicados y sin ellos**. Lo que se infla es la columna `viajes`. Por eso la comprobación es la **suma** de `viajes` contra las filas de silver, nunca el número de filas de gold. La señal de alarma es un múltiplo exacto: si los viajes de gold dan ×2 o ×4 las filas de silver, la deduplicación no está actuando.

### 4.5 Otras reglas de calidad aplicadas y qué detectaron

Las reglas de `limpiar_viajes`, contadas en cascada sobre el crudo de enero:

| Regla | Filas descartadas | Qué detectó |
|---|---|---|
| Tarifa base ≤ 0 o nula | 7 331 | Más de la mitad de los descartes: viajes registrados sin cobro válido |
| Distancia ≤ 0 o nula | 3 286 | Viajes con odómetro en cero o sin dato |
| Distancia ≥ 100 mi | 1 660 | Recorridos fuera del área metropolitana o errores de registro |
| Duración fuera de 1–180 min | 1 630 | Viajes instantáneos o abiertos durante horas |
| Sin hora de recogida | 0 | No detectó nada: la columna venía completa |
| Sin zona de recogida | 0 | No detectó nada: la columna venía completa |
| Recogida fuera del mes | 0 | No detectó nada: el archivo mensual no trae viajes de otros meses |
| **Total** | **13 907 (0,07 %)** | |

Además, `quality.validar` corre en cada tabla de silver: comprueba que la tabla no quede vacía, que las llaves no sean nulas (`pickup_datetime`, `pickup_date`, `pu_location_id`, `empresa` en viajes; `fecha` en clima; `LocationID` en zonas) y que `distancia_mi`, `tarifa_base` y `duracion_min` queden dentro de rango. No se detuvo ninguna corrida: el dato que pasó los filtros venía bien.

Regla propia de la tabla del equipo: `lluvia_mm` se agrega con `MAX`, nunca con `SUM`, porque la lluvia es del día y se repite en las tres filas de cada fecha. Si faltara el clima de un día, `lluvia_mm` queda nula y ese día se excluye de la comparación (`WHERE LLUVIA_MM IS NOT NULL`); en enero de 2024 no faltó ninguno: 31 días con clima, 0 filas sin lluvia.

Tres reglas que no detectaron nada también se reportan: dicen que el dato venía limpio en esas columnas, no que la regla sea innecesaria.

---

## 5. Pipeline y reproducibilidad

El DAG `pipeline_taxi` corrió completo en el Airflow del Code Editor de la cuenta de la anfitriona, en dev, con `computo = glue_small`, `limite = todos` y `mes = 2024-01`, y las cuatro tareas (`correr_bronze`, `correr_silver`, `correr_gold`, `cargar_snowflake`) terminaron en `success`. El cambio del equipo —`agregar_metadatos` en `bronze.py`, `deduplicar` en `silver.py`, `equipo_4_rango_distancia` en `gold.py` y `DDL_EQUIPO_4_RANGO_DISTANCIA` en `carga.py`— entró a `main` por el **pull request #4** (`Apaezc/t2-equipo-4`), con la aprobación de otro integrante y los cinco checks del CI en verde. En local, `make test` deja Ruff y la suite completa en verde —421 pruebas aprobadas y 1 omitida—, con las de `agregar_metadatos` y `deduplicar` en `OK`.

> **Dos capturas que faltan en `evidencia/`:** el PR #4 con los cinco checks en verde y la aprobación, y el job de Glue terminado en la consola de AWS. Si el PR #4 no quedó con aprobación o con algún check en rojo, hay que corregir la frase de arriba antes de entregar.

La tabla `BIGDATA.DEV.EQUIPO_4_RANGO_DISTANCIA` se creó a mano en Snowsight con el `CREATE TABLE` de `carga.py`, como exige el pipeline.
