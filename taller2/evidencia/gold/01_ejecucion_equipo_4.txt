# Evidencia 01. Ejecución del paso Gold – Equipo 4

## 1. Configuración de la ejecución

| Parámetro | Valor |
|---|---|
| Entorno | DEV |
| Cómputo | code_editor |
| Paso ejecutado | gold |
| Mes procesado | 2024-01 |
| Límite | 1000 |
| Reprocesar | false |

## 2. Fuentes de datos utilizadas

El proceso leyó la información desde las siguientes rutas de Amazon S3:

**Viajes (Silver – FHVHV)**

`s3://bigdata-lake-753965517062-us-east-2/dev/silver/fhvhv/mes=2024-01/`

**Zonas (Silver – Taxi Zones)**

`s3://bigdata-lake-753965517062-us-east-2/dev/silver/taxi_zones/`

**Clima (Silver)**

`s3://bigdata-lake-753965517062-us-east-2/dev/silver/clima/mes=2024-01/`

## 3. Destinos de la información

El proceso tenía configuradas las siguientes rutas de escritura:

- **Tarifa por milla y barrio:**

  `s3://bigdata-lake-753965517062-us-east-2/dev/gold/tarifa_por_milla_barrio/mes=2024-01/`

- **Tabla de análisis del equipo 4:**

  `s3://bigdata-lake-753965517062-us-east-2/dev/gold/equipo_4_rango_distancia/mes=2024-01/`

**Tabla de control:** `BIGDATA.CONTROL_DEV.WATERMARK`

## 4. Resultado de la ejecución

| Tabla Gold | Filas leídas | Filas escritas | Decisión |
|---|---:|---:|---|
| tarifa_por_milla_barrio | 1.000 | 5 | SE SALTÓ |
| equipo_4_rango_distancia | 1.000 | 6 | REGISTRÓ |

La tabla `tarifa_por_milla_barrio` no se volvió a procesar porque ya contaba con un registro de ejecución y la configuración tenía `reprocesar=false`.

La tabla `equipo_4_rango_distancia` se construyó correctamente, escribió 6 filas en la capa Gold y registró su ejecución en la tabla de control de Snowflake.

## 5. Mensajes relevantes de la ejecución

```text
CONSULTA BIGDATA.CONTROL_DEV.WATERMARK
(tabla=equipo_4_rango_distancia capa=gold mes=2024-01)

LEE s3://bigdata-lake-753965517062-us-east-2/dev/silver/fhvhv/mes=2024-01

LEE s3://bigdata-lake-753965517062-us-east-2/dev/silver/taxi_zones

LEE s3://bigdata-lake-753965517062-us-east-2/dev/silver/clima/mes=2024-01

BORRA s3://bigdata-lake-753965517062-us-east-2/dev/gold/equipo_4_rango_distancia/mes=2024-01/*

ESCRIBE s3://bigdata-lake-753965517062-us-east-2/dev/gold/equipo_4_rango_distancia/mes=2024-01

REGISTRA BIGDATA.CONTROL_DEV.WATERMARK
(tabla=equipo_4_rango_distancia mes=2024-01)
```

## 6. Conclusión

La ejecución del paso Gold para el equipo 4 finalizó correctamente en el entorno DEV de la cuenta personal de AWS.

Se utilizaron las tres fuentes disponibles en Silver (viajes, zonas y clima), se construyó la tabla `equipo_4_rango_distancia`, se escribieron 6 registros en Amazon S3 y se registró el procesamiento en Snowflake.

**Nota:** Esta ejecución se realizó con el límite de 1.000 filas establecido en la configuración del profesor. Por lo tanto, los resultados corresponden a esa configuración y no deben interpretarse como el procesamiento completo de todos los viajes del mes.

