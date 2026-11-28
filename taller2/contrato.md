# Contrato del Taller 2

**Equipo:** EQUIPO 4 · Anfitrión (dueño del fork): Andrea Páez Cardona

## 1. Integrantes y roles

| Integrante | Rol en el Taller 1 | Rol en el Taller 2 |
|---|---|---|
| [Completar] | [Completar] | Analista de negocio y cumplimiento |
| Andrea Páez Cardona | Analista | Modelador SQL |
| [Completar] | [Completar] | Ingeniero de datos |
| Manuela Restrepo Céspedes | Ingeniera de datos | Operador cloud y calidad |

Roles del Taller 1: Andrea Páez Cardona (Analista), Ana María Montealegre (Modeladora), Manuela Restrepo Céspedes (Ingeniera de datos), Julián Olaya (Calidad y costos).

## 2. Pregunta de negocio

> En enero de 2024, ¿los viajes largos (5 millas o más) en Uber y Lyft caen más que los cortos (menos de 2 millas) los días con lluvia en NYC?

**Para quién es la respuesta y qué decisión apoyaría:** para la autoridad de movilidad. Si la lluvia afecta más a los viajes largos, la demanda que se pierde podría concentrarse en trayectos entre barrios y hacia aeropuertos. Esto ayudaría a evaluar medidas de movilidad, como reforzar el transporte público o revisar estrategias de movilidad durante los días lluviosos. Si el efecto es mayor en los viajes cortos, la afectación podría concentrarse en desplazamientos urbanos de menor distancia.

El análisis distinguirá Uber y Lyft para evitar que los resultados de ambas plataformas queden mezclados.

## 3. Hipótesis

> Los días con lluvia disminuyen más los viajes largos que los cortos, tanto en Uber como en Lyft.

La hipótesis se basa en que algunos desplazamientos largos pueden ser más fáciles de aplazar cuando llueve, mientras que ciertos viajes cortos pueden reemplazar caminatas.

La hipótesis puede resultar falsa: por ejemplo, los viajes largos hacia aeropuertos podrían mantenerse aunque haya lluvia.

## 4. Cambio elegido

| Campo | Respuesta |
|---|---|
| Capa | Gold |
| Archivo y función | `src/pipeline/gold.py`, función `equipo_4_rango_distancia`, registrada en `TABLAS_GOLD`. |
| Archivo de carga | `src/pipeline/carga.py`, con `DDL_EQUIPO_4_RANGO_DISTANCIA`, registrado en `TABLAS_A_CARGAR`. |
| Tabla Gold | `equipo_4_rango_distancia` |
| Granularidad | Una fila por fecha, empresa y rango de distancia. |
| Dimensiones | `fecha`, `empresa`, `rango_distancia` y `lluvia_mm`. |
| Métricas | `viajes`, `distancia_total_mi` e `ingreso_total`. |

**Definición de los rangos de distancia:**

- `corto`: `distancia_mi` < 2.
- `medio`: 2 ≤ `distancia_mi` < 5.
- `largo`: `distancia_mi` ≥ 5.

Silver ya filtra los viajes con distancias válidas, por lo que se espera que cada viaje válido pertenezca a uno de los tres rangos.

**Definición de empresa:** se conservará la identificación de la plataforma (`empresa`) para separar los resultados de Uber y Lyft. Antes de construir la tabla se verificará cómo están representados estos nombres en los datos de Silver y se utilizará la correspondencia correcta. El análisis incluirá únicamente Uber y Lyft.

**Definición de día lluvioso:** `lluvia_mm` ≥ 1.0 mm. Los días con `lluvia_mm` < 1.0 mm se clasificarán como días sin lluvia. Si no existe información climática para una fecha, esta no se incluirá en la comparación entre días lluviosos y secos.

**Por qué se necesita este cambio:** la tabla Gold de ejemplo agrupa por barrio y franja horaria, pero no permite comparar los viajes según su distancia ni distinguir Uber de Lyft. La nueva tabla incorpora ambas dimensiones y permite responder directamente la pregunta de negocio.

Además, el equipo implementa las funciones asignadas en las capas anteriores:

- `agregar_metadatos` en `src/pipeline/bronze.py`: agrega los cinco metadatos a cada fila y calcula `_hash_fila` a partir de las columnas originales.
- `deduplicar` en `src/pipeline/silver.py`: conserva una sola fila por `_hash_fila`.

## 5. Cómo se comprobará

**Calidad en Athena**

