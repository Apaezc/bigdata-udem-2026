# Taller 2 · Tu propia pregunta sobre la lluvia y los viajes de NYC, respondida con tu pipeline

Big Data e Ingeniería de Datos (UdeM) · Se presenta en la clase 6, el 18 de noviembre de 2026 · **Entrega final: domingo 29 de noviembre de 2026, 23:59 (hora de Colombia)** · Mismos equipos del Taller 1

El Taller 2 vale 100 puntos y, junto con el Taller 1, forma la nota de talleres, 50 % cada uno. Se trabaja solo con GitHub, el Code Editor, AWS y Snowflake. La única ayuda es el instructor.

## 1. Para qué es este taller

En el Taller 1 respondieron preguntas sobre una tabla que ya venía lista. En las clases 5, 6 y 7 construyeron, con sus propias manos, el pipeline que produce esa tabla: ingesta a bronze, limpieza en silver, resumen en gold, un orquestador que lo ejecuta en orden y una tabla de control que registra lo que ya se procesó. Este taller les pide algo distinto: usar ese pipeline como herramienta para responder **una pregunta que ustedes mismos eligen** sobre la lluvia y los viajes de NYC, y demostrar que la respuesta es confiable.

Una respuesta confiable no es solo un número. Es un número que se puede reproducir (porque el código está probado y versionado), que viene de un pipeline que corre completo en la nube, y que cuadra con lo que había en cada capa del camino. Ese es el problema real del taller: **¿cómo sé que la cifra que le voy a dar a alguien es la correcta?** Las herramientas (pytest, Git, Glue, la tabla de control) están al servicio de esa pregunta.

## 2. Los cinco entregables

1. **Una transformación propia en silver o en gold.** Cada equipo agrega al pipeline un cambio que su pregunta necesita: una columna nueva, una regla de limpieza o un agregado distinto. El cambio vive en `src/pipeline/silver.py` o en `src/pipeline/gold.py`.
2. **Pruebas del cambio, con CI en verde.** El cambio tiene pruebas con pytest en `tests/`, y el pull request que lo incorpora pasa los checks automáticos de GitHub (Ruff, pytest y la integridad de los DAGs).
3. **El pipeline completo en Glue, lanzado desde Airflow.** Con el mismo DAG de la clase 7, cambiando solo el parámetro de cómputo, el pipeline corre en Glue con las funciones del equipo y termina con todas las tareas en `success`.
4. **Conciliación entre capas y respuesta en Snowflake.** Con la tabla de control (`BIGDATA.CONTROL.WATERMARK`) y consultas sobre bronze, silver y gold, el equipo muestra que las cifras cuadran de una capa a la siguiente, explica cualquier diferencia, y escribe la consulta en Snowflake que responde la pregunta.
5. **Costo y calidad documentados.** Un informe corto con lo que costó correr el pipeline (créditos de Snowflake y tiempo de Glue con los workers usados), las reglas de calidad que se aplicaron y lo que detectaron.

## 3. Calendario

| Fecha | Qué debe estar listo |
|---|---|
| Miércoles 18 de noviembre (clase 6) | Equipo confirmado, pregunta, cambio elegido y `contrato.md` lleno y subido al repositorio |
| Lunes 23 de noviembre (clase 7) | El pipeline corre en Glue, desde Airflow, con las funciones del equipo (aún sin el cambio propio si no está terminado) |
| Martes 24 de noviembre (clase 8) | Avance revisado en clase por el instructor; no tiene que estar terminado, pero sí se debe poder mostrar qué funciona y qué falta |
| Domingo 29 de noviembre | Entrega final: release `t2-entrega` publicado antes de las 23:59 |

La clase 8 no tiene defensa en vivo. La revisión del 24 de noviembre sirve para que el instructor le diga a cada equipo si va por buen camino; no se califica por separado.

## 4. Equipos y roles

Los equipos son los mismos del Taller 1, con el mismo anfitrión (el integrante dueño del fork donde vive el trabajo del equipo). Los roles **rotan**: nadie repite el rol que tuvo en el Taller 1. Los roles reparten la responsabilidad; todos los integrantes ejecutan comandos y consultas en su propia cuenta.

| Rol en el Taller 2 | Responde por | Venía de (Taller 1) |
|---|---|---|
| Analista de negocio y cumplimiento | La pregunta, las definiciones (por ejemplo, qué es «un día con lluvia»), que se cumpla el contrato y el informe | Cualquiera de los otros tres |
| Modelador SQL | La conciliación entre capas y la consulta que responde la pregunta | Cualquiera de los otros tres |
| Ingeniero de datos | El cambio en silver o gold y sus pruebas | Cualquiera de los otros tres |
| Operador cloud y calidad | Glue, Airflow, el costo, las reglas de calidad y apagar todo al terminar | Cualquiera de los otros tres |

