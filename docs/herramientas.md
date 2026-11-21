# Herramientas de la casa

Funciones que ya están escritas y probadas para que las uses en tus talleres sin reescribirlas. Se importan desde `pipeline.herramientas`.

## Índice

- [Cargar gold a Snowflake](#cargar-gold-a-snowflake)

<a id="cargar-gold-a-snowflake"></a>
## Cargar gold a Snowflake

`cargar_gold_a_snowflake` lleva los Parquet de gold (S3) a una tabla de Snowflake. Es la misma función que usa la tarea `cargar_gold` del DAG `pipeline_taxi`, así que en clase y en el DAG se comporta igual.

Qué hace, en este orden:

1. Lee las columnas y tipos de los Parquet en S3 y las columnas de tu tabla, y las compara. Si no coinciden, se detiene con un error y no toca la tabla.
2. Copia los Parquet a una tabla temporal. Si el COPY falla, tu tabla queda como estaba.
3. En una transacción borra el mes (o toda la tabla si no pasas mes) e inserta lo nuevo. Si algo falla, se deshace y tu tabla queda como estaba.

Nunca ignora una columna en silencio: antes, una columna nueva en gold desaparecía sin error.

### Paso a paso

1. Agrega tu columna en `gold.py` (en `COLUMNAS` y en el select) y corre gold. Ejemplo: `rango_distancia`.
2. En Snowflake (Snowsight o Python), crea tu tabla con todas las columnas de gold, en el esquema de tu entorno:

   ```sql
   CREATE TABLE IF NOT EXISTS BIGDATA.DEV.GOLD_ALUMNO (
       FECHA               DATE,
       ZONA                VARCHAR,
       EMPRESA             VARCHAR,
       VIAJES              NUMBER(38, 0),
       INGRESO_TOTAL       FLOAT,
       PROPINA_PROMEDIO    FLOAT,
       DISTANCIA_PROMEDIO  FLOAT,
       LLUVIA_MM           FLOAT,
       RANGO_DISTANCIA     VARCHAR
   );
   ```

3. Carga desde Python (carpeta de tu tabla dentro de gold, y el mes si quieres reemplazar solo uno):

   ```python
   from pipeline.herramientas import cargar_gold_a_snowflake

   filas = cargar_gold_a_snowflake(
       "BIGDATA.DEV.GOLD_ALUMNO",  # tu tabla, con base de datos y esquema
       "daily_zone_metrics",  # carpeta dentro de s3://<lake>/dev/gold/
       mes="2024-01",  # None = reemplaza toda la tabla
   )
   print(f"Se cargaron {filas} filas")
   ```

   Si tu columna de fecha no se llama `FECHA`, indica `columna_fecha="NOMBRE"`.

**Debes ver:** `Se cargaron N filas`, con N igual a las filas de gold de ese mes.

### Si las columnas no coinciden

Por ejemplo, gold ya trae `rango_distancia` y tu tabla todavía no la tiene:

```text
ColumnasDistintas: No se cargó nada: las columnas de gold (@BIGDATA.DEV.LAKE_GOLD/daily_zone_metrics/mes=2024-01/) no coinciden con la tabla BIGDATA.DEV.GOLD_ALUMNO.

  Solo en S3 (gold las trae, la tabla no): RANGO_DISTANCIA

Qué hacer:
  - Si la columna es nueva a propósito, agrégala a la tabla, por ejemplo:
      ALTER TABLE BIGDATA.DEV.GOLD_ALUMNO ADD COLUMN RANGO_DISTANCIA VARCHAR;
    (o vuelve a crear la tabla con tu CREATE TABLE completo).
```

El error también avisa de lo contrario (columnas que están en la tabla y gold ya no trae, con la sugerencia de corregir `gold.py`) y de tipos distintos (por ejemplo, texto en gold y número en la tabla). Cualquier otro error del COPY lo deja Snowflake en el mensaje.

### Notas

- Los tipos se comparan por familia (texto, número, decimal, fecha, timestamp), no por precisión: `NUMBER(19,0)` en el Parquet y `NUMBER(38,0)` en la tabla es lo mismo.
- La conexión sale de `~/.snowflake/connections.toml`, igual que la tabla de control. Si ya tienes una conexión abierta, pásala con `conexion=`.
