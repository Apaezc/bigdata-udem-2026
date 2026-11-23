# Clase 8 · Borrador del camino a prod (sale de la clase 7)

Por decisión del autor, llevar el pipeline a prod pasa de la clase 7 a la clase 8 (martes 24 de noviembre). Este borrador conserva, sin perder nada, las slides que se quitaron de los dos decks de la clase 7: la escalera, la rama por persona, el pull request, el CI, el merge, el túnel a la VM, la corrida en prod y su validación.

## Antes de la clase 8 (pendientes del instructor)

- **El camino a prod no se ensayó con el pipeline v2** (TARIFA_POR_MILLA_BARRIO, CONTROL_PROD, secreto `snowflake_prod`). `clase07_medidas.md` solo tiene la corrida de prod del 20 de noviembre con el pipeline anterior. Si no da tiempo de ensayar, la parte de prod la hace el instructor como demostración.
- **La VM necesita `make actualizar-vm`.** `scripts/actualizar-vm.sh` deja la VM apuntando al secreto de prod (`<PREFIX>/snowflake_prod`, rol `BIGDATA_PROD`); se hace una vez por cuenta, después de que el CI/CD publicó el código y con la VM encendida. Sin ese paso, `cargar_snowflake` en prod falla en `exigir_rol_del_entorno`. Orden: `cd ~/bigdata && make airflow-on`, esperar unos 2 minutos, `make actualizar-vm`, y luego `make airflow-tunel`.
- **El Deploy solo publica en la cuenta del anfitrión.** Los demás integrantes empujan al fork del anfitrión, así que su VM no recibe el código ni se enciende. Solo el anfitrión (y el instructor) lanzan prod; los demás siguen la demostración en el proyector.
- **Una rama por persona** (`clase07-a-prod-<tu-nombre>`, creada una sola vez) para que no choquen las ramas de los integrantes en el fork del anfitrión. Solo el anfitrión hace el merge; los demás abren su PR y revisan el del anfitrión (Approve).
- Agregar a este flujo (o a la slide del túnel) la línea: «Si eres el anfitrión: make airflow-on y, la primera vez, make actualizar-vm.»

## Slides del deck completo (113 a 129)


### Deck completo · slide 113: ¿Cómo llevo algo a prod sin que nadie pueda romperlo desde su Code Editor?

*Tipo: seccion · 1 min*

**Notas del orador:** Problema: todo lo que hicimos hasta ahora fue en dev, y desde el Code Editor no se puede correr prod. ¿Cómo llega entonces el código a prod? Por el único camino que deja rastro y exige revisión: un pull request, los checks automáticos, un merge a main y un despliegue que lo hace GitHub Actions, no una persona. El pipeline en prod lo corre un DAG en la VM de Airflow, con el rol BIGDATA_PROD. Hoy hacemos el recorrido completo, en el fork de cada quien. Tiempo: 1 min. Siguiente: La escalera de dev a prod tiene siete peldaños, y prod solo se alcanza por PR y CI/CD.

### Deck completo · slide 114: La escalera de dev a prod tiene siete peldaños, y prod solo se alcanza por PR y CI/CD

*Tipo: titulo_visual · 2 min*

Diagrama: `diagramas/Dc7-4.svg`.

Texto alternativo: Siete peldaños que suben de izquierda a derecha. Los cuatro primeros son dev, desde el Code Editor: notebook y make test, make correr con code_editor, make correr con glue_small y Airflow del Code Editor. Una línea punteada separa dev de prod. Los tres últimos son prod: pull request y CI, merge y Deploy, y el DAG en la VM.

Pie: Cada peldaño cuesta más que el anterior: por eso se prueba abajo.

**Notas del orador:** Esta es la escalera de pruebas, de lo barato a lo caro; cada peldaño debe pasar antes del siguiente. 1: notebook y make test (segundos). 2: make correr con code_editor (minutos, sin costo extra). 3: make correr con glue_small (minutos y centavos). 4: Airflow del Code Editor, que orquesta lo anterior. La línea roja separa dev de prod. 5: el pull request y el CI (ruff, pytest, integridad de los DAGs, Terraform). 6: el merge a main y el workflow Deploy, que publica el código y los DAGs en S3 y enciende la VM de prod. 7: el DAG pipeline_taxi en la VM, con glue_medium y todos los viajes. Lo que sube a prod es lo que está en main, no lo que tienes en tu Code Editor. Tiempo: 2 min. Siguiente: Creas una rama para tu cambio sin tocar main y compruebas que estás en ella.