Si el equipo tiene tres integrantes, quien tenga el rol de analista asume también el de modelador. Si hay un solo integrante, asume los cuatro y lo anota en `contrato.md`. La rotación se escribe en el contrato (sección 1) y el equipo la respeta salvo que el instructor autorice un cambio.

## 5. Antes de empezar

1. Que el pipeline de la clase 7 corra en su cuenta: `make estado` debe mostrar que las capas existen y que la tabla de control responde.
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

La pregunta debe poder responderse con los datos del pipeline (viajes, zonas, clima) y debe depender de algo que el pipeline hoy **no** calcula. Si el gold actual ya la responde tal cual, la pregunta no necesita un cambio propio y hay que ajustarla.

Ejemplos de preguntas y del cambio que exigen:

| Pregunta | Qué no existe hoy | Cambio posible |
|---|---|---|
| ¿Los viajes largos caen más que los cortos cuando llueve? | Una clasificación del viaje por distancia | Columna `RANGO_DISTANCIA` en silver; gold agrega por rango |
| ¿La lluvia de la mañana afecta más que la de la noche? | La hora del día en el resumen | Columna `FRANJA_HORARIA` en silver y un agregado por franja en gold |
| ¿Se cancelan o se descartan más viajes los días de lluvia? | Cuántos viajes descarta la limpieza cada día | Regla en silver que cuenta los descartados por día y los deja en una tabla aparte |
| ¿Cómo cambia la propina con lluvia fuerte? | Una variable que distinga lluvia fuerte de ligera | Columna `NIVEL_LLUVIA` en silver (umbrales escritos en el contrato) |

Dos reglas para elegir el cambio. Primera: debe ser **pequeño y verificable**; es mejor una columna bien probada que tres a medio hacer. Segunda: debe poder explicarse en dos frases y probarse con pocas filas escritas a mano en el test. Todo esto se acuerda con el instructor al llenar `contrato.md`.

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

Edita `src/pipeline/silver.py` o `src/pipeline/gold.py` y escribe la prueba en `tests/`. Antes de subir nada, comprueba que todo pasa:

```bash
cd ~/bigdata
make test
```

`make test` ejecuta Ruff (revisa estilo y errores evidentes) y pytest (corre las pruebas). Es lo mismo que ejecutará GitHub después; si falla aquí, fallará allá.

**Debes ver:** al final, algo como `N passed` sin ninguna línea `FAILED`.

### 7.3 Guardar el cambio (commit)

