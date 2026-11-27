# Contrato del Taller 2

Equipo: EQUIPO 4 · Anfitrión (dueño del fork): Andrea Páez Cardona

## 1. Integrantes y roles

Los roles rotan respecto al Taller 1: nadie repite.

| Integrante | Rol en el Taller 1 | Rol en el Taller 2 |
|---|---|---|
| <por confirmar> | <rol> | Analista de negocio y cumplimiento |
| Andrea Páez Cardona | Analista | Modelador SQL |
| <por confirmar> | <rol> | Ingeniero de datos |
| <por confirmar> | <rol> | Operador cloud y calidad |

Roles del Taller 1: Andrea Páez Cardona (Analista), Ana María Montealegre (Modeladora), Manuela Restrepo Céspedes (Ingeniera de datos), Julian Olaya (Calidad y costos).

## 2. Pregunta de negocio

> En enero de 2024, ¿los viajes largos (5 millas o más) en Uber y Lyft caen más que los cortos (menos de 2 millas) los días con lluvia en NYC?

**Para quién es la respuesta y qué decisión apoyaría:** para la autoridad de movilidad. Si la lluvia golpea más a los viajes largos, la demanda que se pierde está en trayectos entre barrios y hacia aeropuertos, y ahí convendría reforzar transporte público o tarifas los días de lluvia; si golpea más a los cortos, el efecto está en el centro.

## 3. Hipótesis

> Los días con lluvia caen más los viajes largos que los cortos. Razón: con lluvia la gente evita salir lejos (planes, visitas, trayectos opcionales), mientras que los viajes cortos reemplazan caminar y pueden incluso aumentar. Puede resultar falsa: los viajes largos de aeropuerto no dependen del clima.

## 4. Cambio elegido

| Campo | Respuesta |
|---|---|
| Capa | gold |
| Archivo y función donde va | `src/pipeline/gold.py`, función `equipo_4_rango_distancia` (registrada en `TABLAS_GOLD`); su `CREATE TABLE` en `src/pipeline/carga.py` (`DDL_EQUIPO_4_RANGO_DISTANCIA`, en `TABLAS_A_CARGAR`) |
| Qué se agrega o cambia | Tabla de gold `equipo_4_rango_distancia`: una fila por fecha y `rango_distancia`, con `lluvia_mm` del día, `viajes`, `distancia_total_mi` e `ingreso_total` |
| Definición exacta | `rango_distancia` = `corto` si `distancia_mi` < 2; `medio` si 2 ≤ `distancia_mi` < 5; `largo` si `distancia_mi` ≥ 5. Silver ya deja solo 0 < distancia < 100 mi, así que no hay nulos ni viajes sin rango. `lluvia_mm` es la del día (llega por `enriquecer`); si faltara el clima de un día queda nula y la respuesta excluye ese día. Día con lluvia: `lluvia_mm` ≥ 1.0 mm |
| Por qué lo necesita la pregunta | El gold de la casa agrupa por barrio y franja horaria, no por distancia del viaje: sin el rango no se puede comparar cómo cambian los viajes largos y los cortos con la lluvia |

Además, las dos funciones del equipo: `agregar_metadatos` (`bronze.py`) y `deduplicar` (`silver.py`, una fila por `_hash_fila`).

## 5. Cómo se comprobará

- **Cifras de Athena:** viajes por `rango_distancia` en `dev_gold_equipo_4_rango_distancia` (la suma de los tres debe ser igual a las filas de silver); en silver, `COUNT(*)` contra `COUNT(DISTINCT _hash_fila)` (deben ser iguales). Consultas en `taller2/conciliacion.sql`.
- **Cifras de Snowflake:** `SUM(VIAJES)` de `BIGDATA.DEV.EQUIPO_4_RANGO_DISTANCIA` contra `COUNT(*)` de `dev_silver_fhvhv` en Athena; 93 filas (31 días × 3 rangos).
- **CI y revisión:** el PR debe tener los cinco checks en verde antes del merge. Revisor: un integrante distinto de quien abre el PR.
- **Corrida en Glue:** `computo = glue_small`, `mes = 2024-01`, `limite = todos` (pruebas previas con `limite = 1000`).

## 6. Qué cifra responderá la pregunta

- **Tabla de donde sale:** `BIGDATA.DEV.EQUIPO_4_RANGO_DISTANCIA` (consulta en `taller2/respuesta.sql`).
- **La cifra o comparación:** cambio porcentual de viajes por día en días con lluvia frente a días secos, para cada rango (R1), y el mismo cambio comparando cada día con los días secos del mismo día de la semana (R2).
- **Cómo se leerá el resultado:** si el cambio de `largo` es más negativo que el de `corto`, se confirma la hipótesis; si es igual o menos negativo, se contradice.
- **Conciliación prevista:** filas únicas de bronze − descartes de silver por tipo (sin hora, sin zona, distancia fuera de rango, tarifa ≤ 0, duración fuera de 1-180 min, fuera del mes) = filas de silver = suma de `viajes` de gold = `SUM(VIAJES)` en Snowflake.

## 7. Riesgos

| Riesgo | Cómo lo manejaremos |
|---|---|
| La lluvia se repite en las 3 filas de cada día | Nunca se suma `lluvia_mm`; los días se cuentan con `COUNT(DISTINCT FECHA)` |
| Hay muchos más días secos que con lluvia | Se comparan viajes por día, no totales |
| Los días con lluvia caen en días de la semana distintos | Control por día de la semana con `AVG() OVER (PARTITION BY RANGO_DISTANCIA, DIA_SEMANA)` (R2) |
| Un solo mes: pocos días con lluvia | Se dice en el informe; la conclusión es para enero de 2024, no general |
| Reproceso duplica silver y gold | `deduplicar` por `_hash_fila`; evidencia antes y después en Athena |
| Glue o el Code Editor se quedan encendidos | Correr un solo mes; `make airflow-off` y `make airflow-local-down` al terminar cada sesión |

## 8. Acuerdos de trabajo

- **Reunión del equipo:** <días y horas, canal>
- **Quién revisa los PR:** nadie aprueba su propio cambio; revisa otro integrante.
- **Cuándo se hace merge:** solo con CI en verde y una revisión.
- **Hitos propios:** 27 de nov.: código y PR; 28 de nov.: pipeline en Glue y conciliación; 29 de nov.: informe y entrega.
- **Quién apaga las cuentas al terminar cada sesión:** Operador cloud y calidad (en la cuenta de la anfitriona).
- **Si alguien no responde en 24 horas:** el resto asume su parte y lo anota aquí.

## 9. Cambios al contrato

| Fecha | Qué cambió | Por qué |
|---|---|---|
| 2026-11-27 | Contrato subido al repositorio con la pregunta de rango de distancia y lluvia | No se había subido el 18 de nov. |
