"""DAG ingesta_mensual: tus funciones de la clase 5, más silver y gold, ejecutadas en orden.

    ingestar_zonas -> ingestar_clima -> ingestar_viajes -> silver -> gold

Qué hace cada tarea
- Las tres ingestas llaman a TUS funciones de src/pipeline/ingesta_alumno.py (las del lab de la
  clase 5), con `mes` y `reprocesar`. Si una todavía está vacía, la tarea falla con un mensaje
  que dice cuál pegar.
- silver y gold usan el código del repo (pipeline.silver y pipeline.gold, con Spark local) sobre
  el bronze que dejaron tus ingestas.
- Las cinco tareas consultan la tabla de control (BIGDATA.CONTROL.WATERMARK) antes de trabajar y
  registran en ella al terminar bien. Por eso ejecutar el DAG dos veces con el mismo mes no repite
  nada, y por eso un reintento de Airflow tampoco duplica: si la tarea alcanzó a registrar, el
  reintento se salta; si falló antes de registrar, el reintento lo hace completo.
- Cada tarea imprime en su log qué decidió: «INGESTÓ», «SE SALTÓ» o «REPROCESÓ».

Cómo se lanza (es un DAG de dev, en el Airflow del Code Editor; no hay corridas automáticas)
- Parámetro `mes` (AAAA-MM): obligatorio al disparar a mano.
- Parámetro `reprocesar` (falso por defecto): verdadero ignora la tabla de control y crea un lote
  nuevo (la historia anterior no se borra).
- Sin calendario activo: en clase cada corrida se dispara a mano con su mes. La línea del
  calendario mensual queda comentada en el DAG para que se vea cómo se programaría; si estuviera
  activa, al encender el DAG Airflow lanzaría solo la corrida del mes en curso y el clima de un
  mes que no ha terminado falla.

Datos de prueba (para que cada estudiante pueda repetir la clase sin ensuciar nada real)
- Las tablas se llaman prueba_clima, prueba_taxi_zones, prueba_fhvhv, prueba_fhvhv_trips (silver)
  y prueba_daily_zone_metrics (gold). El prefijo «prueba_» es lo que permite ingestar viajes con
  limite_filas (la guarda del lab lo exige) y borrar sus registros para empezar de cero.
- Los viajes se ingestan en modo de prueba: se descarga el archivo completo y se escriben solo
  las primeras 1 000 filas. Airflow y Spark comparten una máquina de 7.6 GB.

Configuración opcional, con variables de entorno al arrancar Airflow (make airflow-local)
    CLASE05_DATOS             carpeta de datos de las clases (por defecto ~/datos_clase05)
    INGESTA_BASE_BRONZE       bronze de entrada y salida (por defecto <CLASE05_DATOS>/bronze_alumno)
    INGESTA_BASE_SILVER       carpeta de silver (por defecto <CLASE05_DATOS>/silver_alumno)
    INGESTA_BASE_GOLD         carpeta de gold (por defecto <CLASE05_DATOS>/gold_alumno)
    INGESTA_PREFIJO_TABLAS    prefijo de las tablas (por defecto «prueba_»)
    INGESTA_LIMITE_VIAJES     filas de viajes (por defecto 1000; 0 = mes completo)

Por qué las tareas usan ExternalPythonOperator: Airflow corre en su propio entorno de Python
(sin Spark ni el paquete pipeline). Cada tarea ejecuta su función con el Python del .venv del
repo, el mismo de los notebooks y de `make test`, donde sí están Spark y pipeline. Por eso cada
función de tarea es autocontenida: importa lo que usa dentro de ella.
"""

from __future__ import annotations

import os
from datetime import datetime, timedelta
from pathlib import Path

from airflow.sdk import DAG, Param, task

# --- configuración --------------------------------------------------------------------------

# Raíz del repo (airflow/dags/ingesta_mensual.py -> repo) y el Python del .venv, como en
# framework/tasks.py (pipeline_local_task).
REPO_ROOT = Path(__file__).resolve().parents[2]
REPO_SRC = str(REPO_ROOT / "src")
PYTHON_DEL_REPO = str(REPO_ROOT / ".venv" / "bin" / "python")

DATOS = Path(os.environ.get("CLASE05_DATOS", Path.home() / "datos_clase05"))
BASE_BRONZE = os.environ.get("INGESTA_BASE_BRONZE", str(DATOS / "bronze_alumno"))
BASE_SILVER = os.environ.get("INGESTA_BASE_SILVER", str(DATOS / "silver_alumno"))
BASE_GOLD = os.environ.get("INGESTA_BASE_GOLD", str(DATOS / "gold_alumno"))

