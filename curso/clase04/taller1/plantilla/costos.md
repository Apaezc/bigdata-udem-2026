# Costos · Taller 1

Equipo: <nombres> · Cuenta que reporta (anfitrión): <nombre>

## Créditos usados

> Corre esta consulta en la cuenta del anfitrión (ajusta la fecha si mides otro día) y pega el resultado.

```sql
USE ROLE ACCOUNTADMIN;      -- rol administrador de tu cuenta de prueba: puede ver el consumo
USE WAREHOUSE COMPUTE_WH;   -- el cómputo que ejecuta la consulta
USE DATABASE CURSO;         -- INFORMATION_SCHEMA pertenece a una base: sin esta línea da
                            -- «Invalid identifier INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY»
SELECT ROUND(SUM(CREDITS_USED), 4) AS CREDITOS
FROM TABLE(INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY(
       DATE_RANGE_START => '2026-11-10'::DATE,
       WAREHOUSE_NAME => 'COMPUTE_WH'));
```

Alternativa sin base activa (tarda hasta 3 h en reflejar el consumo):

```sql
USE ROLE ACCOUNTADMIN;      -- único rol con acceso a SNOWFLAKE.ACCOUNT_USAGE en tu cuenta
USE WAREHOUSE COMPUTE_WH;
SELECT ROUND(SUM(CREDITS_USED), 4) AS CREDITOS
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE WAREHOUSE_NAME = 'COMPUTE_WH' AND START_TIME >= '2026-11-10'::DATE;
```

**Rol:** `ACCOUNTADMIN`. Leer el consumo de créditos exige el privilegio `MONITOR USAGE` (primera consulta) o acceso a la base `SNOWFLAKE` (alternativa); en tu cuenta de prueba los tiene `ACCOUNTADMIN`. Con otro rol, como `PUBLIC`, la consulta falla o devuelve vacío.


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
