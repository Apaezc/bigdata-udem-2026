# Taller 2 · Tu propia pregunta sobre la lluvia y los viajes de NYC, respondida con tu pipeline

Big Data e Ingeniería de Datos (UdeM) · Se presenta en la clase 6, el 18 de noviembre de 2026 · **Entrega final: domingo 29 de noviembre de 2026, 23:59 (hora de Colombia)** · Mismos equipos del Taller 1

El Taller 2 vale 100 puntos y, junto con el Taller 1, forma la nota de talleres, 50 % cada uno. Se trabaja solo con GitHub, el Code Editor, AWS y Snowflake. La única ayuda es el instructor.

## 1. Para qué es este taller

En el Taller 1 respondieron preguntas sobre una tabla que ya venía lista. En las clases 5 y 6 construyeron una versión de práctica para entender el problema (la ingesta a su propio disco y el lab de silver y gold). En la clase 7 corrieron, de punta a punta y en dev, el pipeline de la casa (`pipeline_taxi`): bronze con la puerta de la tabla de control, silver, gold y la carga a Snowflake, y vieron cómo se pasa a prod con un PR y el CI/CD. Este taller les pide algo distinto: **extender ese pipeline** para responder **una pregunta que ustedes mismos eligen** sobre la lluvia y los viajes de NYC, y demostrar que la respuesta es confiable.

Una respuesta confiable no es solo un número. Es un número que se puede reproducir (porque el código está versionado y pasa la revisión y el CI), que viene de un pipeline que corre completo en la nube, y que cuadra con lo que había en cada capa del camino. Ese es el problema real del taller: **¿cómo sé que la cifra que le voy a dar a alguien es la correcta?** Las herramientas (Git, Glue, la tabla de control) están al servicio de esa pregunta.

## 2. Los cuatro entregables

1. **El cambio del equipo en el código de su fork.** Tiene dos partes. Primera: las dos funciones que el pipeline deja pendientes a propósito, `agregar_metadatos` (en `bronze.py`) y `deduplicar` (en `silver.py`); sus pruebas (que ya existen en `tests/test_equipo_*.py`) pasan de `PENDIENTE` a `OK`. Segunda: lo que su pregunta necesita: una **tabla de gold propia** (una función en `src/pipeline/gold.py`, más su `CREATE TABLE` en `src/pipeline/carga.py`) y, si hace falta, una columna o una regla nueva en `src/pipeline/silver.py`.
2. **El pipeline completo, corrido desde Airflow en la nube.** El DAG `pipeline_taxi`, con el código del fork del equipo, corre en el Airflow del Code Editor del anfitrión con `computo = glue_small` y termina con sus cuatro tareas (`correr_bronze`, `correr_silver`, `correr_gold` y `cargar_snowflake`) en `success`.
3. **Conciliación entre capas y respuesta en Snowflake.** Con la tabla de control (`BIGDATA.CONTROL_DEV.WATERMARK`) y consultas sobre bronze, silver y gold, el equipo muestra que las cifras cuadran de una capa a la siguiente, explica cualquier diferencia, y escribe la consulta en Snowflake que responde la pregunta, sobre la tabla del equipo en `BIGDATA.DEV`.
4. **Costo y calidad documentados.** Un informe corto con lo que costó correr el pipeline (créditos de Snowflake y tiempo de Glue con los workers usados), la explicación de cómo aseguraron que no llegaran duplicados de silver a gold (con evidencia en Athena) y las reglas de calidad que se aplicaron y lo que detectaron.

La integración a `main` también cuenta (criterio 3, 5 puntos): el cambio llega con un pull request revisado por otro integrante y con los cinco checks del CI en verde (sección 7). Eso no es un entregable aparte: se ve en el PR.

> **Qué quiere decir «con las funciones del equipo».** En la clase 6 se dijo que el pipeline correría en Glue «con las funciones del equipo». Lo que eso significa es **«con el código de su fork»**. En Glue corre el `bronze.py` de la casa, que hace lo mismo que las cuatro funciones de ingesta que escribieron en la clase 5; esas funciones ya no están en el repositorio: se quedaron en el material de las clases 5 y 6 (etiqueta `antes-limpieza-clase07`) y no son parte del pipeline. El código de ustedes vuelve a escena aquí: en `bronze.py` (los metadatos), en `silver.py` (`deduplicar` y lo que necesite su pregunta), en `gold.py` y en `carga.py`.

> **Qué NO es el cambio del equipo.** El gold de la casa (`tarifa_por_milla_por_barrio`: ¿a qué hora y en qué barrio se paga más por milla?) es un ejemplo para aprender la receta. No responde ninguna pregunta del Taller: la suya es otra.

## 3. Calendario

