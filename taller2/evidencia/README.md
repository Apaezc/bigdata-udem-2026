# Índice de evidencia · Taller 2 · Equipo 4

Qué prueba cada archivo de esta carpeta y a qué criterio de la rúbrica responde. Toda la evidencia sale de la cuenta de la anfitriona (Andrea Páez Cardona), entorno dev, mes 2024-01, cómputo `glue_small`, `limite = todos`.

## La secuencia del 27 de noviembre

Las corridas se hicieron en este orden, y entenderlo ayuda a leer las capturas:

| Hora | Qué pasó | Captura |
|---|---|---|
| 15:28 | Corrida completa con el código anterior, sin `agregar_metadatos` ni `deduplicar` | `antes_reproceso_codigo_viejo_dag.jpeg` |
| — | Estado del lago con ese código: bronze con 3 lotes, silver con 39 301 046 filas y sin huella | `antes_bronze_lotes.jpeg`, `antes_silver_duplicado.jpeg` |
| 16:02 | Reseteo de dev con el DAG `resetear_entorno` | `reseteo_dev.jpeg` |
| 16:07 | 1.ª corrida con el código del equipo | `corrida1_dag.jpeg` |
| 16:22 | 2.ª corrida, reproceso del mismo mes | `corrida2_dag.jpeg` |

## Criterio 4 · Pipeline en Glue desde Airflow

| Archivo | Qué muestra |
|---|---|
| `corrida1_dag.jpeg` | DAG `pipeline_taxi`, corrida de las 16:07, **Exitoso**, las cuatro tareas en `success`. Total 12:26 — bronze 3:50, silver 5:21, gold 2:48, Snowflake 0:09 |
| `corrida2_dag.jpeg` | La misma corrida repetida a las 16:22 con reproceso, **Exitoso**, cuatro tareas en `success`. Total 14:11 — bronze 4:19, silver 7:21, gold 2:17, Snowflake 0:10 |
| `antes_reproceso_codigo_viejo_dag.jpeg` | Corrida de las 15:28 con el código anterior, **Exitoso**, cuatro tareas en `success`. Total 11:45. Sirve de línea base para comparar el costo de deduplicar |
| `reseteo_dev.jpeg` | DAG `resetear_entorno` de las 16:02, **Exitoso**, sus seis tareas en `success` en 29 segundos |

## Criterio 5 · Conciliación y respuesta

| Archivo | Qué muestra |
|---|---|
| `conciliacion_descartes.jpeg` | Athena, descartes en cascada sobre el crudo: 19 650 023 pasan los filtros, y se descartan 3 286 por distancia, 1 660 por distancia ≥ 100 mi, 7 331 por tarifa base y 1 630 por duración |
| `conciliacion_silver_gold.jpeg` | Athena, el cruce completo en una consulta: `filas_silver` 19 650 023, `viajes_gold_equipo` 19 650 023, `filas_gold_equipo` 93 y `viajes_gold_casa` 19 650 023 |
| `conciliacion_rangos.jpeg` | Athena, viajes por rango en la tabla del equipo: corto 7 175 895, medio 6 512 281, largo 5 961 847, con 31 días cada uno |
| `snowflake_carga.jpeg` | Snowsight, la tabla cargada: 93 filas, 19 650 023 viajes, 31 días |
| `respuesta_R1.jpeg` | Snowsight, R1: 17 días secos y 14 con lluvia; corto +7,5 %, medio +3,5 %, largo +1,0 % |
| `respuesta_R2.jpeg` | Snowsight, R2, controlando por día de la semana: corto +4,7 %, medio +1,0 %, largo +0,7 % |
| `verificaciones/control_watermark.png` | Snowsight, la tabla de control: silver leyó 39 327 860 y escribió 19 650 023 |

## Criterio 6 · Costo y calidad de datos

| Archivo | Qué muestra |
|---|---|
| `antes_silver_duplicado.jpeg` | Athena, silver con el código anterior: 39 301 046 filas, 0 hashes distintos y 39 301 046 filas sin huella, porque `agregar_metadatos` todavía no estaba escrita |
| `antes_bronze_lotes.jpeg` | Athena, bronze con el código anterior: tres lotes, uno de prueba de 1 000 filas sin `_id_lote` y dos de 19 663 930 |
| `despues_reproceso_silver.jpeg` | Athena, silver con el código del equipo tras el reproceso: 19 650 023 filas, 2 lotes, 0 filas sin lote |
| `verificaciones/` | Las seis comprobaciones de cumplimiento, con su propio README: unicidad en silver, inspección de las dos parejas coincidentes, unicidad del grano de gold y la tabla de control |
| `costos/` | Créditos de Snowflake y tiempos de Glue |
| `apagado/` | Apagado de los servicios al terminar |

## Dos avisos sobre los nombres

- **`conciliacion_bronze_lotes.jpeg` no es lo que dice su nombre.** No muestra los lotes de bronze: es una consulta de Snowsight sobre `BIGDATA.DEV.EQUIPO_4_RANGO_DISTANCIA` que devuelve 93 filas, 19 650 023 viajes y 31 días. Es la misma consulta y el mismo resultado que `snowflake_carga.jpeg`, así que las dos capturas prueban lo mismo. Los lotes de bronze del estado final no tienen captura propia; su conteo está escrito y comentado en la PARTE 1.1 de `conciliacion.sql`, y la tabla de control los respalda.
- **`apagado/README.md.`** tiene un punto de más al final del nombre. Así GitHub no lo reconoce como markdown y lo muestra sin formato.
