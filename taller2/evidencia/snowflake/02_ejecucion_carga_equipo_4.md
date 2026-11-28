# Evidencia 02. Ejecución de carga Gold a Snowflake

## 1. Objetivo

Cargar en Snowflake los datos generados por el proceso Gold del equipo 4, desde los archivos Parquet almacenados en Amazon S3.

## 2. Configuración

- Entorno: DEV
- Periodo: 2024-01
- Cómputo: code_editor (este paso no usa Spark)
- Límite: 1000
- Reprocesar: false
- Tabla destino: `BIGDATA.DEV.EQUIPO_4_RANGO_DISTANCIA`

## 3. Resultado de la ejecución

| Tabla | Leídos | Escritos | Estado |
|---|---:|---:|---|
| tarifa_por_milla_barrio | 5 | 5 | SE SALTÓ |
| equipo_4_rango_distancia | 6 | 6 | REGISTRÓ |

La tabla de tarifas se omitió porque ya estaba registrada y `reprocesar=false`.

## 4. Advertencia observada

Durante la ejecución, Athena informó que no encontró la tabla `dev_gold_equipo_4_rango_distancia` en su catálogo de Glue.

El proceso continuó con la carga a Snowflake y registró los seis registros en la tabla de control. Por tanto, la verificación mediante Athena quedó pendiente y no debe considerarse exitosa.

## 5. Conclusión

El proceso reportó la carga de seis registros de la tabla Gold del equipo 4 hacia Snowflake, en el entorno DEV y para enero de 2024. La confirmación de los registros se realizó posteriormente mediante una consulta directa en Snowflake.
