"""DAG hola_airflow: práctica de la clase 6 para conocer Airflow en segundos.

    saludar -> esperar -> reintentar

No usa Spark, Snowflake ni red: solo sirve para ver cómo se ve una corrida, qué significan los
colores de la cuadrícula y qué hace Airflow cuando una tarea falla.

Qué hace cada tarea
- saludar: imprime un saludo y el mes que recibió en el parámetro `mes`.
- esperar: duerme unos segundos para que alcances a ver la tarea en «running» (en ejecución).
- reintentar: falla a propósito en el primer intento y funciona en el reintento. Así ves el
  estado «up_for_retry» (a la espera de reintento) sin romper nada de verdad.

Cómo se lanza (a mano, no hay corridas automáticas)
- En la interfaz: botón de disparar, escribir el `mes` (AAAA-MM) y confirmar.
- En la terminal: airflow dags test hola_airflow 2024-02-01 --conf '{"mes": "2024-02"}'

Mini reto «rompe y arregla»: cambia FALLAR_SIEMPRE a True, guarda y vuelve a lanzar. La tarea
`reintentar` fallará en todos los intentos y quedará en rojo. Luego devuélvela a False y usa
«Clear» en la interfaz para ejecutarla otra vez.
"""

from __future__ import annotations

import time
from datetime import datetime, timedelta

from airflow.sdk import DAG, Param, task

# --- configuración --------------------------------------------------------------------------

# Interruptor del mini reto «rompe y arregla». Con False, `reintentar` falla solo en el primer
# intento (a propósito) y pasa en el reintento. Con True falla en TODOS los intentos: Airflow
# agota el reintento y la tarea queda en rojo («failed») hasta que lo devuelvas a False.
FALLAR_SIEMPRE = False

# Segundos que dura `esperar`: los suficientes para ver la tarea en «running» en la cuadrícula.
SEGUNDOS_DE_ESPERA = 15

# Un reintento con espera corta: así ves «up_for_retry» sin esperar minutos (igual que en
# ingesta_mensual.py).
ARGUMENTOS_POR_DEFECTO = {"retries": 1, "retry_delay": timedelta(seconds=10)}


# --- tareas ---------------------------------------------------------------------------------


@task(task_id="saludar")
def saludar(mes):
    """Imprime un saludo y el mes recibido: lo que escribas en el parámetro `mes` llega aquí."""
    print("Hola, Airflow. Esta es mi primera tarea.")
    print(f"Mes recibido: {mes}")


@task(task_id="esperar")
def esperar():
    """Duerme un rato para que la tarea se vea «en ejecución» (running) en la interfaz."""
    print(f"Esperando {SEGUNDOS_DE_ESPERA} segundos para que se vea «running» en la cuadrícula...")
    time.sleep(SEGUNDOS_DE_ESPERA)
    print("Listo, terminé de esperar.")


@task(task_id="reintentar")
def reintentar(**context):
    """Falla a propósito en el primer intento y funciona en el reintento."""
    # try_number cuenta los intentos de esta tarea: 1 es el primero, 2 es el reintento.
    intento = context["ti"].try_number
    print(f"Este es el intento número {intento}.")

    if FALLAR_SIEMPRE:
        # Modo del mini reto: falla en todos los intentos para que quede en rojo.
        raise RuntimeError(
            "FALLO A PROPÓSITO (mini reto): FALLAR_SIEMPRE = True en "
            "airflow/dags/hola_airflow.py. Para arreglarlo, cambia esa línea a "
            "FALLAR_SIEMPRE = False, guarda el archivo y usa Clear en la tarea."
        )

    if intento <= 1:
        # Falla en el primer intento para que veas «up_for_retry»; el reintento ya pasa.
        # (`airflow tasks test` reporta el intento 0 y no reintenta: ahí siempre falla.)
        raise RuntimeError(
            "FALLO INTENCIONAL en el intento 1: no es un error de verdad. "
            "Airflow lo reintentará solo en unos 10 segundos y el reintento funcionará."
        )
    else:
        print(f"Intento {intento}: esta vez sí funciona. Así termina bien un reintento.")


# --- el DAG ---------------------------------------------------------------------------------

with DAG(
    dag_id="hola_airflow",
    description="Práctica de la clase 6: tres tareas, un parámetro y un fallo con reintento",
    schedule=None,
    start_date=datetime(2024, 1, 1),
    catchup=False,
    default_args=ARGUMENTOS_POR_DEFECTO,
    tags=["bigdata", "clase06", "practica"],
    params={
        "mes": Param(
            "2024-02",
            type="string",
            pattern=r"^\d{4}-(0[1-9]|1[0-2])$",
            description="AAAA-MM, por ejemplo 2024-02.",
        ),
    },
) as dag:
    paso_saludar = saludar(mes="{{ params.mes }}")
    paso_esperar = esperar()
    paso_reintentar = reintentar()

    paso_saludar >> paso_esperar >> paso_reintentar
