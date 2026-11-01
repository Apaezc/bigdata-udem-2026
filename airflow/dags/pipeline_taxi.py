"""DAG pipeline_taxi: bronze -> silver -> gold -> carga a Snowflake, por entorno.

params.entorno elige el camino:
- local: silver_local -> gold_local. Spark en la misma máquina que Airflow (Code Editor),
  sobre la muestra. Gratis; valida la lógica. No carga a Snowflake.
- dev:   bronze_dev -> silver_dev -> gold_dev -> cargar_dev. Glue `small`, 1 mes completo,
  carga a BIGDATA.DEV.
- prod:  bronze_prod -> silver_prod -> gold_prod -> cargar_prod. Glue `medium`/`large`, el año,
  carga a BIGDATA.PROD. Lo usa el Airflow de prod (la VM), con DAGs desplegados por CI.
params.mes vacío = todos los meses del entorno (config/<entorno>.yaml); params.limite recorta
los viajes (vacío = sin recorte). El entorno por defecto viene de PIPELINE_ENTORNO
(la VM de prod lo fija en "prod"; el Code Editor usa "local").
"""

from __future__ import annotations

import os
import sys
from datetime import datetime
from pathlib import Path

from airflow.models.param import Param
from airflow.providers.standard.operators.python import BranchPythonOperator
from airflow.sdk import DAG

# airflow/ es la raíz del paquete `framework`.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from framework.tasks import glue_task, pipeline_local_task, snowflake_task

ENTORNOS = ("local", "dev", "prod")
ENTORNO_POR_DEFECTO = os.environ.get("PIPELINE_ENTORNO", "local")
# Perfil Glue de cada step en la nube (profiles.yaml).
PERFILES = {
    "dev": {"bronze": "small", "silver": "small", "gold": "small"},
    "prod": {"bronze": "small", "silver": "large", "gold": "medium"},
}


def _elegir_entorno(**context) -> str:
    """Primer task_id del camino según params.entorno."""
    entorno = context["params"]["entorno"]
    return "silver_local" if entorno == "local" else f"bronze_{entorno}"


with DAG(
    dag_id="pipeline_taxi",
    schedule=None,
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=["bigdata", "fhvhv"],
    params={
        "entorno": Param(
            ENTORNO_POR_DEFECTO if ENTORNO_POR_DEFECTO in ENTORNOS else "local",
            type="string",
            enum=list(ENTORNOS),
            description="local (muestra, Spark aquí) | dev (Glue small, 1 mes) | prod (Glue, año)",
        ),
        "mes": Param(
            "",
            type="string",
            pattern=r"^(\d{4}-\d{2})?$",
            description="YYYY-MM; vacío = todos los meses del entorno",
        ),
        "limite": Param(
            None,
            type=["null", "integer"],
            minimum=1,
            description="Máximo de viajes a procesar; vacío = sin recorte",
        ),
    },
) as dag:
    elegir = BranchPythonOperator(task_id="elegir_entorno", python_callable=_elegir_entorno)

    silver_local = pipeline_local_task("silver_local", step="silver")
    gold_local = pipeline_local_task("gold_local", step="gold")
    elegir >> silver_local >> gold_local

    for entorno, perfiles in PERFILES.items():
        bronze = glue_task(
            f"bronze_{entorno}", step="bronze", profile=perfiles["bronze"], env=entorno
        )
        silver = glue_task(
            f"silver_{entorno}", step="silver", profile=perfiles["silver"], env=entorno
        )
        gold = glue_task(f"gold_{entorno}", step="gold", profile=perfiles["gold"], env=entorno)
        cargar = snowflake_task(f"cargar_{entorno}", sql_file="sql/copy_gold.sql")
        elegir >> bronze >> silver >> gold >> cargar
