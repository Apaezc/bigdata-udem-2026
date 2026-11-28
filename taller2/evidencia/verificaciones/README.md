# Verificaciones de cumplimiento · Taller 2 · Equipo 4

Comprobaciones hechas por la Analista de negocio y cumplimiento (Ana María Montealegre) para confirmar que lo prometido en `taller2/contrato.md` se cumple en los datos.

Todas se ejecutaron el 28/11/2026 en la cuenta de la anfitriona (Andrea Páez Cardona), entorno dev, mes 2024-01. Las de Athena, en la región Ohio (us-east-2), base `bigdata_lake`, workgroup `bigdata-wg`. Las de Snowflake, en Snowsight con el rol `BIGDATA_DEV`.

Cada entrada trae la consulta, su resultado y la interpretación. Dos llevan además captura: el intento que el workgroup canceló, porque es la única entrada que afirma que algo no se pudo medir, y la tabla de control, de donde sale la prueba central de la deduplicación.

| # | Qué comprueba | Criterio | Resultado |
|---|---|---|---|
| 1 | Unicidad por `_hash_fila` en silver | 6 | No medible: supera el tope de 1 GB del workgroup |
| 2 | Unicidad por las seis columnas de negocio | 6 | 19 650 021 grupos de 19 650 023 filas |
| 3 | Inspección de las dos parejas repetidas | 6 | Idénticas en silver y del mismo lote |
| 4 | Origen de las dos parejas, en el crudo | 6 | Difieren en la hora de solicitud: hashes distintos |
| 5 | Unicidad del grano de la tabla de gold | 5 | Sin duplicados |
| 6 | Tabla de control, las tres capas | 5 y 6 | Silver leyó 39 327 860 y escribió 19 650 023 |

---

## 1. Unicidad por `_hash_fila` en silver — no se pudo medir directamente

**Motor:** Athena · **Criterio:** 6 · **Captura:** `silver_hash_limite_excedido.png`

```sql
SELECT count(*) AS filas, count(DISTINCT "_hash_fila") AS hashes_distintos
FROM bigdata_lake.dev_silver_fhvhv
WHERE mes = '2024-01';
```

**Resultado:**

```
Cancelled · Bytes scanned limit was exceeded
Run time: 2.057 s · Data scanned: 1.00 GB
```

**Estado:** no ejecutable en este entorno. El workgroup `bigdata-wg` corta toda consulta que lea más de 1 GB, y `_hash_fila` son 64 caracteres hexadecimales por cada una de los 19,65 millones de filas: al ser texto de alta entropía comprime poco y la columna sola supera el tope. La unicidad se midió por las dos vías de las entradas 2 y 6.

---

## 2. Unicidad por las seis columnas de negocio en silver

**Motor:** Athena · **Criterio:** 6

```sql
SELECT count(*)    AS grupos,
       sum(filas)  AS filas_totales,
       max(filas)  AS max_repeticiones
FROM (
  SELECT count(*) AS filas
  FROM bigdata_lake.dev_silver_fhvhv
  WHERE mes = '2024-01'
  GROUP BY pickup_datetime, dropoff_datetime, pu_location_id,
           do_location_id, distancia_mi, total_pagado
);
```

**Resultado:**

```
grupos            19 650 021
filas_totales     19 650 023
max_repeticiones  2
```

**Estado:** equivale a la prueba del hash y es más estricta. `_hash_fila` se calcula sobre todas las columnas originales de la fila: dos filas con el mismo hash serían idénticas también en estas seis. Por tanto, si estas seis no se repiten, es imposible que haya hashes repetidos.

De 19 650 023 filas salen 19 650 021 grupos, con un máximo de 2 por grupo: solo dos parejas coinciden en las seis columnas, y se inspeccionaron en las entradas 3 y 4.

---

## 3. Inspección de las dos parejas, en silver

**Motor:** Athena · **Criterio:** 6

```sql
SELECT pickup_datetime, pu_location_id, empresa, duracion_min, tarifa_base,
       propina, pago_conductor, "_id_lote"
FROM bigdata_lake.dev_silver_fhvhv
WHERE mes = '2024-01'
  AND pickup_datetime IN (TIMESTAMP '2024-01-31 23:44:51',
                          TIMESTAMP '2024-01-21 21:40:23')
ORDER BY pickup_datetime;
```

Se pidió por hora de recogida, así que devuelve los 23 viajes que arrancaron en esos dos segundos en toda la ciudad. Las parejas son las que además coinciden en zona:

```
2024-01-21 21:40:23 · PU 75  · Uber · 7,3167 min · 7,36 · 0,00 · 2,71 · lote 20261127T212312Z_3b2b7b
2024-01-21 21:40:23 · PU 75  · Uber · 7,3167 min · 7,36 · 0,00 · 2,71 · lote 20261127T212312Z_3b2b7b

2024-01-31 23:44:51 · PU 197 · Uber · 7,45 min   · 6,28 · 0,00 · 2,91 · lote 20261127T210739Z_b0dc77
2024-01-31 23:44:51 · PU 197 · Uber · 7,45 min   · 6,28 · 0,00 · 2,91 · lote 20261127T210739Z_b0dc77
```

**Estado:** idénticas en todas las columnas que silver conserva **y las dos de cada pareja vienen del mismo lote de bronze**. Eso descarta que sean copias del reproceso: si lo fueran, cada una estaría en un lote distinto. Ya estaban, por duplicado aparente, dentro de una sola copia del archivo de la TLC. Se buscó la diferencia en el crudo (entrada 4).

---

## 4. Origen de las dos parejas, en el crudo

**Motor:** Athena · **Criterio:** 6

