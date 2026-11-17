# Contrato del Taller 2

Se llena en la clase 6 (18 de noviembre de 2026) y se sube a `taller2/contrato.md` en el fork del anfitrión. Sirve para que el equipo y el instructor acuerden **antes de programar** qué se va a construir y cómo se sabrá que está bien. Si algo cambia más adelante, no se borra: se agrega una línea al final de la sección 9 con la fecha y el motivo.

Equipo: <nombre del equipo> · Anfitrión (dueño del fork): <nombre>

## 1. Integrantes y roles

Los roles rotan respecto al Taller 1: nadie repite. Anota el rol que tuvo cada quien en el Taller 1 para comprobarlo.

| Integrante | Rol en el Taller 1 | Rol en el Taller 2 |
|---|---|---|
| <nombre> | <rol> | Analista de negocio y cumplimiento |
| <nombre> | <rol> | Modelador SQL |
| <nombre> | <rol> | Ingeniero de datos |
| <nombre> | <rol> | Operador cloud y calidad |

## 2. Pregunta de negocio

Una sola pregunta, en una frase, que alguien fuera del equipo entienda. Incluye el período y los datos que se usarán.

> <pregunta>

**Para quién es la respuesta y qué decisión apoyaría:** <una o dos frases>

## 3. Hipótesis

Qué esperan encontrar y por qué. Una hipótesis que puede resultar falsa es mejor que una que siempre se cumple.

> <hipótesis y razón>

## 4. Cambio elegido

| Campo | Respuesta |
|---|---|
| Capa | silver / gold (elige una) |
| Archivo y función donde va | <por ejemplo, `src/pipeline/silver.py`, función `enriquecer`> |
| Qué se agrega o cambia | <columna, regla de limpieza o agregado, con su nombre> |
| Definición exacta | <fórmula, umbrales, qué pasa con los nulos> |
| Por qué lo necesita la pregunta | <una o dos frases: qué no se podía responder sin este cambio> |

## 5. Cómo se probará

- **Pruebas con pytest** (mínimo tres): un caso normal, un caso límite (por ejemplo, justo en el umbral) y un caso con datos malos (nulos o valores imposibles). Describe cada una en una línea con su entrada y su resultado esperado.
- **Archivo de pruebas:** <`tests/test_silver.py` u otro>
- **CI:** el PR debe tener los cinco checks en verde antes del merge. Revisor: <integrante distinto de quien escribe el cambio>
- **Corrida en Glue:** parámetros previstos (`computo`, `mes`): <valores>

## 6. Qué cifra responderá la pregunta

- **Tabla de donde sale:** <por ejemplo, la tabla de gold en Snowflake>
- **La cifra o comparación:** <por ejemplo, viajes promedio por día con lluvia fuerte frente a días sin lluvia, ponderado por zona>
- **Cómo se leerá el resultado:** <qué valor confirmaría la hipótesis y qué valor la contradiría>
- **Conciliación prevista:** qué cifras compararán entre bronze, silver, gold y Snowflake, y cuáles descartes esperan explicar.

## 7. Riesgos

| Riesgo | Cómo lo manejaremos |
|---|---|
| <por ejemplo, la lluvia se repite en todas las filas del día> | <guardarla una vez por día; contar días con `COUNT(DISTINCT FECHA)`> |
| <por ejemplo, el cambio deja nulos en silver> | <regla y prueba para ese caso> |
| <por ejemplo, Glue se queda sin presupuesto> | <correr un solo mes; apagar al terminar cada sesión> |

## 8. Acuerdos de trabajo

- **Reunión del equipo:** <días y horas, canal>
- **Quién revisa los PR:** <regla; nadie aprueba su propio cambio>
- **Cuándo se hace merge:** solo con CI en verde y una revisión.
- **Hitos propios:** 23 de nov.: <lo que estará listo>; 24 de nov.: <lo que mostraremos>; 29 de nov.: entrega.
- **Quién apaga las cuentas al terminar cada sesión:** <rol o turno>
- **Si alguien no responde en 24 horas:** <qué hace el resto>

## 9. Cambios al contrato

| Fecha | Qué cambió | Por qué |
|---|---|---|
| | | |

---

## Ejemplo (borrar al llenar el contrato)

**Equipo:** Lluvia Norte · **Anfitrión:** Camila R.

**1. Integrantes y roles.** Camila R. (Taller 1: ingeniera de datos; Taller 2: analista de negocio y cumplimiento), Andrés M. (Taller 1: analista; Taller 2: modelador SQL), Laura P. (Taller 1: modelador; Taller 2: operadora cloud y calidad), Julián T. (Taller 1: calidad y costos; Taller 2: ingeniero de datos).

**2. Pregunta.** En enero de 2024, ¿los viajes largos (más de 8 millas) caen más que los cortos (menos de 3 millas) en los días con lluvia fuerte? Para quién: la autoridad de movilidad, para decidir si refuerza el servicio a zonas lejanas en días de lluvia.

**3. Hipótesis.** Los viajes largos caen más que los cortos con lluvia fuerte, porque quien tiene una alternativa para un trayecto largo (tren, no salir) la usa antes que para uno corto.

**4. Cambio.** Capa: silver. Archivo: `src/pipeline/silver.py`, dentro de `enriquecer`. Se agrega la columna `RANGO_DISTANCIA` con tres valores: `corto` (menos de 3 millas), `medio` (de 3 a 8) y `largo` (más de 8). Una distancia nula queda como `desconocido`; en el límite exacto, 3.0 es `medio` y 8.0 es `medio`. Gold agrega los viajes por fecha, zona, empresa y `RANGO_DISTANCIA`. Lo necesita la pregunta porque el gold actual solo guarda la distancia promedio del grupo, y con un promedio no se puede separar largos de cortos.

**5. Pruebas.** (a) Una fila de 2.5 millas queda `corto`. (b) Una fila de exactamente 8.0 millas queda `medio`. (c) Una fila con distancia nula queda `desconocido` y no se descarta. Archivo: `tests/test_silver.py`. Revisor del PR: Laura P. Corrida en Glue: `computo=glue_medium`, `mes=2024-01`.

**6. Cifra.** Se calcula en Snowflake, sobre gold, la diferencia porcentual de viajes entre día lluvioso (más de 10 mm) y día seco, por cada `RANGO_DISTANCIA`, usando días y no filas. Si la caída de `largo` es mayor que la de `corto`, la hipótesis se sostiene. Conciliación: filas de bronze menos descartes de silver igual a filas de silver; suma de viajes en silver igual a la de gold; viajes en Snowflake igual a lo registrado en la tabla de control.

**7. Riesgos.** La lluvia se repite en todas las filas del día: se guarda una vez por día. Pocos días de lluvia fuerte en enero: se reporta cuántos son (n) en el informe. Presupuesto de Glue: un solo mes y apagar al terminar.

**8. Acuerdos.** Reunión martes y jueves a las 8 p. m. por videollamada. Nadie aprueba su propio PR. Laura apaga las cuentas al cierre de cada sesión.
