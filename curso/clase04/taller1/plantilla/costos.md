# Costos · Taller 1

Equipo: <nombres> · Cuenta que reporta (anfitrión): <nombre>

## Créditos usados

> Corre esta consulta en la cuenta del anfitrión (ajusta la fecha si mides otro día) y pega el resultado.

```sql
SELECT ROUND(SUM(CREDITS_USED), 4) AS CREDITOS
FROM TABLE(INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY(
       DATE_RANGE_START => '2026-11-10'::DATE,
       WAREHOUSE_NAME => 'COMPUTE_WH'));
```

| Día medido | Warehouse | Tamaño | Créditos |
|---|---|---|---|
| <fecha> | COMPUTE_WH | XS | <valor> |

Referencia de presupuesto (estimación del pensum, no medida): hasta 0.3 créditos el Lab 4 y hasta 0.8 el taller en clase.

## Consulta más pesada

- Consulta: <cuál es y a qué pregunta pertenece (por ejemplo, la 3 del caso A)>.
- Cómo la encontraste: Snowsight > Monitoring > Query History > ordenar por duración.
- Captura del Query Profile: `query_profile.png` (en esta carpeta).

## Lectura del Query Profile

- Operador que concentra el tiempo: <nombre del operador y qué porcentaje del tiempo>.
- Qué harías para reducirlo: <una decisión concreta>.

## Warehouse

<Tamaño usado, suspensión automática (60 s) y si lo suspendiste al terminar.>