| Fecha | Qué debe estar listo |
|---|---|
| Miércoles 18 de noviembre (clase 6) | Equipo confirmado, pregunta, cambio elegido y `contrato.md` lleno y subido al repositorio |
| Lunes 23 de noviembre (clase 7) | `pipeline_taxi` corre en el Airflow del Code Editor del anfitrión, con `glue_small`, desde el fork del equipo (puede ir todavía sin el cambio propio) |
| Martes 24 de noviembre (clase 8) | El instructor muestra el DAG que resetea todo el entorno (en prod) y el equipo arranca el trabajo del taller; avance revisado en clase: no tiene que estar terminado, pero sí se debe poder mostrar qué funciona y qué falta |
| Domingo 29 de noviembre | Entrega final: release `t2-entrega` publicado antes de las 23:59 |

La clase 8 no tiene defensa en vivo. La revisión del 24 de noviembre sirve para que el instructor le diga a cada equipo si va por buen camino; no se califica por separado.

## 4. Equipos y roles

Los equipos son los mismos del Taller 1, con el mismo anfitrión (el integrante dueño del fork donde vive el trabajo del equipo). Los roles **rotan**: nadie repite el rol que tuvo en el Taller 1. Los roles reparten la responsabilidad; todos los integrantes ejecutan comandos y consultas en su propia cuenta.

| Rol en el Taller 2 | Responde por | Venía de (Taller 1) |
|---|---|---|
| Analista de negocio y cumplimiento | La pregunta, las definiciones (por ejemplo, qué es «un día con lluvia»), que se cumpla el contrato y el informe | Cualquiera de los otros tres |
| Modelador SQL | La conciliación entre capas y la consulta que responde la pregunta | Cualquiera de los otros tres |
| Ingeniero de datos | El cambio en silver o gold | Cualquiera de los otros tres |
| Operador cloud y calidad | Glue, Airflow, el costo, las reglas de calidad y apagar todo al terminar | Cualquiera de los otros tres |

Si el equipo tiene tres integrantes, quien tenga el rol de analista asume también el de modelador. Si hay un solo integrante, asume los cuatro y lo anota en `contrato.md`. La rotación se escribe en el contrato (sección 1) y el equipo la respeta salvo que el instructor autorice un cambio.

### La cuenta de evidencia

Cada integrante tiene su propia cuenta de AWS, pero **la evidencia sale de una sola: la del anfitrión**. Es la cuenta donde corre el fork del equipo y de donde salen las capturas, el costo y los créditos del informe. Reglas:

- **Dónde se corre:** en el Airflow del Code Editor del anfitrión (entorno dev), con `computo = glue_small`. El cómputo por defecto del formulario **no** es Glue: hay que elegir `glue_small` a mano. **Prod no es requisito.**
- **Con qué código:** con el de `main` del fork. Antes de lanzar, el anfitrión hace `cd ~/bigdata && git switch main && git pull`: con un cómputo de Glue en dev, el código que corre es el de su árbol de trabajo (se sube a `code/dev/`), no el de la VM de prod.
- **Los demás integrantes** hacen `git pull` y pueden probar en su propia cuenta si quieren, pero no hace falta para la entrega.
- **Cuidado con el merge.** Un merge a `main` que toque `src/` o `airflow/` **enciende la VM de Airflow de prod** (la prende el workflow Deploy). Después de cada merge, apáguenla con `cd ~/bigdata && make airflow-off`.

### Las tablas del equipo

Desde la clase 7 `BIGDATA.DEV.DAILY_ZONE_METRICS` deja de ser «la tabla»: queda de historia. **Cada equipo nombra sus tablas con el nombre de su equipo** y las crea en `BIGDATA.DEV` (y, si algún día se promueven, en `BIGDATA.PROD`). Por ejemplo, el equipo «Lluvia Norte» llama a su gold `lluvia_norte_rango_distancia` y a su tabla de Snowflake `BIGDATA.DEV.LLUVIA_NORTE_RANGO_DISTANCIA`. Así dos equipos en la misma cuenta de dev no pisan la tabla del otro. La respuesta del equipo sale de esa tabla.

## 5. Antes de empezar

1. Que el pipeline de la clase 7 corra en su cuenta (la del anfitrión). `make estado` lista las carpetas del lake y los jobs de Glue, pero **no consulta la tabla de control**; para eso, en Snowsight:

   ```sql
   USE ROLE BIGDATA_DEV;
   USE WAREHOUSE BIGDATA_WH;
   USE DATABASE BIGDATA;
   SELECT TABLA, CAPA, MES, FILAS, INICIO FROM BIGDATA.CONTROL_DEV.WATERMARK ORDER BY INICIO;
   ```

   Debe haber al menos una fila por paso. Si el rol `BIGDATA_DEV` no existe en su cuenta, falta `make migrar-clase07` ([guía](../clase07/README.md)).
2. Que el anfitrión haya añadido a todos como colaboradores de su fork (así se hizo en el Taller 1).
3. Que todos tengan el fork del anfitrión clonado en el Code Editor, en `~/bigdata`:

```bash
cd ~
git clone https://github.com/<anfitrion>/<repositorio>.git bigdata
cd ~/bigdata
git switch main
git pull
```

