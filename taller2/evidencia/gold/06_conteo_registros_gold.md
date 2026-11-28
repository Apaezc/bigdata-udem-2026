# Validación del conteo de registros Gold

## Tabla
`bigdata_lake.equipo_4_rango_distancia`

## Consulta ejecutada en Athena

```sql
SELECT COUNT(*) AS total_registros
FROM equipo_4_rango_distancia;
```

## Resultado
- Total de registros: 93
- Días esperados: 31
- Rangos de distancia: 3
- Combinaciones esperadas: 31 × 3 = 93

## Conclusión
La tabla Gold contiene las 93 combinaciones esperadas para enero de 2024, correspondientes a los 31 días del mes y los tres rangos de distancia definidos en el contrato.
