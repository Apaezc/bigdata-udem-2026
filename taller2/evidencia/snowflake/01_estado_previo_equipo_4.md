# Evidencia 01. Estado previo de la tabla Snowflake

## 1. Objetivo

Verificar el estado de la tabla destino antes de realizar la carga de los datos Gold del equipo 4.

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
| 0 | NULL | NULL |

## 5. Interpretación

La consulta confirma que la tabla destino existe, pero se encuentra vacía. No hay registros previos que puedan verse afectados por la carga de enero de 2024.

## 6. Entorno

Validación realizada en la cuenta personal de AWS y Snowflake, entorno DEV.