Qué hace cada parte: `cd ~` te lleva a tu carpeta personal, para no clonar dentro de otro repositorio; `git clone <dirección> bigdata` descarga el repositorio del equipo en una carpeta llamada `bigdata`; `git switch main` te pone en la rama principal; `git pull` trae los cambios más recientes. Si ya tienes la carpeta `~/bigdata` clonada, salta el clon y haz solo `cd ~/bigdata`, `git switch main` y `git pull`.

## 6. Elegir la pregunta y el cambio

La pregunta debe poder responderse con los datos del pipeline (viajes, zonas, clima) y debe depender de algo que el pipeline hoy **no** calcula. Si el gold de la casa ya la responde tal cual, la pregunta no necesita un cambio propio y hay que ajustarla.

Ejemplos de preguntas y del cambio que exigen:

| Pregunta | Qué no existe hoy | Cambio posible |
|---|---|---|
| ¿Los viajes largos caen más que los cortos cuando llueve? | Una clasificación del viaje por distancia | Columna `rango_distancia` en silver (en `limpiar_viajes` o en `enriquecer`); tu tabla de gold agrega por rango |
| ¿La lluvia de la mañana afecta más que la de la noche? | La lluvia del día junto a la franja horaria | Tu función de gold agrupa por franja del día y por lluvia (`lluvia_mm` llega por `enriquecer`) |
| ¿Se descartan más viajes los días de lluvia? | Cuántos viajes descarta silver cada día | **No es una tabla del pipeline.** Se resuelve como conciliación en SQL: los descartes por tipo se cuentan comparando bronze (las tablas `dev_bronze_*` de Athena, que leen los lotes) con silver (sección 10) |
| ¿Cómo cambia la propina con lluvia fuerte? | Una variable que distinga lluvia fuerte de ligera | Columna `nivel_lluvia` (umbrales escritos en el contrato), en silver o en tu función de gold |

Tres reglas para elegir el cambio. Primera: debe ser **pequeño y verificable**; es mejor una columna bien comprobada que tres a medio hacer. Segunda: debe poder explicarse en dos frases y comprobarse con una consulta de Athena sobre pocas filas. Tercera: debe dejar claro el **grano** de su tabla de gold (qué representa cada fila; por ejemplo, un grupo por `rango_distancia`). Todo esto se acuerda con el instructor al llenar `contrato.md`.

Un cambio que muchos equipos van a considerar: `silver.py` **filtra pero no deduplica**. Los descartes de enero (13 907 viajes) vienen de los filtros, no de duplicados. Deduplicar por `_hash_fila` es justo lo que hace la función `deduplicar` que el equipo debe escribir (entregable 1); no lo cuenten como el cambio de su pregunta.

Si ya firmaron en el contrato una idea que el pipeline no soporta tal cual (una «tabla aparte de descartados» o cambiar la distancia nula a `desconocido`, que el filtro `distancia_mi > 0` ya descarta), acuerden hoy un ajuste con el instructor.

### 6.1 La receta, de punta a punta

Para que el cambio llegue a la respuesta, estos son los pasos, en este orden. Todos los comandos empiezan con `cd ~/bigdata`.

**El banco de trabajo del equipo es el notebook** `curso/clase07/01_construir_paso_a_paso.ipynb` (cópienlo a una carpeta suya, como en la clase 7). Ahí cambian o agregan pasos a cada función, las prueban con `limite="1000"` contra el dev de verdad, y la Celda 35 les dice cuáles difieren de los `.py` (`DISTINTO`): esas son las que copian al archivo. La Celda 36 corre con las funciones del notebook las pruebas que ya existen para `agregar_metadatos` y `deduplicar`.

1. **`bronze.py` y `silver.py`.** Escriban `agregar_metadatos` y `deduplicar` primero en el notebook (Celdas 18 y 27), pruébenlas con `probar_mis_funciones` (Celda 36) y cuando salgan `OK` copien cada función completa a su archivo y borren la marca `# PENDIENTE(equipo)`. Después `make test`: las pruebas existentes de esas dos funciones pasan de `PENDIENTE` a `OK`.
2. **`silver.py` (solo si la pregunta lo necesita).** La columna nueva o la regla, dentro de `limpiar_viajes` o de `enriquecer`. Si el contrato tiene un cambio aquí, sigue valiendo: ahora se ejecuta en el paso gold.
3. **`gold.py`.** Una función nueva que recibe el enriquecido y devuelve su tabla. Súmenla a `TABLAS_GOLD` con un nombre que lleve el de su equipo.
4. **`carga.py`.** El `CREATE TABLE` de su tabla, con las columnas de su gold y los tipos equivalentes (`date` es `DATE`; `string`, `VARCHAR`; `bigint` o `int`, `NUMBER(38,0)`; `double`, `FLOAT`), sumado a `TABLAS_A_CARGAR`. El código solo muestra ese texto: cada equipo **crea su propia tabla a mano, en Snowsight**, ejecutando ese `CREATE TABLE` (con `USE ROLE BIGDATA_DEV; USE WAREHOUSE BIGDATA_WH; USE DATABASE BIGDATA;` antes). Si la tabla falta, `cargar_snowflake` se detiene e imprime el SQL exacto para ejecutar; luego se vuelve a correr.
5. **Comprobar en local.** `make test` en verde (Ruff y las pruebas que ya trae el repositorio, entre ellas las de `agregar_metadatos` y `deduplicar`).
6. **PR, revisión y merge** (sección 7). Después del merge, el anfitrión hace `git switch main && git pull` y apaga la VM de prod si se encendió.
7. **Correr el pipeline.** En el Airflow del Code Editor del anfitrión, `pipeline_taxi` con `computo = glue_small`, `limite = todos` y `mes = 2024-01` (para que la respuesta sea del mes completo; con `limite = 1000` solo se prueba).
8. **La respuesta.** Sale de `BIGDATA.DEV.<TABLA_DE_SU_EQUIPO>`.