### Deck completo · slide 115: Creas una rama para tu cambio sin tocar main y compruebas que estás en ella

*Tipo: codigo · 1 min*

```
cd ~/bigdata
git switch main
git pull
git switch -c clase07-a-prod-<tu-nombre>
git branch --show-current
```

**En pantalla:** Debes ver «Switched to a new branch 'clase07-a-prod-<tu-nombre>'» y, al final, el nombre de la rama.

**Notas del orador:** Dónde: la terminal. Problema: no se cambia main directamente; todo entra por una rama y un pull request. git switch main y git pull parten de la versión más reciente del fork. git switch -c crea una rama nueva (con tu nombre, para que no choque con la de otro integrante en el fork del anfitrión) y se mueve a ella; una rama es una línea de trabajo paralela: lo que hagas en ella no toca main hasta que lo apruebes. git branch --show-current imprime en qué rama estás. Error común: «Your local changes would be overwritten»: guarda tus cambios antes (git add y git commit) o muévelos fuera del repositorio. Tiempo: 1 min. Siguiente: Haces un cambio pequeño en src/pipeline/gold.py.

### Deck completo · slide 116: Haces un cambio pequeño en src/pipeline/gold.py

*Tipo: pasos · 1 min*

Ventana: Code Editor.

1. Abre src/pipeline/gold.py con doble clic.
2. Al final escribe una línea de comentario con tu equipo.
3. Presiona Ctrl + S para guardar.

**Notas del orador:** Problema: para recorrer el camino a prod necesitamos un cambio, y debe ser inofensivo. Un comentario en src/ sirve por dos razones: no cambia el comportamiento y, como toca src/, el workflow Deploy sí enciende la VM de prod después del merge (enciende la VM si cambian airflow/ o src/). Es el cambio más pequeño que atraviesa todo el camino. Quien ya empezó su cambio real del Taller puede usar el suyo. Error común: se editó un archivo fuera de src/ o de airflow/: el Deploy no enciende la VM y el DAG de prod no aparece. Tiempo: 1 min. Siguiente: Compruebas el cambio con make test y lo guardas con git add y git commit.

### Deck completo · slide 117: Compruebas el cambio con make test y lo guardas con git add y git commit

*Tipo: codigo · 2 min*

```
cd ~/bigdata
make test
git status
git add src/pipeline/gold.py
git commit -m "Clase 7: comentario de prueba para el camino a prod"
```

**En pantalla:** Escribe los archivos uno por uno en git add: así no subes por accidente algo que no querías.

**Notas del orador:** Entrada: make test ejecuta ruff y pytest, y es lo mismo que ejecutará GitHub después: si falla aquí, fallará allá. git status lista qué archivos cambiaron; debe aparecer solo gold.py. git add marca exactamente qué entra al commit; no se usa git add -A para no subir por accidente archivos como .env. git commit guarda ese punto de la historia con un mensaje que diga qué cambió. Si Git responde «Please tell me who you are», se configura una vez: git config --global user.name "Tu Nombre" y git config --global user.email "tu-correo@ejemplo.com". Tiempo: 2 min. Siguiente: Subes la rama a GitHub con git push; la opción -u la enlaza con la rama remota.

### Deck completo · slide 118: Subes la rama a GitHub con git push; la opción -u la enlaza con la rama remota

*Tipo: codigo · 1 min*

```
cd ~/bigdata
git push -u origin clase07-a-prod-<tu-nombre>
```

**En pantalla:** Debes ver una URL que sugiere abrir un pull request y la línea «Branch 'clase07-a-prod-<tu-nombre>' set up to track».

**Notas del orador:** git push envía la rama a tu fork en GitHub (origin). La opción -u la enlaza con la rama remota, para que los siguientes git push no necesiten más argumentos. Salida esperada: el resumen de objetos enviados y un aviso con la URL «Create a pull request for 'clase07-a-prod-<tu-nombre>' on GitHub». Errores comunes: «Authentication failed» (la autenticación de gh caducó: gh auth login) o «Permission denied»: se está empujando al repositorio equivocado; origin debe ser tu fork. Tiempo: 1 min. Siguiente: Abres un pull request en GitHub.

