# Herramientas de la casa

Funciones que ya están escritas y probadas para que las uses en tus talleres sin reescribirlas. Cada una se importa desde el archivo donde vive (por ejemplo `pipeline.herramientas.capas`, que es `src/pipeline/herramientas/capas.py`), para que siempre sepas de dónde viene:

```python
from pipeline.herramientas.capas import leer_crudo
from pipeline.herramientas.control import mes_ya_procesado, registrar_control
```

Cada función que lee, escribe, consulta o borra **dice en voz alta dónde** (`LEE`, `ESCRIBE`, `CONSULTA`, `REGISTRA`, `CREA`, `CARGA`, `BORRA`) con la ruta completa. En un notebook sale en la celda; en Airflow o Glue, en el log de la tarea.

## Índice

- [La frontera: qué es de la casa y qué es tuyo](#frontera)
- [Las 12 funciones](#las-12)
- [Traer el crudo](#crudo): `traer_crudo_viajes`, `traer_crudo_taxi_zones`, `traer_crudo_clima`
- [Leer y escribir el lake](#lake): `leer_crudo`, `escribir_bronze`, `leer_capa`, `escribir_capa`
- [La huella de una fila](#hash): `hash_fila` y `COLUMNAS_METADATOS`
- [La tabla de control](#control): `mes_ya_procesado`, `registrar_control`
- [Snowflake](#snowflake): `cargar_gold`
- [Los pasos como funciones](#pasos): `correr_bronze`, `correr_silver`, `correr_gold`, `cargar_snowflake`
- [Probar tus funciones desde un notebook](#notebook): `usar_mis_funciones`, `probar_mis_funciones`

<a id="frontera"></a>
## La frontera: qué es de la casa y qué es tuyo

| De la casa (no se edita) | Del equipo (lo que sí escribes) |
|---|---|
| `src/pipeline/herramientas/` (esta página), `quality.py`, `engine.py`, `correr.py`, `run.py` | `agregar_metadatos` (en `bronze.py`) |
| Los `main` de los cuatro pasos y `limpiar_viajes`, `clima_diario`, `limpiar_taxi_zones` y `enriquecer` | `deduplicar` (en `silver.py`) y las tablas resumen que quieras |
| `debe_ingestar` y `registrar_ingesta` (en `bronze.py`, ya resueltas) | Tus tablas de gold: una función en `gold.py`, sumada a `TABLAS_GOLD` |
| El ejemplo de gold, `tarifa_por_milla_por_barrio`, y su `CREATE TABLE` | El `CREATE TABLE` de tu gold en `carga.py`, sumado a `TABLAS_A_CARGAR` |
| `pipeline.yaml`, el DAG `pipeline_taxi` y el DAG `resetear_entorno` | Nada más: las pruebas de `agregar_metadatos` y `deduplicar` ya están en `tests/test_equipo_*.py`. |

Tres reglas de la caja: los equipos importan con el nombre del archivo (`from pipeline.herramientas.<archivo> import ...`), nunca desde `pipeline.herramientas` a secas; la caja nunca importa `bronze.py`, `silver.py`, `gold.py` ni `carga.py` (así no hay ciclos); y todo lo que toca el lake dice en voz alta dónde.

<a id="las-12"></a>
## Las 12 funciones

| Función | Qué hace | Va con | Se importa de |
|---|---|---|---|
| `traer_crudo_viajes(entorno, mes)` | Deja el Parquet de viajes del mes en `_crudo/` y devuelve su ruta | Bronze | `pipeline.herramientas.crudo` (`crudo.py`) |
| `traer_crudo_taxi_zones(entorno)` | Deja el CSV de zonas en `_crudo/` | Bronze | `pipeline.herramientas.crudo` (`crudo.py`) |
| `traer_crudo_clima(entorno, mes)` | Deja el JSON de clima del mes en `_crudo/` | Bronze | `pipeline.herramientas.crudo` (`crudo.py`) |
| `leer_crudo(spark, entorno, tabla, mes=None, limite=None)` | Lee el crudo como DataFrame, con límite determinista | Bronze | `pipeline.herramientas.capas` (`capas.py`) |
| `escribir_bronze(df, entorno, tabla, mes, id_lote)` | Escribe un lote nuevo en bronze y devuelve las filas escritas | Bronze | `pipeline.herramientas.capas` (`capas.py`) |
| `hash_fila(columnas)` | La huella (SHA-256) de la fila completa, como columna de Spark | Bronze y silver | `pipeline.herramientas.capas` (`capas.py`) |
| `mes_ya_procesado(corrida, tabla, capa, mes)` | La puerta: `True` = se salta | Todos los pasos | `pipeline.herramientas.control` (`control.py`) |
| `registrar_control(corrida, tabla, capa, mes, filas, inicio, fuente, leidas=None)` | Anota que el paso terminó bien | Todos los pasos | `pipeline.herramientas.control` (`control.py`) |
| `leer_capa(spark, entorno, capa, tabla, mes=None, lotes="todos")` | Lee bronze, silver o gold | Silver y gold | `pipeline.herramientas.capas` (`capas.py`) |
| `escribir_capa(df, entorno, capa, tabla, mes=None)` | Escribe silver o gold reemplazando el mes | Silver y gold | `pipeline.herramientas.capas` (`capas.py`) |
| `cargar_gold(tabla_snowflake, carpeta_gold, mes=None, ...)` | Carga gold desde S3 a una tabla de Snowflake | Snowflake | `pipeline.herramientas.bodega` (`bodega.py`) |

`COLUMNAS_METADATOS` es la lista de las cinco columnas que bronze agrega (también de `pipeline.herramientas.capas`). El resto de lo que hay en `src/pipeline/herramientas/` es importable pero no se enseña.

Todas las funciones que llevan `entorno` o `corrida` toman el entorno **de la corrida**: desde el Code Editor siempre es `dev`. No hay un argumento para cambiarlo.

<a id="crudo"></a>
## Traer el crudo

```python
from pipeline.herramientas.crudo import (
    traer_crudo_clima,
    traer_crudo_taxi_zones,
    traer_crudo_viajes,
)

ruta_viajes = traer_crudo_viajes("dev", "2024-01")
ruta_zonas = traer_crudo_taxi_zones("dev")
ruta_clima = traer_crudo_clima("dev", "2024-01")
```

Cada función devuelve la ruta `s3://` completa donde quedó el archivo, y antes de bajar nada revisa, en este orden:

1. **¿Ya está en `_crudo/`?** No se descarga. Ahorra los ~450 MB de viajes del mes.
2. **¿Está en la ruta del diseño anterior** (sin `_crudo/`)? Se mueve a `_crudo/`.
3. Si no está en ninguna parte, se descarga de la fuente.

**Debes ver** una línea `YA ESTÁ` (o la descarga) por archivo, con la ruta completa bajo `s3://<tu-bucket>/dev/bronze/_crudo/`.

<a id="lake"></a>
## Leer y escribir el lake

**`leer_crudo`** devuelve un DataFrame del archivo tal como se descargó: los viajes en Parquet, las zonas en un CSV leído todo como texto y el clima en una fila por día. `limite` es el número de filas (`corrida.limite_filas`) o `None` para todo. El límite es **determinista**: `coalesce(1).limit(n)` toma siempre las mismas `n` primeras filas del archivo, así que reprocesar el mismo mes da las mismas filas y se puede comprobar la deduplicación.

```python
from pipeline.herramientas.capas import leer_crudo  # src/pipeline/herramientas/capas.py

viajes = leer_crudo(spark, "dev", "fhvhv", "2024-01", limite=1000)
```

**`escribir_bronze`** escribe un **lote nuevo** (`lote=<id>/`, más un marcador `_LOTE_COMPLETO` al final) y devuelve las filas que quedaron escritas, contadas leyendo de vuelta. Bronze solo agrega: nunca borra los lotes anteriores. Un lote sin marcador quedó a medias y nadie lo lee.

**`leer_capa`** lee una tabla de una capa. En bronze, `lotes="todos"` junta **todos** los lotes completos del mes y `lotes="ultimo"` lee solo el más reciente. En silver y gold lee la carpeta del mes.

```python
from pipeline.herramientas.capas import leer_capa  # src/pipeline/herramientas/capas.py

bronze = leer_capa(spark, "dev", "bronze", "fhvhv", "2024-01")  # todos los lotes
silver = leer_capa(spark, "dev", "silver", "fhvhv", "2024-01")
```

**`escribir_capa`** escribe silver o gold **reemplazando el mes**: borra `mes=<mes>/` y escribe de nuevo, para que un reproceso con menos filas no deje filas viejas mezcladas. Devuelve las filas escritas. Con `capa="bronze"` falla: bronze se escribe con `escribir_bronze`.

```python
from pipeline.herramientas.capas import escribir_capa  # src/pipeline/herramientas/capas.py

filas = escribir_capa(gold, "dev", "gold", "mi_tabla", "2024-01")
```

Resumen de las reglas de cada capa:

| Capa | Regla | Quién la cumple |
|---|---|---|
| bronze | Solo agrega: cada ingesta es un lote nuevo | `escribir_bronze` |
| silver | Reemplaza el mes y es el espejo de la fuente, sin duplicados | `escribir_capa` y `deduplicar` (tuya) |
| gold | Reemplaza el mes | `escribir_capa` |

<a id="hash"></a>
## La huella de una fila

```python
from pipeline.herramientas.capas import COLUMNAS_METADATOS, hash_fila

print(COLUMNAS_METADATOS)
# ['_fecha_ingesta', '_id_lote', '_hash_fila', '_fuente', '_archivo_origen']

df = df.withColumn("_hash_fila", hash_fila(["letra", "numero"]))
```

`hash_fila(columnas)` devuelve una **columna** de Spark con el SHA-256 de esos valores. Cada columna se convierte a texto, el nulo se reemplaza por una marca (así un nulo no se confunde con un texto vacío) y los textos se unen con `||`. Dos filas con los mismos valores dan la misma huella; si cambia un solo valor, cambia. No depende del lote: por eso un reproceso del mismo archivo se puede deduplicar.

`COLUMNAS_METADATOS` es el orden en que `agregar_metadatos` (la función que escribes en `bronze.py`) debe dejar las cinco columnas nuevas, después de las originales.

<a id="control"></a>
## La tabla de control

Es una tabla de Snowflake por entorno: `BIGDATA.CONTROL_DEV.WATERMARK` y `BIGDATA.CONTROL_PROD.WATERMARK`. Cada paso que termina bien anota una fila; antes de trabajar, el paso pregunta si el mes ya está. La clave de consulta es `(TABLA, CAPA, MES)`, y la regla es una sola:

| ¿Hay registro? | `reprocesar` | Resultado |
|---|---|---|
| No | `false` | Se ingesta |
| Sí | `false` | **Se salta**, sea cual sea el número de filas, el cómputo o el límite del registro |
| (da igual) | `true` | Se ingesta siempre (reprocesar es pedirlo a propósito) |

```python
from datetime import UTC, datetime

from pipeline.herramientas.control import mes_ya_procesado, registrar_control

if mes_ya_procesado(corrida, "fhvhv", "bronze", "2024-01"):
    print("se salta")
else:
    inicio = datetime.now(UTC).replace(microsecond=0)
    # ... trabajo ...
    registrar_control(corrida, "fhvhv", "bronze", "2024-01", filas, inicio, fuente, leidas)
```

- **`mes_ya_procesado`** devuelve `True` si **se salta**. Con `reprocesar=true` ni siquiera consulta.
- **`registrar_control`** se llama **solo después de escribir**: si el trabajo falla no queda registro y el mes se puede reintentar. `filas` son las **escritas**; `leidas` es solo informativa. Reprocesar no borra nada: cada corrida deja su fila.

Columnas de la tabla, en orden: `FUENTE`, `CAPA`, `TABLA` (sin prefijo de entorno: `fhvhv`, `taxi_zones`, `clima`, o el nombre de tu gold), `MES` (`AAAA-MM` o `sin_mes` para las zonas), `FILAS`, `INICIO`, `REPROCESAR`, `COMPUTO`, `LIMITE` y `LEIDAS`. Las tres últimas se guardan solo para informar: la puerta no las mira.

Quien tenga el rol `BIGDATA_DEV` consulta y escribe `CONTROL_DEV` y puede **leer** `CONTROL_PROD`, pero no escribirlo. Se conectan con el secreto de Secrets Manager, nunca con `connections.toml` (que usa `ACCOUNTADMIN`).

Para la conciliación (qué anotó el pipeline y si cuadra con lo que ves en Athena y Snowflake), mira siempre el **último registro por tabla, capa y mes**:

```sql
USE ROLE BIGDATA_DEV;
USE WAREHOUSE BIGDATA_WH;
USE DATABASE BIGDATA;

SELECT TABLA, CAPA, MES, FILAS, LEIDAS, COMPUTO, INICIO
FROM BIGDATA.CONTROL_DEV.WATERMARK
QUALIFY ROW_NUMBER() OVER (PARTITION BY TABLA, CAPA, MES ORDER BY INICIO DESC) = 1
ORDER BY CAPA, TABLA, MES;
```

En gold, `FILAS` cuenta filas de gold (una por fecha, barrio y franja, en el ejemplo de la casa), no viajes: los viajes se comparan con `SUM(VIAJES)`.

<a id="snowflake"></a>
## Snowflake

**El rol y el warehouse se dicen siempre.** `ACCOUNTADMIN` no tiene permisos sobre los objetos de `BIGDATA.DEV` y el `CREATE TABLE` falla. Todo SQL de talleres empieza con:

```sql
USE ROLE BIGDATA_DEV;
USE WAREHOUSE BIGDATA_WH;
USE DATABASE BIGDATA;
```

**La tabla la creas tú, a mano, en Snowsight.** El código nunca crea tablas. Si la tabla no existe, `cargar_gold` (y por tanto `cargar_snowflake`) se detiene sin tocar nada y el error imprime el SQL exacto que debes ejecutar, empezando por el rol, el warehouse y la base. Lo ejecutas en Snowsight y vuelves a correr `cargar_snowflake`. Con `IF NOT EXISTS`, repetirlo no hace daño. Ojo: `resetear_entorno` con `borrar dev` también borra las tablas de `BIGDATA.DEV`, así que después de cada reseteo hay que ejecutar el `CREATE TABLE` otra vez.

**`cargar_gold(tabla_snowflake, carpeta_gold, mes=None, ...)`** lleva los Parquet de gold (S3) a una tabla de Snowflake. Es la misma que usa el paso `snowflake` del pipeline (el DAG, `make correr PASO=snowflake` y el notebook), así que en todos lados se comporta igual. Se llamaba `cargar_gold_a_snowflake` en las clases anteriores; el nombre viejo sigue valiendo.

Qué hace, en este orden:

1. Lee las columnas y tipos de los Parquet en S3 y las columnas de tu tabla, y las compara. Si no coinciden, se detiene con un error y no toca la tabla.
2. Copia los Parquet a una tabla temporal. Si el `COPY` falla, tu tabla queda como estaba.
3. En una transacción borra el mes (o toda la tabla si no pasas mes) e inserta lo nuevo. Si algo falla, se deshace y tu tabla queda como estaba.

Nunca ignora una columna en silencio.

### Paso a paso con tu tabla

Cada equipo **nombra sus tablas** y viven en `BIGDATA.DEV` (y, ya promovidas, en `BIGDATA.PROD`). Aquí el ejemplo de la casa; cambia el nombre por el de tu tabla.

1. Escribe la función de tu gold en `gold.py` y súmala a `TABLAS_GOLD`. Corre el paso gold.
2. Escribe el `CREATE TABLE` de tu tabla en `carga.py`, con las columnas de tu gold, y súmalo a `TABLAS_A_CARGAR` (ahí solo se guarda el texto: el código lo muestra, nunca lo ejecuta). La equivalencia de tipos:

   | Spark (gold) | Snowflake |
   |---|---|
   | `date` | `DATE` |
   | `string` | `VARCHAR` |
   | `bigint` o `int` | `NUMBER(38,0)` |
   | `double` | `FLOAT` |

3. El nombre completo de la tabla sale de una función, para que no se escriba a mano:

   ```python
   from pipeline.herramientas.rutas import nombre_tabla_snowflake

   tabla = nombre_tabla_snowflake("dev", "tarifa_por_milla_barrio")
   print(tabla)  # BIGDATA.DEV.TARIFA_POR_MILLA_BARRIO
   ```

4. Crea la tabla **en Snowsight** (una sola vez; el código no la crea) con este SQL, y luego carga un mes. El texto exacto de tu tabla lo imprime `sql_para_snowsight` (o el error de `cargar_snowflake` si falta):

   ```sql
   USE ROLE BIGDATA_DEV;
   USE WAREHOUSE BIGDATA_WH;
   USE DATABASE BIGDATA;

   CREATE TABLE IF NOT EXISTS BIGDATA.DEV.TARIFA_POR_MILLA_BARRIO (
     FECHA DATE, BOROUGH VARCHAR, FRANJA VARCHAR,
     VIAJES NUMBER(38,0), DISTANCIA_TOTAL_MI FLOAT,
     INGRESO_TOTAL FLOAT, TARIFA_POR_MILLA FLOAT);
   ```

   ```python
   from pipeline.herramientas.bodega import cargar_gold
   from pipeline.herramientas.rutas import nombre_tabla_snowflake

   tabla = nombre_tabla_snowflake("dev", "tarifa_por_milla_barrio")
   filas = cargar_gold(
       tabla,  # siempre BASE.ESQUEMA.TABLA
       "tarifa_por_milla_barrio",  # carpeta dentro de s3://<lake>/dev/gold/
       mes="2024-01",  # None = reemplaza toda la tabla
   )
   print(f"Se cargaron {filas} filas")
   ```

   Si tu columna de fecha no se llama `FECHA`, indica `columna_fecha="NOMBRE"`.

**Debes ver:** `CREA ...`, `CARGA BIGDATA.DEV....` y `Se cargaron N filas`, con N igual a las filas de gold de ese mes.

Lo normal es no llamar a estas funciones a mano: `make correr PASO=snowflake` (o la tarea `cargar_snowflake` del DAG) lo hace, y antes compara las columnas de gold con las de la tabla usando Athena.

### Si las columnas no coinciden

Por ejemplo, gold ya trae `rango_distancia` y tu tabla todavía no la tiene:

```text
ColumnasDistintas: No se cargó nada: las columnas de gold (@BIGDATA.DEV.LAKE_GOLD/mi_tabla/mes=2024-01/) no coinciden con la tabla BIGDATA.DEV.MI_TABLA.

  Solo en S3 (gold las trae, la tabla no): RANGO_DISTANCIA

Qué hacer:
  - Si la columna es nueva a propósito, agrégala a la tabla, por ejemplo:
      ALTER TABLE BIGDATA.DEV.MI_TABLA ADD COLUMN RANGO_DISTANCIA TEXT;
    (o vuelve a crear la tabla con tu CREATE TABLE completo).
```

El `ALTER` sugerido lleva el tipo que Snowflake infiere de los Parquet (por ejemplo `TEXT` para un texto; en tu tabla puedes escribir `VARCHAR`, que es lo mismo). El error también avisa de lo contrario (columnas que están en la tabla y gold ya no trae) y de tipos distintos.

### Notas

- Los tipos se comparan por familia (texto, número, decimal, fecha, timestamp), no por precisión: `NUMBER(19,0)` en el Parquet y `NUMBER(38,0)` en la tabla es lo mismo.
- Sin `conexion=`, la función abre la conexión por el secreto del entorno de la tabla (`BIGDATA_DEV` para `BIGDATA.DEV.*`, `BIGDATA_PROD` para `BIGDATA.PROD.*`). **No** usa `~/.snowflake/connections.toml` (rol `ACCOUNTADMIN`).
- Solo mira los archivos `.parquet`: `_SUCCESS` y los marcadores `_$folder$` que dejan Spark y Glue se ignoran.
- `BIGDATA.DEV.DAILY_ZONE_METRICS` (la tabla de las clases 4 a 6) queda como historia: ya no es «la tabla».

<a id="pasos"></a>
## Los pasos como funciones

Los cuatro pasos del pipeline son funciones que se llaman solas, y son **las mismas** en una celda de un notebook, en `make correr PASO=...` y como tarea del DAG `pipeline_taxi` (con el mismo nombre):

```python
from pipeline.correr import cargar_snowflake, correr_bronze, correr_gold, correr_silver

correr_bronze(limite="1000")
correr_silver(limite="1000")
correr_gold(limite="1000")
cargar_snowflake()
```

Cada una recibe las cuatro perillas, todas opcionales: `mes`, `computo`, `limite` y `reprocesar`. Lo que no pases sale de `pipeline.yaml`. **El entorno no es una perilla**: desde el Code Editor siempre es `dev`. Cada una imprime el mismo encabezado (entorno, cómputo, paso, mes, límite, qué lee, qué escribe y qué tabla de control usa) y un cierre con una línea por tabla: leídas, escritas, y si **se saltó** o **registró**. Devuelve una lista de `Resultado`.

| Perilla | Valores | Nota |
|---|---|---|
| `computo` | `code_editor`, `glue_small`, `glue_medium`, `glue_large` | Es lo único que cambia entre Spark en el Code Editor y Glue |
| `limite` | `"1000"`, `"100000"`, `"todos"` | Con `code_editor` solo `1000` o `100000` |
| `mes` | `"AAAA-MM"` | Vacío = los meses de `config/dev.yaml` |
| `reprocesar` | `True` o `False` | `True` ignora la tabla de control |

<a id="notebook"></a>
## Probar tus funciones desde un notebook

Dos ayudas para escribir tus funciones en un notebook antes de pasarlas a los `.py`:

```python
from pipeline.herramientas.equipo import (
    probar_mis_funciones,
    usar_mis_funciones,
)

# Las pone «encima» de bronze.py y silver.py, solo en este proceso, para correr el pipeline con ellas.
usar_mis_funciones(agregar_metadatos=agregar_metadatos, deduplicar=deduplicar)

# Corre las MISMAS pruebas de make test con tus funciones, sin tocar los .py.
probar_mis_funciones(agregar_metadatos=agregar_metadatos, deduplicar=deduplicar)
```

Los nombres válidos son `agregar_metadatos`, `debe_ingestar`, `registrar_ingesta` y `deduplicar`; otro nombre es un error. `probar_mis_funciones` imprime una línea por prueba:

- **`OK`**: la prueba corrió y pasó.
- **`PENDIENTE`**: la función todavía conserva la marca `# PENDIENTE(equipo)` en su cuerpo. Cuando la escribes y borras la marca, la **misma prueba** pasa a correr de verdad.
- **`FALLA`**: la prueba corrió y no pasó.

`usar_mis_funciones` **falla con un cómputo de Glue**: tus funciones del notebook viven en el proceso del notebook y no viajan a Glue. Para Glue, cópialas a `bronze.py` (o `silver.py`) y corre de nuevo.
