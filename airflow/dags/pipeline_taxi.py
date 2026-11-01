"""DAG pipeline_taxi: bronze -> silver -> gold -> carga a Snowflake.

Dos conceptos separados:
- ENTORNO (dónde quedan los datos): lo fija cada Airflow con PIPELINE_ENTORNO y NO se elige
  al lanzar. El Airflow del Code Editor es `dev` (s3://<lake>/dev/, BIGDATA.DEV); la VM es
  `prod` (s3://<lake>/prod/, BIGDATA.PROD) y solo recibe DAGs por CI (merge a main).
- params.computo (con qué recursos se calcula):
    spark_local  -> Spark en el Code Editor sobre la muestra (gratis; solo en dev), en ./lake.
    glue_small | glue_medium | glue_large -> Glue con 2, 4 o 6 workers.
  En dev se puede probar con recursos de prod (glue_large, varios meses) sin tocar prod.
params.mes vacío = todos los meses de config/<entorno>.yaml. preparar_entorno decide el límite
de filas: spark_local, máximo 10 000 por fuente; Glue, el que pida el desarrollador; prod, ninguno.
"""

from __future__ import annotations

import os
import sys
from datetime import datetime
from pathlib import Path

from airflow.providers.standard.operators.python import BranchPythonOperator
from airflow.sdk import DAG, Param

# airflow/ es la raíz del paquete `framework`.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from framework.tasks import glue_task, pipeline_local_task, preparar_entorno_task, snowflake_task

ENTORNO = os.environ.get("PIPELINE_ENTORNO", "dev")
if ENTORNO not in ("dev", "prod"):
    raise ValueError(
        f"PIPELINE_ENTORNO inválido {ENTORNO!r}: usa 'dev' (Code Editor) o 'prod' (VM)"
    )

COMPUTO = {
    "dev": ["spark_local", "glue_small", "glue_medium", "glue_large"],
    "prod": ["glue_medium", "glue_large"],
}[ENTORNO]


def _elegir_computo(**context) -> str:
    return "silver_spark_local" if context["params"]["computo"] == "spark_local" else "bronze"


with DAG(
    dag_id="pipeline_taxi",
    schedule=None,
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=["bigdata", "fhvhv", ENTORNO],
    description=f"Pipeline FHVHV en el entorno {ENTORNO}",
    params={
        "computo": Param(
            COMPUTO[0] if ENTORNO == "dev" else "glue_large",
            type="string",
            enum=COMPUTO,
            description="spark_local (muestra, gratis) | glue_small | glue_medium | glue_large",
        ),
        "mes": Param(
            None,
            type=["null", "string"],
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
    preparar = preparar_entorno_task(ENTORNO)
    elegir = BranchPythonOperator(task_id="elegir_computo", python_callable=_elegir_computo)
    preparar >> elegir

    if "spark_local" in COMPUTO:
        silver_local = pipeline_local_task("silver_spark_local", step="silver")
        gold_local = pipeline_local_task("gold_spark_local", step="gold")
        elegir >> silver_local >> gold_local

    # bronze solo descarga (y omite lo que ya existe): siempre en el perfil más chico.
    bronze = glue_task("bronze", step="bronze", env=ENTORNO, profile="small")
    silver = glue_task("silver", step="silver", env=ENTORNO)
    gold = glue_task("gold", step="gold", env=ENTORNO)
    cargar = snowflake_task(
        "cargar_gold", sql_file="sql/copy_gold.sql", params={"entorno": ENTORNO}
    )
    elegir >> bronze >> silver >> gold >> cargar