### Deck completo · slide 119: Abres un pull request en GitHub

*Tipo: pasos · 2 min*

Ventana: GitHub.

1. En tu fork, haz clic en Compare & pull request.
2. Comprueba que la base sea main de tu fork.
3. Escribe dos frases y haz clic en Create pull request.

**Notas del orador:** Dónde: GitHub, en el navegador. Un pull request (PR) es una solicitud para revisar tus cambios antes de incorporarlos a main. En un fork, GitHub a veces propone como destino el repositorio original del curso: hay que cambiar base repository al fork del equipo. Escribe una descripción de dos o tres frases. Al crear el PR arrancan solos los checks del CI. Error común: el PR apunta al repositorio del instructor; se cierra y se abre de nuevo con la base correcta. Tiempo: 2 min. Siguiente: Esperas los cinco checks del CI en verde.

### Deck completo · slide 120: Esperas los cinco checks del CI en verde

*Tipo: pasos · 2 min*

Ventana: GitHub.

1. En el pull request, baja hasta los checks.
2. Espera los cinco en verde, sin ningún rojo.
3. Si uno falla, abre Details y corrige tu rama.

**Notas del orador:** El CI (la verificación automática) corre en GitHub Actions al crear o actualizar el PR: ruff lint y formato, pytest, pytest de los DAGs (necesita Airflow), terraform fmt y validate de infra/aws y de infra/snowflake, y terraform plan de infra/aws. Deben quedar en verde los cinco. Si un check sale rojo, se abre Details, se lee el error, se corrige en la rama y un git push actualiza el PR solo. No se avanza hasta que estén en verde: el merge con CI en rojo no se hace. Tiempo típico: unos minutos; el tiempo exacto se anota en el ensayo. Error común: el check de Terraform plan falla si faltan los secrets AWS_ROLE_ARN o TF_STATE_BUCKET en el fork (make secrets). Tiempo: 2 min. Siguiente: Se aprueba el cambio y se hace el merge.

### Deck completo · slide 121: Se aprueba el cambio y se hace el merge

*Tipo: pasos · 2 min*

Ventana: GitHub.

1. Otro integrante abre Files changed y hace clic en Approve.
2. Haz clic en Merge pull request y en Confirm merge.
3. En Actions, espera el workflow Deploy en verde.

**Notas del orador:** Nadie aprueba su propio cambio: es la segunda barandilla, después del CI. Para esta práctica, quien trabaja solo puede pedir la aprobación al compañero de al lado. Al hacer merge, el cambio entra a main. El workflow Deploy se dispara solo: planea y aplica Terraform (con la guardia de destrucción: aborta si el plan elimina algo), empaqueta src en code/pipeline.zip, sincroniza dags/, code/ y framework/ en S3 y, si el push cambió airflow/ o src/, enciende la VM de Airflow de prod. Ese Deploy es lo que pone en prod el código de main. Error común: el Deploy falla por falta de secrets; el instructor ayuda. Tiempo: 2 min. Siguiente: Apagas el Airflow de dev y abres el túnel, porque los dos usan el puerto 8080.

### Deck completo · slide 122: Apagas el Airflow de dev y abres el túnel, porque los dos usan el puerto 8080

*Tipo: codigo · 1 min*

```
cd ~/bigdata
make airflow-local-down
make airflow-tunel
```

**En pantalla:** El túnel ocupa esta terminal: déjala abierta y abre otra con Terminal > New Terminal.

**Notas del orador:** Problema: la VM de prod no tiene ninguna entrada pública; su UI solo se alcanza por un túnel SSM desde el Code Editor. Y el Airflow de dev y el de prod usan el mismo puerto 8080, así que primero se apaga el de dev. make airflow-tunel abre el túnel y imprime la URL, que es la misma que la de dev. La VM la encendió el Deploy; si no está encendida, make airflow-on. Tarda unos 2 minutos después del Deploy en estar lista. Errores comunes: «El puerto 8080 está ocupado (¿Airflow de dev encendido?)»; «La instancia está stopped. Ejecuta make airflow-on primero»; «No existe la instancia bigdata-airflow»: falta make airflow-habilitar, una sola vez. Tiempo: 1 min. Siguiente: Entras a Airflow de prod por el túnel.