```bash
cd ~/bigdata
git status
git add src/pipeline/silver.py tests/test_silver.py
git commit -m "Agrega NIVEL_LLUVIA a silver con su prueba"
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

1. Pulsa **Compare & pull request** en el aviso amarillo que aparece tras el push.
2. Comprueba que **base repository** sea el fork del equipo y que la base sea `main`. En un fork, GitHub a veces propone como destino el repositorio original del curso; si es así, cámbialo.
3. Escribe un título y una descripción de dos o tres frases: qué cambia y por qué lo necesita la pregunta. Pulsa **Create pull request**.
4. Espera a que terminen los **checks** (el CI: la verificación automática). Deben quedar en verde los cinco: *Ruff y pytest*, *Integridad de los DAGs de Airflow*, *Terraform fmt y validate* (infra/aws), *Terraform fmt y validate* (infra/snowflake) y *Terraform plan* (infra/aws).

Si un check sale en rojo, abre **Details**, lee el error, corrígelo en tu rama, repite 7.2, 7.3 y haz `git push` (el PR se actualiza solo). No avances hasta que estén en verde.

### 7.6 Revisión y merge

Otro integrante (no quien escribió el cambio) revisa el PR: abre la pestaña **Files changed**, lee el cambio y deja al menos un comentario o una aprobación con **Review changes > Approve**. Cuando el CI esté en verde y haya revisión, quien escribió el cambio pulsa **Merge pull request** y luego **Confirm merge**. El merge incorpora la rama a `main`.

Después del merge, el workflow **Deploy** (pestaña **Actions**) publica el código nuevo y los DAGs en AWS; espera a que termine en verde antes de lanzar el pipeline en Glue. En la terminal, vuelve a `main`:

```bash
cd ~/bigdata
git switch main
git pull
```

### 7.7 Publicar la entrega (release)

Cuando todo esté en `main`, el anfitrión crea el **release**, que fija una etiqueta sobre la versión exacta que se califica. En GitHub: **Releases > Draft a new release > Choose a tag**, escribe `t2-entrega`, pulsa **Create new tag**, y luego **Publish release**. Lo que esté en `main` en el momento de publicar el release es lo que se evalúa. Los cambios posteriores no cuentan.

## 8. Qué se entrega exactamente y dónde

Todo en la rama `main` del fork del anfitrión, y lo que no es código en una carpeta `taller2/` en la raíz del repositorio.

| Archivo | Contenido |
|---|---|
| `taller2/contrato.md` | El contrato lleno el 18 de nov., actualizado si algo cambió (con una nota de qué cambió y por qué) |
| `src/pipeline/silver.py` o `src/pipeline/gold.py` | La transformación propia |
| `tests/test_silver.py` o `tests/test_gold.py` | Las pruebas de la transformación (o un archivo nuevo en `tests/` con las del equipo) |
| `taller2/conciliacion.sql` | Las consultas que comparan filas y cifras entre bronze, silver, gold y Snowflake, con un comentario que interprete cada resultado |
| `taller2/respuesta.sql` | La consulta de Snowflake que responde la pregunta, con la cifra final en un comentario |
| `taller2/informe.md` | Una a dos páginas: la respuesta a la pregunta en lenguaje claro, la conciliación resumida, el costo y la calidad (sección 9) |
| `taller2/evidencia/` | Capturas: el PR con el CI en verde, el DAG con todas las tareas en `success`, el job de Glue terminado y el resultado de `respuesta.sql` |
| Coevaluación | Una por integrante, con el enlace que dé el instructor |

Además: el PR del cambio debe aparecer fusionado (*merged*) en el historial del repositorio, y el release `t2-entrega` debe estar publicado.

## 9. Qué lleva el informe de costo y calidad

**Costo.** Los créditos de Snowflake que gastó el equipo en el taller (misma consulta de `costos.md` del Taller 1, con la fecha ajustada) y, para Glue, el trabajo que lanzaron: con cuántos workers, cuánto duró y cuántos meses procesó. Si corrieron con 2 y con 4 workers, comparen los tiempos y digan si duplicar los workers redujo el tiempo a la mitad. Termina con una frase: ¿qué configuración elegirían para correrlo cada mes y por qué?

**Calidad.** Qué reglas aplicó el equipo (las dadas por el pipeline más las propias, si las hay), qué detectaron (cuántas filas descartadas, de qué tipo) y qué decisión tomaron con eso. Una regla que no detectó nada también se reporta: dice que el dato venía bien.

## 10. Conciliar y responder con Snowflake

Conciliar es comprobar que las cifras cuadran de una capa a la siguiente. Lo mínimo que se espera:

- **Bronze a silver:** filas de bronze, menos las que silver descartó (cada tipo de descarte contado), igual a las filas de silver. La diferencia debe quedar explicada, no «aproximadamente igual».
- **Silver a gold:** la suma de viajes en silver es igual a la suma de la columna de viajes en gold.
- **Gold a Snowflake:** filas y viajes de la tabla en Snowflake igual a lo que gold escribió. La tabla `BIGDATA.CONTROL.WATERMARK` guarda las filas que registró cada capa; la consulta debe cruzarla con lo que se cuenta directamente.

Una consulta de conciliación sin interpretación vale poco: escribe en un comentario qué cuadró, qué no y por qué. La consulta de respuesta (`respuesta.sql`) sale de la tabla que ya conciliaste, y la cifra final debe poder explicarse con una frase al lector del informe. Recuerden las trampas del Taller 1: la lluvia se repite en todas las filas del día, y los promedios de grupos se ponderan.

## 11. Rúbrica

Total: 100 puntos. Cada criterio tiene cuatro niveles: sobresaliente (100 % de los puntos del criterio), logrado (75 %), en proceso (40 %) y no logrado (0 %). Aprobar (60 o más) exige que existan los cinco entregables aunque sea de forma básica. 

| # | Criterio | Pts | Sobresaliente | Logrado | En proceso | No logrado |
|---|---|---|---|---|---|---|
| 1 | Pregunta y contrato (`contrato.md`) | 10 | Pregunta específica y medible, cambio justificado por la pregunta, riesgos reales | Pregunta clara; la relación con el cambio es correcta pero se explica poco | Pregunta vaga o cambio que no la afecta | No hay contrato |
| 2 | Transformación propia en silver o gold | 20 | Cambio correcto, legible, con decisiones (umbrales, nulos) escritas; produce la columna o regla esperada en el Glue | Correcto y legible; faltan decisiones por escribir | Funciona solo en parte (por ejemplo, falla con nulos) | No hay cambio, o no corre |
| 3 | Pruebas y CI | 15 | Al menos tres pruebas (caso normal, caso límite y caso con datos malos), PR fusionado con los cinco checks en verde y revisado por otro integrante | Pruebas correctas pero sin caso con datos malos, o sin revisión de otro integrante | Pruebas que no fallarían si el cambio estuviera mal; checks en verde | Sin pruebas, o merge con CI en rojo |
| 4 | Pipeline en Glue desde Airflow | 20 | Run completo con todas las tareas en `success`, con el cambio propio, parámetros (`computo`, `mes`) anotados y evidencia | Run completo con el cambio, evidencia parcial | Corre en Glue pero sin el cambio propio, o con tareas fallidas | No hay corrida en Glue |
| 5 | Conciliación y respuesta en Snowflake | 20 | Tres cruces (bronze a silver, silver a gold, gold a Snowflake) que cuadran o con diferencias explicadas; la consulta responde la pregunta y la cifra se interpreta | Dos cruces correctos; la consulta responde la pregunta | Un cruce, o cifras que no cuadran sin explicación | No hay conciliación o la consulta no responde |
| 6 | Costo y calidad | 15 | Créditos y tiempo medidos, comparación de configuración, reglas de calidad con lo que detectaron y una decisión justificada | Costo medido y reglas descritas; falta la comparación o la decisión | Cifras sin medir (estimadas) | No hay informe |

**Cómo se mide cada cosa.** «Checks en verde» se ve en el PR; «todas las tareas en `success`» se ve en la cuadrícula del DAG en Airflow; «cuadra» significa que las dos cifras son iguales o que la diferencia está explicada fila por fila (descartes contados por tipo). Quien califica abre el release `t2-entrega` y verifica estos puntos con la evidencia y con lo que hay en el repositorio.

**Participación.** La nota del equipo se multiplica por un factor de entre 0.7 y 1.0 según la coevaluación y el historial de commits de cada integrante.

**Entrega tardía.** Un release publicado después del límite descuenta 10 puntos por cada día de retraso, hasta un máximo de 30.

## 12. Costo: apagar y respetar el límite

Mientras trabajan, esto cuesta dinero cuando está encendido: el **Code Editor** y la **VM de Airflow de prod**. Glue y Snowflake solo cobran mientras ejecutan un job o una consulta.

- **Al terminar cada sesión, apaguen.** Sigan [Apagar y encender](../../docs/cada-sesion.md): cierran el túnel (Ctrl+C), `make airflow-off`, `make airflow-local-down` y comprueban con `make estado` que Airflow diga `stopped`, que ningún job de Glue esté en `RUNNING` y que el warehouse esté `SUSPENDED`.
- **El límite de AWS.** El presupuesto mensual es de 50 USD por defecto. Al 60 % del gasto real AWS impide iniciar jobs de Glue y máquinas virtuales, y detiene la VM de Airflow de prod. Si les pasa, `make desbloquear` lo revierte, pero eso significa que ya gastaron mucho más de lo previsto: revisen qué quedó corriendo.
- **El límite de Snowflake.** El resource monitor de su cuenta corta el uso al llegar a su cuota de créditos. Se amplía con `make snowflake-ampliar-cuota CUOTA=<créditos>` solo si de verdad lo necesitan, y se anota en el informe.
- **Corran lo mínimo necesario.** Prueben con un mes (por ejemplo, `mes=2024-01`) antes de lanzar más. Un año completo cuesta y toma mucho más tiempo, y no es necesario para el taller.
- **La prueba de Snowflake vence el 3 de diciembre.** Después de entregar, siguen las instrucciones de la clase 8 para apagar las cuentas y no pagar.

## 13. Errores comunes

| Qué pasa | Por qué | Qué hacer |
|---|---|---|
| El PR propone como destino el repositorio del curso | En un fork GitHub sugiere el repositorio original | Cambia **base repository** al fork del equipo |
| El CI falla con un error de formato | Ruff revisa el formato | Corre `make test` en local; para formatear, `ruff format src tests` |
| La prueba pasa en local y falla en CI | Dependen de un archivo o variable que solo existe en tu entorno | Que la prueba cree sus propios datos con pocas filas escritas a mano |
| El run de Glue no usa el cambio | Se lanzó antes de que terminara el workflow **Deploy** | Espera a que **Deploy** quede en verde y vuelve a lanzar |
| Las cifras de silver y gold no cuadran | Gold agrega, y lo que se compara no es la misma magnitud | Compara la suma de viajes, no el número de filas |
| Pierden una hora buscando un error de Glue | El error está en los logs, no en Airflow | En Airflow abre el log de la tarea y, desde ahí, el *run id* de Glue; revisa los logs de ese run |

## 14. Si algo no está claro

Pregunten en clase o por el canal del curso antes de decidir por su cuenta algo que cambie el alcance. 
