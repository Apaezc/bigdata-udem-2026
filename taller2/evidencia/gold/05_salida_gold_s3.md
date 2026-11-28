# Verificación de archivos Gold en S3

## Ubicación
`s3://bigdata-lake-753965517062-us-east-2/dev/gold/`

## Resultado de la consulta
Se identificaron dos archivos Parquet:

1. Tabla del equipo 4:
   - Ruta: `equipo_4_rango_distancia/mes=2024-01/`
   - Archivo: `part-00000-5f68ed4c-cc88-4f85-997d-d1ef62cd4bcb-c000.snappy.parquet`
   - Tamaño: 4.1 KiB

2. Otra salida del pipeline:
   - Ruta: `tarifa_por_milla_barrio/mes=2024-01/`
   - Tamaño: 17.3 KiB

## Resumen
- Objetos encontrados: 2
- Tamaño total: 21.4 KiB
- La tabla `equipo_4_rango_distancia` cuenta con un archivo Parquet generado para enero de 2024.

## Validación pendiente
Verificar cantidad de registros, unicidad de fecha y rango de distancia, y conciliación de métricas.