### Deck completo · slide 123: Entras a Airflow de prod por el túnel

*Tipo: pasos · 1 min*

Ventana: Terminal y navegador.

1. Abre otra terminal y escribe make airflow-password.
2. Abre en el navegador la URL del túnel.
3. Entra como admin con la contraseña de prod.

**Notas del orador:** Salida de make airflow-password: «Usuario: admin» y «Contraseña: ...», leídas de Secrets Manager (el secreto <prefijo>/airflow-admin). La contraseña de prod es distinta a la de dev. En la lista de DAGs de prod deben verse pipeline_taxi y resetear_entorno (pausados al nacer); si aparece algún DAG pausado de las prácticas de las clases 5 y 6, es un resto de la base de datos de antes y no importa. El Airflow de prod es el entorno PROD: lo dice la descripción del DAG y el encabezado de cada tarea (PROD, con una advertencia). Errores comunes: la UI sale en blanco (la URL es la del túnel, no la de dev); «Invalid or Expired Auth Token». Tiempo: 1 min. Siguiente: Lanzas pipeline_taxi en prod.

### Deck completo · slide 124: Lanzas pipeline_taxi en prod

*Tipo: pasos · 3 min*

Ventana: Navegador · Airflow de prod.

1. Activa pipeline_taxi y haz clic en Trigger (▶).
2. Deja glue_medium, todos y 2024-01; sin marcar Reprocesar.
3. Haz clic en el segundo Trigger: cuatro tareas en verde.

**Notas del orador:** En prod el formulario no deja elegir el entorno, ni code_editor, ni un límite: el cómputo ofrece solo glue_small, glue_medium y glue_large (defecto glue_medium), el límite ofrece solo todos, y el mes arranca en 2024-01 durante el curso (un mes vacío lanzaría los doce meses). Prod no lee pipeline.yaml. Escribe en s3://<lake>/prod/, anota en BIGDATA.CONTROL_PROD.WATERMARK y carga en BIGDATA.PROD, con el rol BIGDATA_PROD (el secreto <prefijo>/snowflake_prod). Medida previa (pipeline anterior, 20 nov., glue_medium, enero completo): success en 8 min 30 s (bronze 157 s, silver 134 s, gold 116 s); la de hoy se mide en el ensayo. Mientras corre, el instructor puede mostrar el log de correr_bronze: el encabezado dice PROD. Errores comunes: el DAG falla en cargar_snowflake (revisar el secreto de prod); «Invalid or Expired Auth Token». Tiempo: 3 min. Siguiente: Prod rechaza el entorno elegido, code_editor y los límites.

### Deck completo · slide 125: Prod rechaza el entorno elegido, code_editor y los límites

*Tipo: comparacion · 2 min*

| Si intentas en prod | Qué pasa |
|---|---|
| Cómputo code_editor | La primera tarea falla |
| Límite 1000 | La primera tarea falla |
| Escribir desde el Code Editor | El rol lo impide |

**Notas del orador:** Barandillas, no un control contra el dueño de la cuenta, y así hay que decirlo. En el formulario de prod, cómputo y límite no ofrecen las opciones prohibidas; si llega un valor ajeno por airflow dags trigger --conf, la primera tarea falla antes de tocar nada: «Prod solo corre con Glue» o «Prod siempre procesa todo». Desde el Code Editor, entorno_actual() devuelve dev, y si alguien fuerza PIPELINE_ENTORNO=prod, el código rechaza code_editor y exige el rol BIGDATA_PROD, que el Code Editor no tiene. El control real es Snowflake: BIGDATA_DEV no puede escribir en PROD ni en CONTROL_PROD, y el rol de la VM no tiene acceso a dev/. Lo comprobamos con una consulta en un minuto. Tiempo: 2 min. Siguiente: Validas prod con Athena: la misma consulta de gold contra silver, ahora con las tablas prod_.