Cada consulta de Snowflake del taller empieza igual:

```sql
USE ROLE BIGDATA_DEV;
USE WAREHOUSE BIGDATA_WH;
USE DATABASE BIGDATA;
```

`ACCOUNTADMIN` y `COMPUTE_WH` son los nombres de las clases 1 a 6: con `ACCOUNTADMIN` no se puede crear ni alterar en `BIGDATA.DEV`, y `BIGDATA_WH` es el warehouse que tiene el freno de costo.

Si agregan una columna a una tabla que ya existe en Snowflake, la carga se detiene con `ColumnasDistintas` y dice el `ALTER TABLE` que hace falta (con el tipo que trae el Parquet): ejecútenlo y vuelvan a lanzar el paso `cargar_snowflake`. Las tablas de Athena tienen un esquema fijo: una columna nueva no aparece en ellas si no se recrea la tabla. Para el taller basta con conciliar en Snowflake y con los totales en Athena.

## 7. Flujo de Git mínimo

Todo el trabajo del taller entra a `main` del fork del anfitrión mediante un **pull request (PR)**, es decir, una solicitud para que otros revisen los cambios antes de incorporarlos. Nadie sube directamente a `main`. Los comandos van en la terminal del Code Editor y todos empiezan con `cd ~/bigdata`, para que no dependan de en qué carpeta estaba la terminal.

### 7.1 Crear una rama

```bash
cd ~/bigdata
git switch main
git pull
git switch -c t2-nivel-lluvia
```

- `git switch main` y `git pull` parten de la versión más reciente del equipo.
- `git switch -c t2-nivel-lluvia` crea una rama nueva con ese nombre y se mueve a ella. Una **rama** es una línea de trabajo paralela: lo que hagas en ella no toca `main` hasta que lo apruebes. Usa un nombre corto que diga qué cambia.

**Debes ver:** `Switched to a new branch 't2-nivel-lluvia'`.

### 7.2 Hacer el cambio y comprobarlo en local

Edita `src/pipeline/silver.py` o `src/pipeline/gold.py`. Antes de subir nada, comprueba que todo pasa:

```bash
cd ~/bigdata
make test
```

`make test` ejecuta Ruff (revisa estilo y errores evidentes) y pytest (corre las pruebas que ya trae el repositorio). Es lo mismo que ejecutará GitHub después; si falla aquí, fallará allá.

**Debes ver:** al final, algo como `N passed` sin ninguna línea `FAILED`.

### 7.3 Guardar el cambio (commit)

```bash
cd ~/bigdata
git status
git add src/pipeline/silver.py
git commit -m "Agrega NIVEL_LLUVIA a silver"
```

- `git status` lista qué archivos cambiaron; revísalo antes de guardar.
- `git add <archivos>` marca exactamente qué entra al commit. Escribe los archivos uno por uno en lugar de `git add -A`, así no subes por accidente archivos que no querías (por ejemplo, `.env`).
- `git commit -m "<mensaje>"` guarda ese punto de la historia con un mensaje que diga **qué** cambió, en una frase.

Si Git responde `Please tell me who you are`, configúralo una sola vez: `git config --global user.name "Tu Nombre"` y `git config --global user.email "tu-correo@ejemplo.com"`, y repite el commit.

### 7.4 Subir la rama (push)

```bash
cd ~/bigdata
git push -u origin t2-nivel-lluvia
```

`git push` envía la rama al repositorio del equipo en GitHub (`origin`). La opción `-u` la enlaza con la rama remota, de modo que los siguientes `git push` no necesitan más argumentos.

### 7.5 Abrir el pull request y esperar el CI

En GitHub (navegador), en el repositorio del equipo:

1. Haz clic en **Compare & pull request** en el aviso amarillo que aparece tras el push.
2. Comprueba que **base repository** sea el fork del equipo y que la base sea `main`. En un fork, GitHub a veces propone como destino el repositorio original del curso; si es así, cámbialo.
3. Escribe un título y una descripción de dos o tres frases: qué cambia y por qué lo necesita la pregunta. Haz clic en **Create pull request**.
4. Espera a que terminen los **checks** (el CI: la verificación automática). Deben quedar en verde los cinco: *Ruff y pytest*, *Integridad de los DAGs de Airflow*, *Terraform fmt y validate* (infra/aws), *Terraform fmt y validate* (infra/snowflake) y *Terraform plan* (infra/aws).

Si un check sale en rojo, abre **Details**, lee el error, corrígelo en tu rama, repite 7.2, 7.3 y haz `git push` (el PR se actualiza solo). No avances hasta que estén en verde.

### 7.6 Revisión y merge

Otro integrante (no quien escribió el cambio) revisa el PR: abre la pestaña **Files changed**, lee el cambio y aprueba con **Review changes > Approve** (un comentario solo no cuenta para el criterio 3). Cuando el CI esté en verde y haya revisión, quien escribió el cambio hace clic en **Merge pull request** y luego en **Confirm merge**. El merge incorpora la rama a `main`.

Después del merge, el workflow **Deploy** (pestaña **Actions**) publica el código nuevo y los DAGs de **prod** y, si cambiaron `src/` o `airflow/`, enciende la VM de Airflow de prod. Espera a que termine en verde. Para la evidencia del taller no se usa esa VM: se usa el Airflow del Code Editor del anfitrión, que corre el código de su árbol de trabajo, así que hay que traer `main`. En la terminal del anfitrión:

```bash
cd ~/bigdata
git switch main
git pull
make airflow-off
```

`make airflow-off` apaga la VM de prod si el Deploy la encendió (si ya estaba apagada, no pasa nada).

### 7.7 Publicar la entrega (release)

Cuando todo esté en `main`, el anfitrión crea el **release**, que fija una etiqueta sobre la versión exacta que se califica. En GitHub: **Releases > Draft a new release > Choose a tag**, escribe `t2-entrega`, haz clic en **Create new tag**, y luego en **Publish release**. Lo que esté en `main` en el momento de publicar el release es lo que se evalúa. Los cambios posteriores no cuentan.

## 8. Qué se entrega exactamente y dónde

Todo en la rama `main` del fork del anfitrión, y lo que no es código en una carpeta `taller2/` en la raíz del repositorio. Para crearla y traer el contrato (que está en `curso/taller2/contrato.md`), una sola vez:

```bash
cd ~/bigdata
mkdir -p taller2 && cp curso/taller2/contrato.md taller2/
```

| Archivo | Contenido |
|---|---|
| `taller2/contrato.md` | El contrato lleno el 18 de nov., actualizado si algo cambió (con una nota de qué cambió y por qué) |
| `src/pipeline/bronze.py`, `silver.py`, `gold.py` y `carga.py` | El cambio del equipo: `agregar_metadatos`, `deduplicar`, la tabla de gold propia y su `CREATE TABLE` |
| `taller2/conciliacion.sql` | Las consultas que comparan filas y cifras entre bronze, silver, gold y Snowflake, con un comentario que interprete cada resultado |
| `taller2/respuesta.sql` | La consulta de Snowflake que responde la pregunta, con la cifra final en un comentario |
| `taller2/informe.md` | Una a dos páginas: la respuesta a la pregunta en lenguaje claro, la conciliación resumida, el costo y la calidad de datos (sección 9) |
| `taller2/evidencia/` | Capturas, todas de la cuenta del anfitrión: el PR con el CI en verde, el DAG `pipeline_taxi` del Airflow del Code Editor con las cuatro tareas en `success` (y `computo = glue_small` en los parámetros), el job de Glue terminado, el resultado de `respuesta.sql` y las capturas de las consultas de Athena de la sección 9 (antes, después y reproceso) |
| Coevaluación | Una por integrante, con el enlace que dé el instructor |

Además: el PR del cambio debe aparecer fusionado (*merged*) en el historial del repositorio, y el release `t2-entrega` debe estar publicado.

## 9. Qué lleva el informe de costo y calidad

**Costo.** Los créditos de Snowflake que gastó el equipo en el taller (misma consulta de `costos.md` del Taller 1, con la fecha ajustada) y, para Glue, el trabajo que lanzaron: con cuántos workers, cuánto duró y cuántos meses procesó. Si corrieron con `glue_small` (2 workers) y con `glue_medium` (4), comparen los tiempos y digan si duplicar los workers redujo el tiempo a la mitad (la clase 7 trae una tabla de dimensionamiento con tiempos reales para comparar). Termina con una frase: ¿qué configuración elegirían para correrlo cada mes y por qué?

### Calidad de datos: cómo aseguraron que no llegaran duplicados de silver a gold

Es la parte que más pesa en la nota (25 puntos). La explicación debe poder repetirla otro equipo, con cifras. Debe cubrir cinco puntos:

1. **Qué hace su `deduplicar` y por qué en ese orden.** Qué columna usa (`_hash_fila`), cuál fila conserva entre las repetidas, qué hace `deduplicar` y por qué la casa la aplica a las tres tablas de silver después de limpiarlas: así el cruce de `enriquecer`, en el paso gold, ya no multiplica.
2. **Evidencia antes y después, con Athena.** En silver, `COUNT(*)` frente a `COUNT(DISTINCT _hash_fila)`: deben ser iguales. Y las filas de silver (`COUNT(*)`) contra la suma de `viajes` en gold y en Snowflake. Peguen la consulta, el resultado y una línea que lo interprete. Para tener «antes» y «después»: (1) escriban `agregar_metadatos`, reseteen dev (y vuelvan a crear su tabla en Snowsight) y corran el mes; (2) con `deduplicar` todavía en `PENDIENTE`, corran de nuevo con `reprocesar` marcado: ese es el «antes» (filas ≠ hashes distintos); (3) escriban `deduplicar` y reprocesen otra vez: ese es el «después». No hace falta otro reset, porque silver lee los dos lotes y los deduplica. Para no gastar Glue, este ejercicio puede hacerse con `limite = 1000`.
3. **Qué pasó al reprocesar un mes.** Corran el mismo mes dos veces (`reprocesar` marcado) y muestren que ni silver ni gold crecen: mismos conteos, misma suma de `viajes`. Bronze sí crea un lote nuevo en cada reproceso; la prueba de que `deduplicar` funciona es que silver no lo hereda.
4. **Una advertencia.** Gold sigue teniendo **el mismo número de filas** aunque haya duplicados, porque gold agrupa; lo que se infla es la columna `viajes`. Por eso se compara la **suma** de `viajes` y no el número de filas: contar filas de gold no detecta el problema.
5. **Qué otras reglas de calidad aplicaron y qué detectaron.** Las del pipeline más las propias, con cuántas filas descartaron y de qué tipo. Una regla que no detectó nada también se reporta: dice que el dato venía bien.

Consultas de ejemplo (Athena, entorno dev; ajusten el mes y el nombre de su tabla de gold):

```sql
-- 1. Silver sin duplicados: las dos cifras deben ser iguales.
SELECT COUNT(*) AS filas, COUNT(DISTINCT _hash_fila) AS hashes_distintos
FROM bigdata_lake.dev_silver_fhvhv
WHERE mes = '2024-01';

-- 2. Cuántas filas están repetidas y cuántas veces (vacío si todo está bien).
SELECT _hash_fila, COUNT(*) AS veces
FROM bigdata_lake.dev_silver_fhvhv
WHERE mes = '2024-01'
GROUP BY _hash_fila
HAVING COUNT(*) > 1
ORDER BY veces DESC
LIMIT 20;

-- 3. Silver a gold: cada lado debe dar la misma suma de viajes
--    (filas de silver contra suma de viajes de gold).
SELECT (SELECT COUNT(*) FROM bigdata_lake.dev_silver_fhvhv WHERE mes = '2024-01') AS filas_silver,
       (SELECT SUM(viajes) FROM bigdata_lake.dev_gold_tarifa_por_milla_barrio WHERE mes = '2024-01') AS viajes_gold;
```

La suma de `viajes` de Snowflake se compara con `SELECT SUM(VIAJES) FROM BIGDATA.DEV.<TABLA_DE_SU_EQUIPO>;` (con el `USE` de la sección 6.1). Las consultas de ejemplo usan la tabla de gold de la casa. Con su propia tabla, comparen las filas de silver (Athena) contra `SELECT SUM(VIAJES) FROM BIGDATA.DEV.<TABLA_DE_SU_EQUIPO>` en Snowflake, si su tabla cuenta viajes. Si no los cuenta, la evidencia de duplicados se hace con la tabla de la casa, que se calcula con la misma corrida. Si `viajes` de gold es un múltiplo exacto de las filas de silver (×4 tras un reproceso: silver duplica cada tabla y el cruce con zonas y clima multiplica otra vez), la causa es una deduplicación que no está actuando.

## 10. Conciliar y responder con Snowflake

Conciliar es comprobar que las cifras cuadran de una capa a la siguiente. Lo mínimo que se espera:

- **Bronze a silver:** filas de bronze, menos las que silver descartó (cada tipo de descarte contado), igual a las filas de silver. La diferencia debe quedar explicada, no «aproximadamente igual». Ojo: las tablas `dev_bronze_*` de Athena leen **todos los lotes** de bronze (silver también los lee todos); el archivo original completo está en `dev_crudo_fhvhv`. Con `limite` el lote es más pequeño que el crudo, porque el límite se aplica solo en bronze.
- **Silver a gold:** las filas de viajes en silver son iguales a la suma de la columna viajes de gold. (Si no cuadra y es un múltiplo exacto, silver tiene duplicados: revisen `deduplicar`.)
- **Gold a Snowflake:** filas y viajes de la tabla del equipo en Snowflake igual a lo que gold escribió.