```sql
SELECT pickup_datetime, pulocationid, dolocationid,
       request_datetime, on_scene_datetime,
       dispatching_base_num, originating_base_num, hvfhs_license_num
FROM bigdata_lake.dev_crudo_fhvhv
WHERE mes = '2024-01'
  AND ((pickup_datetime = TIMESTAMP '2024-01-21 21:40:23' AND pulocationid = 75)
    OR (pickup_datetime = TIMESTAMP '2024-01-31 23:44:51' AND pulocationid = 197));
```

**Resultado (4 filas, 59,94 MB leídos):**

| Recogida | PU → DO | Solicitud | Llegada del conductor | Base | Licencia |
|---|---|---|---|---|---|
| 2024-01-31 23:44:51 | 197 → 197 | 23:39:34 | 23:43:27 | B03404 | HV0003 |
| 2024-01-31 23:44:51 | 197 → 197 | 23:40:50 | 23:43:27 | B03404 | HV0003 |
| 2024-01-21 21:40:23 | 75 → 74 | 21:34:35 | 21:39:36 | B03404 | HV0003 |
| 2024-01-21 21:40:23 | 75 → 74 | 21:34:18 | 21:40:23 | B03404 | HV0003 |

**Estado:** las dos filas de cada pareja difieren en la hora de solicitud, y las de la segunda también en la hora de llegada del conductor. Silver no conserva ninguna de esas dos columnas, pero `_hash_fila` se calcula sobre la fila original completa: por eso sus huellas son distintas y `deduplicar` conservó ambas, que es el comportamiento especificado.

Conviene nombrar el límite que esto revela. Coinciden en zonas, hora de recogida al segundo, hora de entrega, distancia, tarifa y pago al conductor: lo más probable es que sean el mismo viaje reportado dos veces por el proveedor, con la hora de solicitud corregida. `deduplicar` garantiza que **el pipeline** no cree copias al reprocesar, y eso se cumple; no está diseñado para detectar casi-duplicados que ya venían en el archivo de la TLC, porque la huella es de la fila completa. Son 2 casos entre 19 650 023 viajes (0,00001 %) y no alteran ninguna cifra de la respuesta.

---

## 5. Unicidad del grano de la tabla de gold del equipo

**Motor:** Athena · **Criterio:** 5

Lo promete el contrato, sección 5: «Comprobar que no existan duplicados en la granularidad `fecha` y `rango_distancia`».

```sql
SELECT fecha, rango_distancia, count(*) AS veces
FROM bigdata_lake.dev_gold_equipo_4_rango_distancia
WHERE mes = '2024-01'
GROUP BY fecha, rango_distancia
HAVING count(*) > 1;
```

**Resultado:** sin filas (0,34 KB leídos).

**Estado:** el grano declarado en el contrato se cumple. Cada combinación de fecha y rango aparece una sola vez: 93 filas, 31 días × 3 rangos.

---

## 6. Tabla de control: último registro por capa

**Motor:** Snowflake (Snowsight) · **Criterio:** 5 y 6 · **Captura:** `control_watermark.png`

El filtro va con `MES IN ('2024-01', 'sin_mes')` y no con `MES IS NULL`: las zonas se registran con el texto `sin_mes`, así que con el filtro de nulos esa fila no aparece.

```sql
USE ROLE BIGDATA_DEV;
USE WAREHOUSE BIGDATA_WH;
USE DATABASE BIGDATA;

SELECT TABLA, CAPA, MES, FILAS, LEIDAS, COMPUTO, LIMITE, REPROCESAR, INICIO
FROM BIGDATA.CONTROL_DEV.WATERMARK
WHERE MES IN ('2024-01', 'sin_mes')
QUALIFY ROW_NUMBER() OVER (PARTITION BY TABLA, CAPA, MES ORDER BY INICIO DESC) = 1
ORDER BY CAPA, TABLA;
```

**Resultado (10 filas, todas con `glue_small`, `limite = todos`, `reprocesar = TRUE`):**

| Tabla | Capa | Mes | Filas | Leídas |
|---|---|---|---|---|
| clima | bronze | 2024-01 | 31 | 31 |
| fhvhv | bronze | 2024-01 | 19 663 930 | 19 663 930 |
| taxi_zones | bronze | sin_mes | 265 | 265 |
| equipo_4_rango_distancia | gold | 2024-01 | 93 | 19 650 023 |
| tarifa_por_milla_barrio | gold | 2024-01 | 744 | 19 650 023 |
| clima | silver | 2024-01 | 31 | 62 |
| fhvhv | silver | 2024-01 | 19 650 023 | 39 327 860 |
| taxi_zones | silver | sin_mes | 265 | 530 |
| equipo_4_rango_distancia | snowflake | 2024-01 | 93 | 93 |
| tarifa_por_milla_barrio | snowflake | 2024-01 | 744 | 744 |

**Estado:** es la prueba más directa de que `deduplicar` actuó, y la da el propio pipeline sin depender del tope de lectura de Athena.

La fila de **silver / fhvhv** dice que silver leyó 39 327 860 filas y escribió 19 650 023. Las cuentas cierran exactas:

- 2 lotes de bronze × 19 663 930 = **39 327 860**, justo lo leído.
- Se eliminaron 19 663 930 por duplicadas (un lote entero) + 13 907 por los filtros de calidad = **19 677 837**.
- 39 327 860 − 19 677 837 = **19 650 023**, justo lo escrito.

Las otras dos tablas de silver muestran el mismo patrón: clima leyó 62 y escribió 31; taxi_zones leyó 530 y escribió 265. Las tres se deduplicaron, que es lo que impide que el cruce de `enriquecer` multiplique los viajes en gold.

De ahí en adelante no se pierde ni se duplica nada: las dos tablas de gold leyeron 19 650 023 viajes y escribieron 93 y 744 grupos, y Snowflake recibió exactamente esas 93 y 744 filas.