### Deck completo · slide 126: Validas prod con Athena: la misma consulta de gold contra silver, ahora con las tablas prod_

*Tipo: codigo · 3 min*

```
SELECT
  (SELECT sum(viajes) FROM bigdata_lake.prod_gold_tarifa_por_milla_barrio
   WHERE mes = '2024-01') AS viajes_en_gold,
  (SELECT count(*) FROM bigdata_lake.prod_silver_fhvhv
   WHERE mes = '2024-01') AS filas_en_silver;
```

**En pantalla:** Antes, ejecuta 01_tablas.sql con <ENTORNO> = prod. Con un solo lote en prod, las dos cifras son iguales.

**Notas del orador:** Primero se repite el paso de la copia de 01_tablas.sql con s/<ENTORNO>/prod/g y se ejecutan los bloques en Athena: aparecen las siete tablas prod_. La consulta es la C1 de 02_duplicados_y_conciliacion.sql con dev_ cambiado por prod_ (Ctrl+F > reemplazar todo). Prod procesó el mes completo con un solo lote y no reprocesó: la relación vale 1. Cifras esperadas del mes completo, según la corrida del 20 de noviembre (bronze 19 663 930, silver 19 650 023; 13 907 descartados por los filtros): se confirman en el ensayo. Y gold en prod ya no es la tabla de 15 909 filas de daily_zone_metrics: es tarifa_por_milla_barrio. Si Athena devuelve 0 filas, la tabla apunta a otro entorno o prod no ha corrido el paso: el bloque 7 de 01_tablas.sql ("$path") muestra de qué carpeta lee. Tiempo: 3 min. Siguiente: Validas prod en Snowflake: la tabla de control de prod y la tabla cargada deben cuadrar.

### Deck completo · slide 127: Validas prod en Snowflake: la tabla de control de prod y la tabla cargada deben cuadrar

*Tipo: codigo · 2 min*

```
USE ROLE BIGDATA_DEV;
USE WAREHOUSE BIGDATA_WH;
USE DATABASE BIGDATA;

SELECT TABLA, CAPA, MES, FILAS, COMPUTO, INICIO
FROM BIGDATA.CONTROL_PROD.WATERMARK ORDER BY INICIO;
SELECT COUNT(*), SUM(VIAJES) FROM BIGDATA.PROD.TARIFA_POR_MILLA_BARRIO;
```

**En pantalla:** Con BIGDATA_DEV puedes leer prod, pero no escribir. SUM(VIAJES) debe ser igual a las filas de silver.

**Notas del orador:** Con el rol BIGDATA_DEV se puede leer PROD y CONTROL_PROD, y no escribir. La primera consulta lista lo que anotó el DAG de la VM, en orden: bronze (fhvhv, taxi_zones, clima), silver, gold y snowflake, todas con COMPUTO glue_medium y LIMITE todos; cada paso terminado deja una fila. Las filas de gold cuentan filas de gold, no viajes. La segunda consulta cuenta las filas de la tabla de prod y suma los viajes. Debe cuadrar: SUM(VIAJES) en Snowflake es igual a las filas de silver (según la corrida del 20 nov. del pipeline anterior, silver de enero tenía 19 650 023 viajes; se confirma en el ensayo), que es igual a viajes_en_gold de Athena. Si no cuadra y el factor es exacto, silver tiene duplicados. Tiempo: 2 min. Siguiente: Compruebas que BIGDATA_DEV no puede escribir en prod: el INSERT falla por permisos.

### Deck completo · slide 128: Compruebas que BIGDATA_DEV no puede escribir en prod: el INSERT falla por permisos

*Tipo: codigo · 2 min*

```
USE ROLE BIGDATA_DEV;
USE WAREHOUSE BIGDATA_WH;
USE DATABASE BIGDATA;

INSERT INTO BIGDATA.CONTROL_PROD.WATERMARK (TABLA, CAPA, MES)
VALUES ('prueba', 'bronze', '2024-01');
-- SQL access control error: Insufficient privileges to operate on table
```

**En pantalla:** El mismo INSERT en CONTROL_DEV funciona. Ese error es la barandilla que de verdad protege a prod.

