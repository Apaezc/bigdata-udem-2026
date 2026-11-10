# Clase 4 · El lake y el Taller 1: cargar los viajes sin duplicarlos (mar 10 nov)

Orden de trabajo en clase. Procedimiento para llevar el código de GitHub a Snowsight (Copy raw file y pegar en una hoja): ver [`../clase01/cuentas.md`](../clase01/cuentas.md). El Lab 4 y el taller se hacen con GitHub y Snowsight, sin terminal; la excepción son los pasos 10 a 12 de la guía (sección 1), que usan la terminal del Code Editor. La única ayuda es el instructor. Datos: el paquete público de gold, `s3://bigdata-udem-2026-publico/paquete/gold/daily_zone_metrics/` (Parquet, 3 carpetas `mes=2024-01` a `mes=2024-03`, 6 archivos, 640.9 KiB; 46 715 filas y 60 268 466 viajes).

## 1. Pasos 10 a 12 de la guía (25 min)

Los comandos, las salidas esperadas y los errores comunes están en [`docs/guia.md`](../../docs/guia.md), pasos 10 a 12. Siempre `cd ~/bigdata` antes de cada `make`: fuera de esa carpeta aparece `No rule to make target`.

1. **Paso 10:** en la terminal del Code Editor, `cd ~/bigdata` y `make deploy`. Debes ver `Apply complete! Resources: 23 added` y, al final, `==> Deploy completado`. Crea el lake, la base de Glue `bigdata_lake` y el workgroup `bigdata-wg` de Athena.
2. **Paso 11:** `cd ~/bigdata` y `make snowflake`. Cuando veas `Enter a value:`, escribe `yes`. Debes ver `==> Conexión de AIRFLOW_SVC guardada en el secreto bigdata/snowflake.`
3. **Paso 12:** `cd ~/bigdata` y `make muestra`. La terminal se queda quieta varios minutos mientras Glue trabaja; no la cierres. Debes ver `==> Muestra lista en s3://bigdata-lake-<cuenta>-us-east-2/muestra.`

Sin los pasos 5 a 9 de la clase 3 no hay plan alternativo: quien viene atrasado termina primero el 10 y el 11.

## 2. Demo de Athena del instructor (8 min, slides 10 y 11)

Guion paso a paso, SQL exacto con la ruta real y errores comunes: [`athena_demo.sql`](athena_demo.sql). Se hace en la consola de AWS, región us-east-2 (Ohio), workgroup `bigdata-wg`. El instructor la ensaya antes en su cuenta (la política del bucket público permite leer desde cualquier cuenta de AWS; la prueba entre cuentas se hace en ese ensayo).

## 3. Lab 4 · Del bucket público a una tabla de Snowflake (esquema `CURSO.LAB4`, 32 min)

1. **Lab** ([`lab4.sql`](lab4.sql)): pégalo en una hoja. Paso 0: selecciona de `USE ROLE` a `USE SCHEMA CURSO.LAB4;` y pulsa ▶. Resuelve E1 a E6 (★) con Cmd/Ctrl+Enter, bloque a bloque; en E6 cargas `datos/dim_zona.sql` y `datos/festivos_2024.sql` en una hoja aparte. E7 (★★) repite la consulta en Athena, desde tu cuenta de AWS, y es opcional.
2. **Verificación** ([`lab4_verificacion.sql`](lab4_verificacion.sql)): otra hoja, **Run All**. Meta: RESUMEN = OK y "6 de 6 ★ en OK". PENDIENTE en E7 es normal.
3. **Solución** ([`lab4_solucion.sql`](lab4_solucion.sql)): después de intentarlo.

**Ejemplo de entrada y salida.** Entrada (E3, una sola vez):

```sql
COPY INTO DAILY_ZONE_METRICS FROM @LAKE_PUBLICO
  PATTERN = '.*[.]parquet' MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;
```

Salida: 6 filas `LOADED` (una por archivo; el orden varía) con 6692, 9217, 6282, 8607, 6635 y 9282 filas cargadas, 46 715 en total. Repetir exactamente la misma sentencia (E5) responde:

| status |
|---|
| Copy executed with 0 files processed. |

Resultado de la verificación con todo resuelto (E7 incluido):

| EJERCICIO | NIVEL | RESULTADO | PISTA |
|---|---|---|---|
| E1 | ★ | OK | Correcto |
| E2 | ★ | OK | Correcto |
| E3 | ★ | OK | Correcto |
| E4 | ★ | OK | Correcto |
| E5 | ★ | OK | Correcto |
| E6 | ★ | OK | Correcto |
| E7 | ★★ | OK | Correcto |
| RESUMEN | ★ | OK | 6 de 6 ★ en OK |

## 4. Taller 1 · Una estrella para la pregunta de la lluvia (entrega: domingo 15 de noviembre de 2026, 23:59, hora de Colombia)

Todo el enunciado está en [`taller1/README.md`](taller1/README.md): datos, cuatro trampas, tres casos, núcleo, entregables, rúbrica, retos y roles. Equipos de hasta 4 personas; entrega con el release `t1-entrega` del fork del anfitrión.

- **Esqueletos** ([`taller1/plantilla/`](taller1/plantilla/)): `01_estrella.sql`, `02_carga.sql`, `03_preguntas.sql`, `04_chequeos.sql`, `memo.md`, `costos.md`, `RETOS.md` y `diagrama.md`. Se copian a `taller1/` en el fork del anfitrión.
- **Autoverificación** ([`taller1/verificar_t1.sql`](taller1/verificar_t1.sql)): una hoja nueva en Snowsight, **Run All**; la salida va a `autoverificacion.txt`. Comprueba que `CURSO.T1.FACT_VIAJES_DIA` tiene 46 715 filas y 60 268 466 viajes y que hay al menos dos dimensiones.
- **Trabajo en clase:** 95 min desde las 2:15, con los hitos del enunciado (sección 11).

