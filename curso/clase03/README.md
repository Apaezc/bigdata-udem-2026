# Clase 3 · Responder bien y guardar para que el total cuadre (lun 9 nov)

Orden de trabajo en clase. Cada lab tiene tres archivos: el enunciado, la verificación y la solución. Procedimiento para llevar el código de GitHub a Snowsight (Copy raw file y pegar en una hoja): ver [`../clase01/cuentas.md`](../clase01/cuentas.md). Todo se trabaja con GitHub y Snowsight, de forma individual, salvo la parada AWS (sección 2), que usa la terminal del Code Editor; la única ayuda es el instructor. Datos: `SNOWFLAKE_SAMPLE_DATA.TPCH_SF1` (solo lectura).

## 1. Lab 3A · Ventanas sobre ORDERS (esquema `CURSO.LAB3A`, 27 min)

1. **Lab** ([`lab3a.sql`](lab3a.sql)): pégalo en una hoja. Paso 0: selecciona de `USE ROLE` a `USE SCHEMA CURSO.LAB3A;` y pulsa ▶. Corre el bloque de la vista `MENSUAL_1995` (ya escrita). Resuelve EJ1 a EJ5 (★). EJ6 a EJ8 (★★) y EJ9 (★★★) son opcionales.
2. **Verificación** ([`lab3a_verificacion.sql`](lab3a_verificacion.sql)): otra hoja, **Run All**. Meta: RESUMEN = OK y "5 de 5".
3. **Solución** ([`lab3a_solucion.sql`](lab3a_solucion.sql)): después de intentarlo.

## 2. Parada AWS · Code Editor y secrets (pasos 5 a 9 de la guía, 35 min)

Entre el Lab 3A y el descanso: dejas listo el entorno donde corre el pipeline de las clases 4 a 6. Es la excepción a la regla de las clases 1 a 4 (sin terminal): estos pasos se hacen en la terminal del Code Editor, dentro del navegador. Los comandos, las salidas esperadas y los errores comunes están en [`docs/guia.md`](../../docs/guia.md), pasos 5 a 9.

1. **Antes (al empezar el Lab 3A):** quien ya hizo el bootstrap en la clase 2 entra a SageMaker Studio y pulsa **Run space** (paso 5.2); tarda 3 a 5 min. Si lo dejas para el final del lab, el Code Editor no estará listo a tiempo.
2. **Pasos 5 y 6 (12 min):** abre el Code Editor, abre una terminal y clona tu fork en `~/bigdata`. Debes ver el prompt terminado en `~/bigdata$`.
3. **Pasos 7 a 9 (17 min):** `make snowflake-conexion` (llave, sin contraseña), `make setup`, y solo si aparece el AVISO de `gh`, `gh auth login` y `make secrets`; cierra con `make doctor`. Debes ver como última línea `==> Diagnóstico sin fallos`.
4. **Si no tienes las cuotas de AWS aprobadas:** sigue con EJ6 a EJ9 del Lab 3A mientras los demás hacen la parada, y lee el recorrido en la guía.

Siempre `cd ~/bigdata` antes de cada `make`: fuera de esa carpeta aparece `No rule to make target`. La clase 4 abre con los pasos 10 a 12 de la guía; sin los pasos 5 a 9 arranca con atraso.

## 3. Lab 3B · QUALIFY, CTE y promedio ponderado (esquema `CURSO.LAB3B`, 14 min)

1. **Lab** ([`lab3b.sql`](lab3b.sql)): Paso 0 igual que el 3A, con `CURSO.LAB3B`. El archivo trae las consultas anidadas de EJ1 a EJ3 como punto de partida: no necesitas haber terminado el Lab 3A. Resuelve B1 a B4 (★); B5 (★★) es opcional.
2. **Verificación** ([`lab3b_verificacion.sql`](lab3b_verificacion.sql)): otra hoja, **Run All**. Meta: RESUMEN = OK y "4 de 4". En B1 a B3 revisa además que la vista use `QUALIFY` (revisión superficial: un comentario con esa palabra también la satisface).
3. **Solución** ([`lab3b_solucion.sql`](lab3b_solucion.sql)): después de intentarlo.

## 4. Lab 3C · Estrella de TPC-H (esquema `CURSO.LAB3C`, 32 min)

1. **Lab** ([`lab3c.sql`](lab3c.sql)): Paso 0 con `CURSO.LAB3C` y Paso 1 (`ALTER SESSION SET QUERY_TAG = 'LAB3C';`, antes de cargar tablas). `DIM_FECHA` (C2) ya viene resuelta. Cada tabla se carga con una sentencia propia. Después de C3, la lectura del costo (unos 4 min, obligatoria): corre la consulta ya escrita, abre en el Query Profile el paso más caro y responde en los comentarios. Resuelve C1 a C5 (★); C6 y C7 (★★) y C8 (★★★, SCD tipo 2) son opcionales.
2. **Verificación** ([`lab3c_verificacion.sql`](lab3c_verificacion.sql)): otra hoja, **Run All**. Meta: RESUMEN = OK y "5 de 5". La fila `MARCA` comprueba que las cargas quedaron marcadas `LAB3C`; las respuestas de lectura no se califican.
3. **Solución** ([`lab3c_solucion.sql`](lab3c_solucion.sql)): incluye la respuesta de referencia de la lectura.

