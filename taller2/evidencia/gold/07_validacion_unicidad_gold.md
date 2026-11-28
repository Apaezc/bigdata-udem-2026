# Validación de unicidad de la tabla Gold

## Tabla
`bigdata_lake.equipo_4_rango_distancia`

## Llave de negocio
- fecha
- rango_distancia

## Consulta ejecutada

```sql
SELECT
    COUNT(*) AS total_registros,
    COUNT(DISTINCT CONCAT(CAST(fecha AS VARCHAR), '-', rango_distancia)) AS llaves_unicas
FROM equipo_4_rango_distancia;
```

## Resultado
- Total de registros: 93
- Llaves únicas: 93
- Registros duplicados: 0

## Conclusión
La tabla Gold cumple la regla de unicidad definida en el contrato: existe una sola fila por cada combinación de fecha y rango de distancia.