PREFIJO = os.environ.get("INGESTA_PREFIJO_TABLAS", "prueba_")
TABLA_ZONAS = f"{PREFIJO}taxi_zones"
TABLA_CLIMA = f"{PREFIJO}clima"
TABLA_VIAJES = f"{PREFIJO}fhvhv"
TABLA_SILVER = f"{PREFIJO}fhvhv_trips"
TABLA_GOLD = f"{PREFIJO}daily_zone_metrics"

# Modo de prueba de los viajes. 0 en la variable significa mes completo (None para la función).
LIMITE_VIAJES = int(os.environ.get("INGESTA_LIMITE_VIAJES", "1000")) or None

# El mes sale del parámetro. Si se deja vacío, solo una corrida programada puede completarlo
# (con el mes del intervalo que acaba de cerrar); a mano, las tareas fallan pidiendo el mes.
MES = (
    "{% if params.mes %}{{ params.mes }}"
    "{% elif dag_run.run_type | string == 'scheduled' %}{{ data_interval_start.strftime('%Y-%m') }}"
    "{% endif %}"
)
# Las plantillas de Airflow devuelven texto: cada tarea lo convierte a verdadero o falso.
REPROCESAR = "{{ params.reprocesar }}"

# Un reintento rápido basta para demostrar que reintentar no duplica.
ARGUMENTOS_POR_DEFECTO = {"retries": 1, "retry_delay": timedelta(seconds=10)}


# --- tareas ---------------------------------------------------------------------------------
# Cada función corre en el Python del repo: por eso importa dentro de ella y no usa nada del
# resto de este archivo (solo sus argumentos).


@task.external_python(task_id="ingestar_zonas", python=PYTHON_DEL_REPO, expect_airflow=False)
def tarea_ingestar_zonas(repo_src, base_bronze, tabla, reprocesar):
    import sys

    sys.path.insert(0, repo_src)
    from pipeline import ingesta_alumno as alumno

    reprocesar = str(reprocesar).lower() == "true"

    # Paso 1. Tu función debe estar pegada.
    if alumno.esta_pendiente(alumno.ingestar_zonas):
        raise RuntimeError(
            "PENDIENTE: pega tu función ingestar_zonas (Celda 18 del lab de la clase 5) en "
            "src/pipeline/ingesta_alumno.py"
        )

    # Paso 2. Llamarla. Devuelve la carpeta del lote, o None si no hizo nada.
    print(f"ingestar_zonas: tabla={tabla}, reprocesar={reprocesar}, bronze={base_bronze}")
    lote = alumno.ingestar_zonas(reprocesar=reprocesar, base_bronze=base_bronze, tabla=tabla)

    # Paso 3. Explicar qué decidió.
    if lote is None:
        print("DECISIÓN: SE SALTÓ. La tabla de control ya tiene las zonas y reprocesar es falso.")
    elif reprocesar:
        print(f"DECISIÓN: REPROCESÓ. Lote nuevo en {lote}; el anterior sigue ahí.")
    else:
        print(f"DECISIÓN: INGESTÓ. Lote nuevo en {lote} y registro en la tabla de control.")


@task.external_python(task_id="ingestar_clima", python=PYTHON_DEL_REPO, expect_airflow=False)
def tarea_ingestar_clima(repo_src, base_bronze, tabla, mes, reprocesar):
    import sys

    sys.path.insert(0, repo_src)
    from pipeline import ingesta_alumno as alumno
    from pipeline.settings import validar_mes

    reprocesar = str(reprocesar).lower() == "true"
    if not mes:
        raise ValueError('Falta el parámetro mes. Dispara el DAG con {"mes": "2024-01"}.')
    validar_mes(mes)

    if alumno.esta_pendiente(alumno.ingestar_clima):
        raise RuntimeError(
            "PENDIENTE: pega tu función ingestar_clima (Celda 16 del lab de la clase 5) en "
            "src/pipeline/ingesta_alumno.py"
        )

    print(f"ingestar_clima: tabla={tabla}, mes={mes}, reprocesar={reprocesar}")
    lote = alumno.ingestar_clima(mes, reprocesar=reprocesar, base_bronze=base_bronze, tabla=tabla)

    if lote is None:
        print(f"DECISIÓN: SE SALTÓ. La tabla de control ya tiene el clima de {mes}.")
    elif reprocesar:
        print(f"DECISIÓN: REPROCESÓ el clima de {mes}. Lote nuevo en {lote}.")
    else:
        print(f"DECISIÓN: INGESTÓ el clima de {mes}. Lote nuevo en {lote}.")