**Cómo se usa la tabla de control** (`BIGDATA.CONTROL_DEV.WATERMARK`, una tabla por entorno). Cada paso que termina bien anota una fila; **reprocesar no borra nada**, así que una misma clave puede tener varias filas. Las reglas de lectura:

1. Se toma el **último registro por `(TABLA, CAPA, MES)`**, el de mayor `INICIO`.
2. `TABLA` no lleva el entorno: es `fhvhv`, `taxi_zones`, `clima` o el nombre de su tabla de gold. El valor `prueba_*` es de la práctica de las clases 5 y 6 en `BIGDATA.CONTROL.WATERMARK` (historia): nunca se filtra con `LIKE '%fhvhv%'`.
3. En gold, `FILAS` cuenta **filas de gold** (una por cada grupo de su tabla), no viajes. Los viajes se comparan con `SUM(VIAJES)`.
4. `FILAS` son las filas escritas; `LEIDAS`, las leídas; `COMPUTO`, `LIMITE` y `REPROCESAR` se guardan solo para informar.

```sql
USE ROLE BIGDATA_DEV;
USE WAREHOUSE BIGDATA_WH;
USE DATABASE BIGDATA;

SELECT TABLA, CAPA, MES, FILAS, LEIDAS, COMPUTO, LIMITE, INICIO
FROM BIGDATA.CONTROL_DEV.WATERMARK
QUALIFY ROW_NUMBER() OVER (PARTITION BY TABLA, CAPA, MES ORDER BY INICIO DESC) = 1
ORDER BY CAPA, TABLA, MES;
```

Consultas modelo de Athena (silver y gold, duplicados, factores): `curso/clase07/athena/02_duplicados_y_conciliacion.sql`.

Una consulta de conciliación sin interpretación vale poco: escribe en un comentario qué cuadró, qué no y por qué. La consulta de respuesta (`respuesta.sql`) sale de la tabla que ya conciliaste, y la cifra final debe poder explicarse con una frase al lector del informe. Recuerden las trampas del Taller 1: la lluvia se repite en todas las filas del día, y los promedios de grupos se ponderan.

## 11. Rúbrica

Total: 100 puntos. Cada criterio tiene cuatro niveles: sobresaliente (100 % de los puntos del criterio), logrado (75 %), en proceso (40 %) y no logrado (0 %). Aprobar (60 o más) exige que existan los cuatro entregables aunque sea de forma básica. 

| # | Criterio | Pts | Sobresaliente | Logrado | En proceso | No logrado |
|---|---|---|---|---|---|---|
| 1 | Pregunta y contrato (`contrato.md`) | 10 | Pregunta específica y medible, cambio justificado por la pregunta, riesgos reales | Pregunta clara; la relación con el cambio es correcta pero se explica poco | Pregunta vaga o cambio que no la afecta | No hay contrato |
| 2 | El cambio del equipo (metadatos, deduplicado y tabla de gold propia) | 20 | `agregar_metadatos` y `deduplicar` con sus pruebas en `OK`, y una tabla de gold propia correcta y legible, con decisiones (umbrales, nulos) escritas; el pipeline en Glue produce la tabla esperada | Todo correcto y legible; faltan decisiones por escribir | Funciona solo en parte (por ejemplo, falla con nulos, o una de las dos funciones sigue `PENDIENTE`) | No hay cambio, o no corre |
| 3 | PR revisado y CI en verde | 5 | PR fusionado con los cinco checks en verde y aprobado por otro integrante | Sin revisión de otro integrante, o con un check en rojo que se corrigió después del merge | PR sin fusionar, o checks en rojo al fusionar | Sin PR |
| 4 | Pipeline en Glue desde Airflow | 20 | Run completo de `pipeline_taxi` (`glue_small`) con las cuatro tareas en `success`, con el cambio propio, parámetros (`computo`, `limite`, `mes`) anotados y evidencia de la cuenta del anfitrión | Run completo con el cambio, evidencia parcial | Corre en Glue pero sin el cambio propio, o con tareas fallidas | No hay corrida en Glue |
| 5 | Conciliación y respuesta en Snowflake | 20 | Tres cruces (bronze a silver, silver a gold, gold a Snowflake) que cuadran o con diferencias explicadas; la consulta responde la pregunta y la cifra se interpreta | Dos cruces correctos; la consulta responde la pregunta | Un cruce, o cifras que no cuadran sin explicación | No hay conciliación o la consulta no responde |
| 6 | Costo y calidad de datos | 25 | Créditos y tiempo medidos, comparación de configuración y una explicación de cómo aseguraron que no llegaran duplicados de silver a gold, con evidencia (consultas de Athena antes y después, filas de silver iguales a la suma de `viajes` de gold y de Snowflake, y reproceso de un mes sin crecimiento) y la configuración que elegirían cada mes, con la razón | Costo medido y explicación de la deduplicación con evidencia parcial; falta la comparación de configuración o la decisión | Cifras de costo sin medir (estimadas), o deduplicación explicada sin evidencia | No hay informe |

