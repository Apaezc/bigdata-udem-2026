"""DAG pipeline_taxi: bronze -> silver -> gold -> carga a Snowflake.

    correr_bronze  >>  correr_silver  >>  correr_gold  >>  cargar_snowflake

Cada tarea se llama igual que la función de `pipeline/correr.py` que ejecuta, y es la misma que
corres en una celda del cuaderno o con `make correr PASO=...`.

Entorno y perillas, dos cosas distintas:
- ENTORNO (dónde quedan los datos): NO se elige al lanzar. Lo fija cada Airflow con
  PIPELINE_ENTORNO. El del Code Editor es `dev` (s3://<lake>/dev/, BIGDATA.DEV); la VM es `prod`
  (s3://<lake>/prod/, BIGDATA.PROD) y solo recibe el DAG por CI/CD (merge a main). El entorno
  aparece en el doc_md del DAG y en el banner de cada tarea.
- Perillas (el formulario de «Trigger DAG»): `computo`, `limite`, `mes` y `reprocesar`. En dev
  los valores iniciales salen de pipeline.yaml (si el yaml está mal, el DAG se parsea igual con
  los valores por defecto y el aviso queda en el doc_md). En prod no se lee el yaml: solo Glue,
  límite `todos` y, durante el curso, mes 2024-01.

Cómo se lanza cada tarea (framework/tasks.py): con code_editor, el CLI `python -m pipeline.run`
con el Python del .venv del repo; con glue_*, la función `correr_<paso>(...)` en el proceso de
Airflow (usa el lanzador de Glue); `cargar_snowflake` no usa Spark ni Glue.
"""

from __future__ import annotations

import sys
from datetime import datetime
from pathlib import Path

from airflow.sdk import DAG

# airflow/ es la raíz del paquete `framework`.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from framework.tasks import (
    documentacion_del_dag,
    entorno_del_airflow,
    nombre_del_entorno,
    parametros_del_formulario,
    tarea_del_pipeline,
)

ENTORNO = entorno_del_airflow()
PARAMS, AVISOS = parametros_del_formulario(ENTORNO)
DEFECTOS = {nombre: param.value for nombre, param in PARAMS.items()}

with DAG(
    dag_id="pipeline_taxi",
    schedule=None,
    start_date=datetime(2024, 1, 1),
    catchup=False,
    max_active_runs=1,
    max_active_tasks=1,
    tags=["bigdata", "fhvhv", ENTORNO],
    description=f"Pipeline FHVHV en el entorno {nombre_del_entorno(ENTORNO)}",
    doc_md=documentacion_del_dag(ENTORNO, AVISOS, DEFECTOS),
    params=PARAMS,
) as dag:
    correr_bronze = tarea_del_pipeline("correr_bronze", ENTORNO)
    correr_silver = tarea_del_pipeline("correr_silver", ENTORNO)
    correr_gold = tarea_del_pipeline("correr_gold", ENTORNO)
    cargar_snowflake = tarea_del_pipeline("cargar_snowflake", ENTORNO)

    correr_bronze >> correr_silver >> correr_gold >> cargar_snowflake
