# Evidencia 03. Verificación de datos cargados en Snowflake

## 1. Objetivo

Comprobar que los registros del proceso Gold del equipo 4 quedaron almacenados en la tabla destino de Snowflake.

## 2. Tabla consultada

`BIGDATA.DEV.EQUIPO_4_RANGO_DISTANCIA`

## 3. Consulta ejecutada

```sql
SELECT
    COUNT(*) AS TOTAL_REGISTROS,
    MIN(FECHA) AS FECHA_MINIMA,
    MAX(FECHA) AS FECHA_MAXIMA
FROM BIGDATA.DEV.EQUIPO_4_RANGO_DISTANCIA;
```

## 4. Resultado obtenido

| TOTAL_REGISTROS | FECHA_MINIMA | FECHA_MAXIMA |
|---:|---|---|
| 6 | 2024-01-01 | 2024-01-01 |

## 5. Interpretación

La consulta confirma que la tabla contiene seis registros y que todos corresponden al 1 de enero de 2024.

El total coincide con los seis registros reportados por el proceso de carga desde S3 hacia Snowflake.

## 6. Conclusión

Se confirma que los seis registros de la tabla Gold del equipo 4 están disponibles en Snowflake, dentro del entorno DEV.