**Cómo se mide cada cosa.** «Checks en verde» y «aprobado por otro integrante» se ven en el PR; «las cuatro tareas en `success`» se ve en la cuadrícula del DAG `pipeline_taxi` en el Airflow del Code Editor del anfitrión; «cuadra» significa que las dos cifras son iguales o que la diferencia está explicada fila por fila (descartes contados por tipo). Quien califica abre el release `t2-entrega` y verifica estos puntos con la evidencia y con lo que hay en el repositorio.

**Participación.** La nota del equipo se multiplica por un factor de entre 0.7 y 1.0 según la coevaluación y el historial de commits de cada integrante.

**Entrega tardía.** Un release publicado después del límite descuenta 10 puntos por cada día de retraso, hasta un máximo de 30.

## 12. Costo: apagar y respetar el límite

Mientras trabajan, esto cuesta dinero cuando está encendido: el **Code Editor** y la **VM de Airflow de prod**. Glue y Snowflake solo cobran mientras ejecutan un job o una consulta.

- **Al terminar cada sesión, apaguen.** Sigan [Apagar y encender](../../docs/cada-sesion.md): cierran el túnel (Ctrl+C), `make airflow-off`, `make airflow-local-down` y comprueban con `make estado` que Airflow diga `stopped`, que ningún job de Glue esté en `RUNNING` y que el warehouse esté `SUSPENDED`. **Después de cada merge a `main`, la VM de prod puede quedar encendida** (el Deploy la enciende): `make airflow-off`.
- **El límite de AWS.** El presupuesto mensual es de 50 USD por defecto. Al 60 % del gasto real AWS impide iniciar jobs de Glue y máquinas virtuales, y detiene la VM de Airflow de prod. Si les pasa, `make desbloquear` lo revierte, pero eso significa que ya gastaron mucho más de lo previsto: revisen qué quedó corriendo.
- **El límite de Snowflake.** El resource monitor de su cuenta corta el uso al llegar a su cuota de créditos. Se amplía con `make snowflake-ampliar-cuota CUOTA=<créditos>` solo si de verdad lo necesitan, y se anota en el informe.
- **Corran lo mínimo necesario.** Prueben con un mes (por ejemplo, `mes=2024-01`) y con `limite = 1000` antes de lanzar el mes completo (`limite = todos`). Un año completo cuesta y toma mucho más tiempo, y no es necesario para el taller. Y `resetear_entorno` borra **todo** el entorno: úsenlo solo si de verdad quieren empezar de cero, y con la confirmación escrita.
- **La prueba de Snowflake vence el 3 de diciembre.** Después de entregar, siguen las instrucciones de la clase 8 para apagar las cuentas y no pagar.

## 13. Errores comunes

| Qué pasa | Por qué | Qué hacer |
|---|---|---|
| El PR propone como destino el repositorio del curso | En un fork GitHub sugiere el repositorio original | Cambia **base repository** al fork del equipo |
| El CI falla con un error de formato | Ruff revisa el formato | Corre `make test` en local; para formatear, `ruff format src tests` |
| El run de Glue no usa el cambio | El anfitrión no hizo `git pull` de `main` antes de lanzar (en dev, Glue corre el código de su árbol de trabajo) | `cd ~/bigdata && git switch main && git pull` y vuelve a lanzar |
| Todas las tareas terminan en verde pero dicen `SE SALTÓ` | La tabla de control ya tiene ese mes y `reprocesar` no está marcado | Es lo esperado. Para repetir a propósito, marca `reprocesar` (y recuerda que bronze crea un lote nuevo; `deduplicar` debe estar escrito) |
| La carga falla con `ColumnasDistintas` | La tabla de Snowflake no tiene una columna que gold sí trae | Ejecuta el `ALTER TABLE` que sugiere el error y vuelve a lanzar `cargar_snowflake` |
| Los viajes de gold son un múltiplo exacto de silver (×4), o ×8 la cifra limpia | `deduplicar` no está escrito y se reprocesó un mes | Escribe `agregar_metadatos` y `deduplicar`, haz `resetear_entorno` en dev y repite el pipeline |
| Las cifras de silver y gold no cuadran | Gold agrega, y lo que se compara no es la misma magnitud | Compara la suma de viajes, no el número de filas (con duplicados gold tiene las mismas filas y `viajes` inflado) |
| Pierden una hora buscando un error de Glue | El error está en los logs, no en Airflow | En Airflow abre el log de la tarea y, desde ahí, el enlace al run de Glue; revisa los logs de ese run |

## 14. Si algo no está claro

Pregunten en clase o por el canal del curso antes de decidir por su cuenta algo que cambie el alcance. 