- En Silver, comparar `COUNT(*)` con `COUNT(DISTINCT _hash_fila)`. Los valores deben coincidir después de la deduplicación.
- En Gold, comprobar que los viajes estén clasificados en los rangos corto, medio y largo.
- Verificar que la suma de `viajes` de Gold coincida con el número de viajes válidos de Silver correspondientes a Uber y Lyft.
- Comprobar que no existan duplicados en la granularidad `fecha`, `empresa` y `rango_distancia`.
- Las consultas de conciliación se documentarán en `taller2/conciliacion.sql`.

**Carga en Snowflake**

- Tabla: `BIGDATA.DEV.EQUIPO_4_RANGO_DISTANCIA`.
- Comparar `SUM(VIAJES)` en Snowflake con la suma de viajes de la tabla Gold en Athena.
- Si existen registros para las dos empresas, los tres rangos y los 31 días, se esperan 186 combinaciones (31 × 2 × 3). Este número es una referencia, no una condición obligatoria si alguna combinación no tiene viajes.
- La consulta de respuesta se documentará en `taller2/respuesta.sql`.

**CI y revisión**

- El PR debe tener los cinco checks en verde antes del merge.
- El revisor debe ser un integrante distinto de quien abre el PR.
- Nadie aprueba su propio cambio.

**Corrida en Glue**

- `computo = glue_small`
- `mes = 2024-01`
- `limite = todos`
- Las pruebas iniciales podrán utilizar `limite = 1000`.

## 6. Qué cifras responderán la pregunta

**Tabla de origen:** `BIGDATA.DEV.EQUIPO_4_RANGO_DISTANCIA`.

Se calculará el promedio de viajes por día para cada combinación de empresa y rango de distancia, diferenciando los días lluviosos de los días sin lluvia.

Se utilizarán dos comparaciones:

- **R1 — Comparación general:** cambio porcentual del promedio de viajes por día en días lluviosos frente a días sin lluvia, para cada empresa y rango de distancia.
- **R2 — Comparación por día de la semana:** repetir la comparación teniendo en cuenta el mismo día de la semana, para reducir el efecto de las diferencias entre lunes, martes, fines de semana, etc.

**Interpretación:**

- Si el cambio porcentual de los viajes largos es más negativo que el de los cortos, la hipótesis recibe respaldo.
- Si la caída de los largos es igual o menor que la de los cortos, la hipótesis no recibe respaldo.
- Se presentarán los resultados de Uber y Lyft por separado. También se podrá describir si ambas plataformas muestran un comportamiento similar o diferente.

La conclusión estará limitada a enero de 2024 y no se generalizará automáticamente a otros meses.

## 7. Riesgos

| Riesgo | Cómo lo manejaremos |
|---|---|
| Mezclar Uber y Lyft | Mantener `empresa` como dimensión de Gold y presentar resultados separados. |
| La lluvia se repite en varias filas del día | No sumar `lluvia_mm`; utilizar un valor representativo del día y contar fechas distintas. |
| Hay más días secos que lluviosos | Comparar promedios de viajes por día, no totales acumulados. |
| Los días lluviosos pueden caer en días de la semana diferentes | Realizar una segunda comparación controlando por día de la semana (R2). |
| Un solo mes puede tener pocos días lluviosos | Reportar esta limitación y restringir la conclusión a enero de 2024. |
| Un reproceso puede duplicar Silver y multiplicar Gold | Aplicar `deduplicar` por `_hash_fila` y comprobar los resultados antes y después del reproceso. |
| Falta información climática para alguna fecha | Identificar esas fechas y excluirlas de la comparación climática. |
| Glue o el Code Editor quedan encendidos | Ejecutar un solo mes y apagar los servicios al terminar la sesión. |

## 8. Acuerdos de trabajo

- **Reunión del equipo:** [Completar días, horas y canal].
- **Revisión de PR:** nadie aprueba su propio cambio; revisa otro integrante.
- **Merge:** solo con CI en verde y una revisión.
- **Hitos propios:**
  - 27 de noviembre: código y PR.
  - 28 de noviembre: pipeline en Glue y conciliación.
  - 29 de noviembre: informe y entrega.
- **Apagado de servicios:** responsabilidad del Operador cloud y calidad, en coordinación con la anfitriona y utilizando la cuenta correspondiente.
- **Si alguien no responde en 24 horas:** el resto del equipo asume su parte y lo deja documentado.

## 9. Cambios al contrato

| Fecha | Qué cambió | Por qué |
|---|---|---|
| 2026-11-27 | Contrato subido al repositorio con la pregunta de rango de distancia y lluvia. | No se había subido el 18 de noviembre. |
| 2026-11-27 | Se ajustó la granularidad de Gold para incluir `empresa` y separar Uber y Lyft. Se actualizaron las conciliaciones y el número de combinaciones esperado. | La pregunta de negocio compara el comportamiento de ambas plataformas y no debe mezclar sus viajes. |