**Ejemplo de entrada y salida de la lectura** (corre la consulta ya escrita en `lab3c.sql`, hoja del lab; los tiempos varían):

| PASO | SEGUNDOS | QUERY_ID |
|---|---|---|
| CREATE OR REPLACE TABLE FACT_LINEITEM | 1.97 | 01c8496b-… |
| CREATE OR REPLACE TABLE DIM_FECHA | 1.22 | 01c8496b-… |
| CREATE OR REPLACE TABLE DIM_CLIENTE | 0.73 | 01c8496b-… |

## 5. Demos del instructor

**Guion de demos** ([`demos.sql`](demos.sql)): una demo por consulta de las slides (2, 3, 5 a 11, 18 a 22, 24 a 34, 36, 37 y, para la 35, el perfil de la carga del Lab 3C), con el número de slide y el resultado esperado de cada una. Las demos 0, 22 y 23 (SCD tipo 1 y tipo 2, slides 33 y 34) usan la estrella que deja lista la demo 0 en `CURSO.DEMO3`. Para borrar los objetos de las demos: ver el final del archivo.

**Evidencia de las slides** ([`evidencia.sql`](evidencia.sql)): para cada afirmación del deck, las consultas paso a paso que llevan a la cifra y el resultado esperado, ordenadas por número de slide; se pega en una hoja de Snowsight y crea y borra su propia base `CURSO_EVIDENCIA_C3`.

## Presentación

- **Presentación** ([`deck/slides.pdf`](deck/slides.pdf)): 38 slides, 240 min. Orden del día: Lab 3A, parada AWS (sección 2), descanso de 20 min, Lab 3B, Lab 3C, controles, caso de NYC y cierre.

## Cómo reiniciar un lab

Los tres Paso 0 son idempotentes: puedes correrlos más de una vez. Cada ejercicio usa `CREATE OR REPLACE`, así que volver a correr un bloque lo reemplaza. Para empezar de cero un esquema:

```sql
DROP SCHEMA IF EXISTS CURSO.LAB3C;
```

y vuelve a correr el Paso 0 del lab.

## Errores comunes

| Síntoma | Causa | Cómo evitarlo |
|---|---|---|
| `This session does not have a current database` o el esquema no existe | No se corrió el Paso 0 en esa hoja | Selecciona del primer `USE ROLE` hasta la última línea del Paso 0 y pulsa ▶ |
| La verificación dice PENDIENTE y sí escribiste tu SELECT | El `CREATE` falló | Busca el mensaje rojo en la hoja del lab |
| REVISAR con columnas distintas | El alias de salida no coincide | Compara TUS_COLUMNAS con COLUMNAS_ESPERADAS |
| Run All en el lab | Corre los ejemplos y los marcadores de todos los ejercicios | Usa Cmd/Ctrl+Enter bloque a bloque; Run All solo en la verificación |
| `Window function [...] appears outside of SELECT, QUALIFY, and ORDER BY clauses` | Filtraste con WHERE el resultado de una ventana | Calcula la ventana en una subconsulta y filtra afuera; en el Lab 3B, usa `QUALIFY` |
| EJ4: dos pedidos del mismo día tienen el mismo acumulado | Sin marco `ROWS`, el marco agrupa por valor de fecha | Escribe `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` y desempata el `ORDER BY` |
| `Object 'MENSUAL_1995' does not exist` (EJ3) | No corriste el bloque de la vista entregada | Corre el `CREATE OR REPLACE VIEW MENSUAL_1995` del lab |
| B1, B2 o B3 dan REVISAR con el resultado correcto: «Usa QUALIFY» | La vista usa una subconsulta | Reescribe con `QUALIFY` y sin subconsulta |
| B4 da 161711.03 en las tres columnas | Seguiste con `AVG` sobre los promedios | Pondera: `SUM(PEDIDOS * PROM) / SUM(PEDIDOS)` |
| La consulta de lectura del Lab 3C no devuelve filas | La marca no está en esa hoja (`QUERY_TAG` vale por sesión) o aún no cargaste tablas | Corre el Paso 1 en la misma hoja, antes de cargar |
| La fila `MARCA` de la verificación dice PENDIENTE o REVISAR | Las cargas no se hicieron con `QUERY_TAG = 'LAB3C'` en esa hoja | Corre el Paso 1 en la hoja del lab y repite el `CREATE TABLE` que falte |
| FACT_LINEITEM con más de 6 001 215 filas | Uniste con una tabla que repite la clave | Une solo con ORDERS por `L_ORDERKEY` y cuenta antes y después |
| DIM_FECHA con 3 000 filas | Faltó el filtro por la fecha máxima | `QUALIFY FECHA <= MAXF`, después de calcular `FECHA` con `ROW_NUMBER` |
| `Object 'FACT_LINEITEM' does not exist` (C4 a C8) | Creaste la vista antes que las tablas | Carga C1 a C3 y después las vistas |
| `Missing column specification` al crear una vista | `COUNT`, `SUM` o `AVG` sin `AS` | Pon `AS NOMBRE` en cada columna calculada |
| No ves un archivo en tu fork | El fork no está al día | Sync fork > Update branch |