**Notas del orador:** Esta es la prueba de que dev no puede contaminar prod. Con el rol BIGDATA_DEV, un INSERT en BIGDATA.CONTROL_PROD.WATERMARK falla con un error de control de acceso («Insufficient privileges»); el mismo INSERT en CONTROL_DEV funcionaría (por eso no lo repetimos: dejaría una fila falsa). El texto exacto del error se confirma en el ensayo. SHOW GRANTS TO ROLE BIGDATA_DEV no trae CREATE, INSERT ni DELETE sobre PROD ni sobre CONTROL_PROD. Son barandillas contra errores, y el control real es este: el rol. El rol de Glue es el mismo para dev y prod; el aislamiento está en el código y en Snowflake. Tiempo: 2 min. Siguiente: Antes de cerrar, apagas todo lo que cobra.

### Deck completo · slide 129: Antes de cerrar, apagas todo lo que cobra

*Tipo: pasos · 2 min*

Ventana: Terminal del Code Editor.

1. En la terminal del túnel presiona Ctrl + C.
2. En otra terminal escribe make airflow-off y presiona Enter.
3. Escribe make estado: Airflow stopped y ningún job RUNNING.

**Notas del orador:** Lo que cuesta dinero mientras está encendido: el Code Editor (unos US$0.10 por hora; se apaga solo tras 60 minutos de inactividad) y la VM de Airflow de prod. Glue y Snowflake solo cobran mientras corre un job o una consulta; el warehouse BIGDATA_WH se suspende solo a los 60 segundos. make estado muestra el estado de Airflow, los últimos job runs de Glue, el warehouse y los costos. Recordatorio importante: después de cada merge a main que toque src/ o airflow/, el Deploy enciende la VM de prod; hay que apagarla con make airflow-off. Presupuesto: al 60 % del gasto real AWS impide iniciar jobs de Glue y máquinas virtuales y detiene la VM (make desbloquear lo revierte). Tiempo: 2 min. Siguiente: Hoy construiste, comprobaste y promoviste un pipeline.

## Slides del deck corto (35 a 38)

### Deck corto · slide 35: Con todo probado en dev, subimos a prod por una escalera de siete peldaños: PR y CI/CD

*Tipo: titulo_visual · 4 min*

Diagrama: `diagramas/Dc7-4.svg`.

Texto alternativo: Siete peldaños de izquierda a derecha: Notebook y make test, make correr code_editor, make correr glue_small y Airflow del Code Editor (dev); una línea punteada; Pull request y CI, Merge y Deploy, DAG en la VM (prod).

Pie: Cada peldaño cuesta más que el anterior: por eso se prueba abajo.

**Notas del orador:** Los cuatro primeros peldaños son dev, desde el Code Editor: notebook y make test, make correr con code_editor, make correr con glue_small y Airflow del Code Editor. Una línea punteada separa dev de prod. Los tres últimos son prod: pull request y CI, merge y Deploy, y el DAG en la VM. Cada peldaño cuesta más que el anterior: por eso se prueba abajo. Problema: ¿cómo llevo algo a prod sin que nadie pueda romperlo desde su Code Editor? La respuesta es que prod solo se alcanza por pull request y CI/CD. Tiempo: 4 min. Siguiente: Subes un cambio pequeño en una rama y lo llevas por pull request, CI y merge.

### Deck corto · slide 36: Subes un cambio pequeño en una rama y lo llevas por pull request, CI y merge

*Tipo: codigo · 11 min*

```
cd ~/bigdata
git switch main && git pull
git switch -c clase07-a-prod-<tu-nombre>
# Escribe un comentario al final de src/pipeline/gold.py y guarda
make test
git add src/pipeline/gold.py
git commit -m "Clase 7: comentario de prueba para el camino a prod"
git push -u origin clase07-a-prod-<tu-nombre>
```

**En pantalla:** En GitHub, abre Compare & pull request con base main de tu fork, espera los cinco checks en verde, otro integrante aprueba y haz el merge; espera el Deploy.

