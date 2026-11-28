# Conteo del archivo original FHvhv - Enero 2024

**Fecha:** 28 de noviembre de 2026
**Entorno:** AWS SageMaker personal
**Fuente:** S3 - archivo crudo FHvhv enero 2024

## Ubicación del archivo

`s3://bigdata-lake-753965517062-us-east-2/dev/bronze/_crudo/fhvhv/mes=2024-01/fhvhv_tripdata_2024-01.parquet`

## Resultado

Se leyó el archivo Parquet original sin aplicar límite de registros.

**Total de registros: 19.663.930**

## Comparación con las capas actuales

- Bronze: 1.000 registros.
- Silver: 1.000 registros.
- Archivo original: 19.663.930 registros.

La ejecución anterior de Bronze y Silver corresponde a una muestra de 1.000 registros, no al conjunto completo del mes.