@task.external_python(task_id="ingestar_viajes", python=PYTHON_DEL_REPO, expect_airflow=False)
def tarea_ingestar_viajes(repo_src, base_bronze, tabla, mes, reprocesar, limite_filas):
    import sys

    sys.path.insert(0, repo_src)
    from pipeline import ingesta_alumno as alumno
    from pipeline.settings import validar_mes

    reprocesar = str(reprocesar).lower() == "true"
    if not mes:
        raise ValueError('Falta el parámetro mes. Dispara el DAG con {"mes": "2024-01"}.')
    validar_mes(mes)

    if alumno.esta_pendiente(alumno.ingestar_viajes):
        raise RuntimeError(
            "PENDIENTE: pega tu función ingestar_viajes (Celda 20 del lab de la clase 5) en "
            "src/pipeline/ingesta_alumno.py"
        )

    # Modo de prueba: descarga el archivo completo, pero escribe solo `limite_filas` filas.
    print(
        f"ingestar_viajes: tabla={tabla}, mes={mes}, reprocesar={reprocesar}, "
        f"limite_filas={limite_filas}"
    )
    lote = alumno.ingestar_viajes(
        mes,
        reprocesar=reprocesar,
        base_bronze=base_bronze,
        tabla=tabla,
        limite_filas=limite_filas,
    )

    if lote is None:
        print(f"DECISIÓN: SE SALTÓ. La tabla de control ya tiene los viajes de {mes}.")
    elif reprocesar:
        print(f"DECISIÓN: REPROCESÓ los viajes de {mes}. Lote nuevo en {lote}.")
    else:
        print(f"DECISIÓN: INGESTÓ los viajes de {mes}. Lote nuevo en {lote}.")


@task.external_python(task_id="silver", python=PYTHON_DEL_REPO, expect_airflow=False)
def tarea_silver(repo_src, base_bronze, base_silver, base_gold, mes, reprocesar, tablas):
    import json
    import sys
    from argparse import Namespace
    from datetime import UTC, datetime
    from unittest import mock

    sys.path.insert(0, repo_src)
    from pipeline import engine, silver
    from pipeline import io as pio
    from pipeline.settings import cargar, validar_mes
    from pipeline.watermark import consultar_watermark, registrar_watermark

    reprocesar = str(reprocesar).lower() == "true"
    if not mes:
        raise ValueError('Falta el parámetro mes. Dispara el DAG con {"mes": "2024-01"}.')
    validar_mes(mes)
    tabla_silver = tablas["silver"]

    # Paso 1. Consultar la tabla de control: ¿silver de este mes ya está hecho?
    registros = json.loads(consultar_watermark(tabla_silver, "silver", mes))
    if registros and not reprocesar:
        ultimo = registros[-1]
        print(
            f"DECISIÓN: SE SALTÓ silver {mes}. La tabla de control ya tiene {len(registros)} "
            f"registro(s), el último del {ultimo['inicio']} UTC con {ultimo['filas']} filas."
        )
        return

    # Paso 2. Configuración del repo (entorno local) apuntando a las carpetas del estudiante.
    inicio = datetime.now(UTC).replace(microsecond=0)
    cfg = cargar("local")
    cfg["rutas"] = {"bronze": base_bronze, "silver": base_silver, "gold": base_gold}
    args = Namespace(env="local", engine="local", meses=[mes], limite=None)

    # Paso 3. Correr silver del repo. Silver busca las carpetas «fhvhv», «clima» y «taxi_zones»;
    # las ingestas de prueba escribieron en las suyas (prefijo prueba_), así que se le indica
    # cuáles son solo mientras corre.
    carpetas_de_bronze = {
        "VIAJES": tablas["viajes"],
        "CLIMA": tablas["clima"],
        "ZONAS": tablas["zonas"],
    }
    spark = engine.get_spark("local")
    with mock.patch.multiple(pio, **carpetas_de_bronze):
        silver.main(spark, cfg, args)

    # Paso 4. Registrar solo ahora, con las filas que quedaron en silver.
    filas = pio.leer_silver(spark, cfg, [mes]).count()
    registrar_watermark(base_bronze, "silver", tabla_silver, mes, filas, inicio, reprocesar)
    accion = "REPROCESÓ" if registros else "CONSTRUYÓ"
    print(f"DECISIÓN: {accion} silver {mes}: {filas} filas en {base_silver}.")