## 5. Demos del instructor

**Guion de demos** ([`demos.sql`](demos.sql)): una demo por consulta de las slides (4, 12, 14 a 20), con el número de slide y el resultado esperado de cada una. Las demos leen las tablas de `CURSO.LAB4`, que deja el Lab 4; solo crean objetos en `CURSO.DEMO4`. Para borrarlos: ver el final del archivo.

## Presentación

- **Presentación** ([`deck/slides.pdf`](deck/slides.pdf)): 26 slides, 240 min. Orden del día: apertura, pasos 10 a 12, el lake y la demo de Athena, Lab 4, descanso de 20 min, kickoff del Taller 1, trabajo en equipo de 95 min y cierre.

## Cómo reiniciar el Lab 4

El Paso 0 es idempotente: puedes correrlo más de una vez. Cada vista usa `CREATE OR REPLACE`, así que volver a correr un bloque la reemplaza. Para empezar de cero:

```sql
DROP SCHEMA IF EXISTS CURSO.LAB4;
```

y vuelve a correr el Paso 0 del lab. Recuerda que recrear la tabla `DAILY_ZONE_METRICS` borra la memoria del `COPY INTO`: el siguiente `COPY INTO` carga todo otra vez, una sola vez.

## Errores comunes

| Síntoma | Causa | Cómo evitarlo |
|---|---|---|
| `No rule to make target` en el paso 10, 11 o 12 | El comando se corrió fuera de la carpeta del repositorio | `cd ~/bigdata` y vuelve a correr el `make` |
| `Object 'LAKE_PUBLICO' does not exist` | No se corrió el Paso 0 en esa hoja, o falta el ejercicio 1 | Selecciona de `USE ROLE` a `USE SCHEMA CURSO.LAB4;` y pulsa ▶ |
| `LIST @LAKE_PUBLICO` devuelve 0 filas (`No data`) | La ruta de la URL del stage tiene un error de escritura | Copia la URL completa del paquete y vuelve a crear el stage |
| `Failure using stage area. Cause: [Access Denied (Status Code: 403 ...)]` | La URL apunta a un prefijo que no es público | Verifica la URL carácter por carácter |
| E1 da REVISAR aunque `LIST` funciona | La URL no es exactamente la del paquete (por ejemplo, sin la `/` final) | Copia la URL completa del paquete, con la `/` final |
| `PARQUET file format can produce one and only one column of type variant, object, or array` | Falta `MATCH_BY_COLUMN_NAME` en el `COPY INTO` | Añade `MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE` |
| El `COPY INTO` responde `0 files processed` la primera vez | El `PATTERN` no coincide con los nombres de los archivos | Usa `'.*[.]parquet'` |
| Las columnas de `EJ2` salen `NULL` | El nombre del campo lleva mayúsculas (`$1:Fecha`) | El campo va en minúsculas: `$1:fecha` |
| Las filas de E5 son el doble (93 430) | Segundo `COPY INTO` con `FORCE = TRUE`, o dos cargas tras recrear la tabla | `CREATE OR REPLACE TABLE` y un solo `COPY INTO` |
| `Missing column specification` al crear una vista | Una columna calculada sin `AS` | Pon `AS NOMBRE` en cada columna calculada |
| `EJ6` falla con `DIM_ZONA does not exist` | No se corrieron los archivos de `datos/` en el esquema `CURSO.LAB4` | Pega y corre `dim_zona.sql` y `festivos_2024.sql` con `USE SCHEMA CURSO.LAB4;` |
| `invalid identifier 'VIAJES'` al mirar `EJ2` | La vista todavía tiene el marcador `SELECT NULL AS PENDIENTE` | Escribe tu `SELECT` en el marcador y vuelve a crear la vista |
| La verificación dice PENDIENTE y sí escribiste tu `SELECT` | El `CREATE` falló | Busca el mensaje rojo en la hoja del lab |
| REVISAR con columnas distintas | El alias de salida no coincide | Compara `TUS_COLUMNAS` con `COLUMNAS_ESPERADAS` |
| Run All en el lab | Corre los ejemplos y los marcadores de todos los ejercicios | Usa Cmd/Ctrl+Enter bloque a bloque; Run All solo en la verificación |
| Athena: `Access Denied (Status Code: 403)` | La política del bucket público no permite listar o leer el prefijo, o la ruta no es exacta | Revisa la ruta `s3://bigdata-udem-2026-publico/paquete/gold/daily_zone_metrics/` y avisa al instructor |
| Athena: `SELECT COUNT(*)` da 0 tras crear la tabla | Faltan las particiones | `MSCK REPAIR TABLE bigdata_lake.gold_publico;` |
| Athena: la base o el workgroup no aparecen | Región distinta de us-east-2 o paso 10 sin terminar | Cambia la región a us-east-2; repite `make deploy` desde `~/bigdata` |
| Taller: `Object 'DAILY_ZONE_METRICS' does not exist` | Estás en `CURSO.T1` y la tabla está en `CURSO.LAB4` | Escribe `CURSO.LAB4.DAILY_ZONE_METRICS` |
| Taller: `SUM(VIAJES)` es mayor tras unir con `DIM_ZONA` | Un nombre de zona se repite en la dimensión | Una fila por nombre; cuenta antes y después de unir |
| No ves un archivo en tu fork | El fork no está al día | Sync fork > Update branch |
