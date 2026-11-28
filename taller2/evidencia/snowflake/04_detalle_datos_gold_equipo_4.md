# Evidencia 04. Detalle de los datos Gold del equipo 4

## 1. Objetivo

Consultar y revisar los registros almacenados en Snowflake después de ejecutar la carga de la tabla Gold del equipo 4.

## 2. Tabla consultada

`BIGDATA.DEV.EQUIPO_4_RANGO_DISTANCIA`

## 3. Resultado obtenido

| Fecha | Empresa | Rango | Lluvia (mm) | Viajes | Distancia total (mi) | Ingreso total |
|---|---|---|---:|---:|---:|---:|
| 2024-01-01 | Lyft | Corto | 0 | 81 | 102.01 | 1291.64 |
| 2024-01-01 | Lyft | Largo | 0 | 49 | 466.57 | 2464.50 |
| 2024-01-01 | Lyft | Medio | 0 | 99 | 310.27 | 2641.69 |
| 2024-01-01 | Uber | Corto | 0 | 210 | 268.01 | 3563.69 |
| 2024-01-01 | Uber | Largo | 0 | 272 | 2759.03 | 15142.48 |
| 2024-01-01 | Uber | Medio | 0 | 289 | 957.68 | 8952.95 |

## 4. Hallazgos iniciales

- Se identifican las empresas Lyft y Uber.
- Ambas empresas tienen registros para los tres rangos de distancia: corto, medio y largo.
- Los seis registros corresponden al 1 de enero de 2024.
- La precipitación registrada es de 0 mm en todos los grupos.
- El total de viajes es de 1.000: 229 de Lyft y 771 de Uber.

## 5. Limitaciones de esta consulta

Los datos corresponden a la muestra procesada con el límite de 1.000 registros configurado en el proyecto.

Como todos los registros pertenecen a una fecha sin lluvia, esta consulta no permite comparar el comportamiento de los viajes durante días lluviosos y secos.

## 6. Conclusión

La consulta confirma que los datos Gold están disponibles en Snowflake y contienen la información necesaria para clasificar los viajes por empresa y rango de distancia.

Sin embargo, se requiere analizar un conjunto de fechas que incluya días lluviosos y secos para responder la pregunta de investigación.
