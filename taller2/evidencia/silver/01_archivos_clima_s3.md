# Evidencia 05. Verificación de archivos Silver de clima en S3

## 1. Objetivo

Comprobar la existencia de los archivos de clima procesados en la capa Silver de Amazon S3 para enero de 2024.

## 2. Ubicación verificada

```text
s3://bigdata-lake-753965517062-us-east-2/dev/silver/clima/mes=2024-01/
```

## 3. Comando ejecutado

```bash
aws s3 ls s3://bigdata-lake-753965517062-us-east-2/dev/silver/clima/mes=2024-01/
```

## 4. Resultado obtenido

```text
2026-11-25 00:26:49          0 _SUCCESS
2026-11-25 00:26:48       1433 part-00000-d22d4985-2cf6-4631-94a5-83e86a11eb1e-c000.snappy.parquet
```

## 5. Interpretación

La carpeta contiene el marcador `_SUCCESS` y un archivo Parquet comprimido con Snappy. Esto confirma la existencia de la salida de la capa Silver de clima para enero de 2024.

## 6. Conclusión

Se verifica que los archivos climáticos procesados están disponibles en S3 para el periodo consultado.

Esta evidencia confirma la existencia de los archivos, pero no demuestra por sí sola qué fechas tienen lluvia ni sus valores de precipitación.