**Notas del orador:** Se crea una sola vez la rama, con tu nombre para que no choque con las de los demás integrantes en el fork del anfitrión, sin tocar main, se hace un cambio pequeño en gold.py, se comprueba con make test y se guarda con git add (archivo por archivo, para no subir algo sin querer) y git commit; git push -u la enlaza con la rama remota. En GitHub: Compare & pull request en tu fork, base main de tu fork, dos frases y Create pull request. El CI corre en GitHub Actions: ruff lint y formato, pytest, pytest de los DAG, terraform fmt y validate de infra/aws y de infra/snowflake, y terraform plan; deben quedar cinco checks en verde, y si uno falla, Details y se corrige la rama. Solo el anfitrión hace el merge; los demás abren su PR y revisan el del anfitrión (Approve). Otro integrante abre Files changed y hace clic en Approve; luego Merge pull request y Confirm merge. En Actions, el workflow Deploy sincroniza dags y código a la VM; se espera en verde. Tiempo: 11 min. Siguiente: Entras a Airflow de prod por el túnel y lanzas pipeline_taxi.

### Deck corto · slide 37: Entras a Airflow de prod por el túnel y lanzas pipeline_taxi

*Tipo: pasos · 10 min*

Ventana: Terminal y navegador · Airflow de prod.

1. Apaga Airflow de dev, abre el túnel y entra.
2. Lanza pipeline_taxi con glue_medium, todos y 2024-01.
3. Prod rechaza code_editor y el límite 1000.

**Notas del orador:** Se apaga el Airflow de dev con make airflow-local-down porque los dos usan el puerto 8080; make airflow-tunel ocupa esa terminal, así que se deja abierta y se abre otra. En la segunda, make airflow-password imprime la contraseña de prod; se abre la URL del túnel y se entra como admin. Se activa pipeline_taxi, Trigger, y se deja glue_medium, todos y 2024-01 sin marcar Reprocesar; cuatro tareas en verde. En prod el formulario no deja elegir el entorno, ni code_editor, ni un límite: ofrece solo glue_small, glue_medium y glue_large, el límite todos y un mes que arranca en 2024-01 (un mes vacío lanzaría los doce meses). Si llega algo que el formulario no ofrece, la primera tarea falla antes de tocar nada, y escribir desde el Code Editor lo impide el rol. Tiempo: 10 min. Siguiente: Validas prod con Athena y Snowflake, y el INSERT desde BIGDATA_DEV falla por permisos.

### Deck corto · slide 38: Validas prod con Athena y Snowflake, y el INSERT desde BIGDATA_DEV falla por permisos

*Tipo: codigo · 8 min*

```
USE ROLE BIGDATA_DEV;
USE WAREHOUSE BIGDATA_WH;
USE DATABASE BIGDATA;
SELECT TABLA, CAPA, MES, FILAS FROM BIGDATA.CONTROL_PROD.WATERMARK;
SELECT COUNT(*), SUM(VIAJES) FROM BIGDATA.PROD.TARIFA_POR_MILLA_BARRIO;
INSERT INTO BIGDATA.CONTROL_PROD.WATERMARK (TABLA, CAPA, MES)
VALUES ('prueba', 'bronze', '2024-01');
-- SQL access control error: Insufficient privileges to operate on table
```

**En pantalla:** En Athena, la misma consulta de gold contra silver con las tablas prod_ da cifras iguales. Al cerrar apagas todo lo que cobra: Ctrl + C, make airflow-off y make estado.

**Notas del orador:** Athena: se ejecuta 01_tablas.sql con <ENTORNO> = prod y la consulta de gold contra silver con las tablas prod_; con un solo lote en prod, las dos cifras son iguales. Snowflake: con BIGDATA_DEV se puede leer PROD y CONTROL_PROD, pero no escribir; la primera consulta lista lo que anotó el DAG de la VM (todas con COMPUTO glue_medium) y SUM(VIAJES) debe ser igual a las filas de silver. El INSERT en CONTROL_PROD falla con un error de control de acceso («Insufficient privileges»); el mismo INSERT en CONTROL_DEV funcionaría, y ese error es la barandilla que de verdad protege a prod. Antes de cerrar se apaga todo lo que cobra: Ctrl + C en la terminal del túnel, make airflow-off en otra, y make estado debe decir Airflow stopped y ningún job RUNNING. Tiempo: 8 min. Siguiente: Hoy construiste, comprobaste y promoviste un pipeline, y en el Taller tu equipo escribe cuatro piezas.