@task.external_python(task_id="gold", python=PYTHON_DEL_REPO, expect_airflow=False)
def tarea_gold(repo_src, base_bronze, base_silver, base_gold, mes, reprocesar, tablas):
    import json
    import sys
    from argparse import Namespace
    from datetime import UTC, datetime

    sys.path.insert(0, repo_src)
    from pipeline import engine, gold
    from pipeline import io as pio
    from pipeline.settings import cargar, validar_mes
    from pipeline.watermark import consultar_watermark, registrar_watermark

    reprocesar = str(reprocesar).lower() == "true"
    if not mes:
        raise ValueError('Falta el parámetro mes. Dispara el DAG con {"mes": "2024-01"}.')
    validar_mes(mes)
    tabla_gold = tablas["gold"]

    # Paso 1. Consultar la tabla de control: ¿gold de este mes ya está hecho?
    registros = json.loads(consultar_watermark(tabla_gold, "gold", mes))
    if registros and not reprocesar:
        ultimo = registros[-1]
        print(
            f"DECISIÓN: SE SALTÓ gold {mes}. La tabla de control ya tiene {len(registros)} "
            f"registro(s), el último del {ultimo['inicio']} UTC con {ultimo['filas']} filas."
        )
        return

    # Paso 2. Configuración del repo apuntando a las carpetas del estudiante.
    inicio = datetime.now(UTC).replace(microsecond=0)
    cfg = cargar("local")
    cfg["rutas"] = {"bronze": base_bronze, "silver": base_silver, "gold": base_gold}
    args = Namespace(env="local", engine="local", meses=[mes], limite=None)

    # Paso 3. Correr gold del repo: lee silver y escribe las métricas diarias por zona.
    spark = engine.get_spark("local")
    gold.main(spark, cfg, args)

    # Paso 4. Registrar solo ahora, con las filas de la partición del mes.
    carpeta_del_mes = pio.unir(cfg["rutas"]["gold"], pio.CARPETA_CAPA["gold"], f"mes={mes}")
    filas = spark.read.parquet(carpeta_del_mes).count()
    registrar_watermark(base_silver, "gold", tabla_gold, mes, filas, inicio, reprocesar)
    accion = "REPROCESÓ" if registros else "CONSTRUYÓ"
    print(f"DECISIÓN: {accion} gold {mes}: {filas} filas en {base_gold}.")


# --- el DAG ---------------------------------------------------------------------------------

with DAG(
    dag_id="ingesta_mensual",
    description="Ingesta del alumno (zonas, clima, viajes) y silver/gold, mes a mes",
    # Para correr solo el día 1 de cada mes a medianoche, cambia la línea de abajo por esta:
    # schedule="0 0 1 * *",
    schedule=None,
    start_date=datetime(2024, 1, 1),
    catchup=False,
    is_paused_upon_creation=True,
    max_active_runs=1,
    default_args=ARGUMENTOS_POR_DEFECTO,
    tags=["bigdata", "clase06", "dev"],
    params={
        "mes": Param(
            "",
            type="string",
            pattern=r"^(\d{4}-(0[1-9]|1[0-2]))?$",
            description="AAAA-MM, por ejemplo 2024-01. Obligatorio al disparar a mano.",
        ),
        "reprocesar": Param(
            False,
            type="boolean",
            description="Verdadero: ignora la tabla de control y crea un lote nuevo.",
        ),
    },
) as dag:
    zonas = tarea_ingestar_zonas(
        repo_src=REPO_SRC,
        base_bronze=BASE_BRONZE,
        tabla=TABLA_ZONAS,
        reprocesar=REPROCESAR,
    )
    clima = tarea_ingestar_clima(
        repo_src=REPO_SRC,
        base_bronze=BASE_BRONZE,
        tabla=TABLA_CLIMA,
        mes=MES,
        reprocesar=REPROCESAR,
    )
    viajes = tarea_ingestar_viajes(
        repo_src=REPO_SRC,
        base_bronze=BASE_BRONZE,
        tabla=TABLA_VIAJES,
        mes=MES,
        reprocesar=REPROCESAR,
        limite_filas=LIMITE_VIAJES,
    )
    silver = tarea_silver(
        repo_src=REPO_SRC,
        base_bronze=BASE_BRONZE,
        base_silver=BASE_SILVER,
        base_gold=BASE_GOLD,
        mes=MES,
        reprocesar=REPROCESAR,
        tablas={
            "zonas": TABLA_ZONAS,
            "clima": TABLA_CLIMA,
            "viajes": TABLA_VIAJES,
            "silver": TABLA_SILVER,
        },
    )
    gold = tarea_gold(
        repo_src=REPO_SRC,
        base_bronze=BASE_BRONZE,
        base_silver=BASE_SILVER,
        base_gold=BASE_GOLD,
        mes=MES,
        reprocesar=REPROCESAR,
        tablas={"gold": TABLA_GOLD},
    )

    zonas >> clima >> viajes >> silver >> gold
