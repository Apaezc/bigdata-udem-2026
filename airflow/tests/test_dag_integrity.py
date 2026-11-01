"""Integridad del DAG pipeline_taxi: carga sin errores, número de tareas y orden."""

from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path

import pytest

AIRFLOW_ROOT = Path(__file__).resolve().parents[1]
DAGS_DIR = AIRFLOW_ROOT / "dags"
DAG_ID = "pipeline_taxi"

# Airflow lee su configuración al importarse: fijar antes de cualquier import de airflow.
os.environ.setdefault("AIRFLOW_HOME", tempfile.mkdtemp(prefix="airflow_home_"))
os.environ.setdefault("AIRFLOW__CORE__LOAD_EXAMPLES", "False")
os.environ.setdefault("AIRFLOW__CORE__UNIT_TEST_MODE", "True")
if str(AIRFLOW_ROOT) not in sys.path:
    sys.path.insert(0, str(AIRFLOW_ROOT))


@pytest.fixture(scope="module")
def dag_bag():
    from airflow.dag_processing.dagbag import DagBag

    return DagBag(dag_folder=str(DAGS_DIR))


@pytest.fixture(scope="module")
def dag(dag_bag):
    # dags[...] evita consultar la base de datos de Airflow (no hay DB en el test).
    return dag_bag.dags[DAG_ID]


def _upstream_ids(task) -> set[str]:
    """Todos los ancestros de la tarea (transitivo)."""
    seen: set[str] = set()
    stack = list(task.upstream_task_ids)
    while stack:
        tid = stack.pop()
        if tid not in seen:
            seen.add(tid)
            stack.extend(task.dag.get_task(tid).upstream_task_ids)
    return seen


def test_no_import_errors(dag_bag):
    assert dag_bag.import_errors == {}, dag_bag.import_errors
    assert DAG_ID in dag_bag.dags


CAMINOS = {
    "local": ["silver_local", "gold_local"],
    "dev": ["bronze_dev", "silver_dev", "gold_dev", "cargar_dev"],
    "prod": ["bronze_prod", "silver_prod", "gold_prod", "cargar_prod"],
}


@pytest.mark.parametrize("entorno", CAMINOS)
def test_cada_entorno_es_una_cadena_desde_el_branch(dag, entorno):
    tareas = CAMINOS[entorno]
    assert dag.get_task(tareas[0]).upstream_task_ids == {"elegir_entorno"}
    for anterior, siguiente in zip(tareas, tareas[1:], strict=False):
        assert dag.get_task(siguiente).upstream_task_ids == {anterior}
    assert dag.get_task(tareas[-1]).downstream_task_ids == set()


def test_no_quedan_ramas_de_snowpark(dag):
    assert not [t for t in dag.task_ids if "snowpark" in t]


def test_dag_es_manual_con_params(dag):
    assert type(dag.timetable).__name__ == "NullTimetable"
    assert set(dag.params) == {"entorno", "mes", "limite"}
    assert dag.params["entorno"] in CAMINOS
    assert dag.params["mes"] == ""
    assert dag.params["limite"] is None


@pytest.mark.parametrize("entorno", ["dev", "prod"])
def test_glue_pasa_entorno_worker_type_y_workers(dag, entorno):
    # StartJobRun falla con "Please set both Worker Type and Number of Workers" si falta uno.
    for step in ("bronze", "silver", "gold"):
        tarea = dag.get_task(f"{step}_{entorno}")
        assert tarea.run_job_kwargs["WorkerType"] == "G.1X"
        assert tarea.run_job_kwargs["NumberOfWorkers"] >= 2
        assert tarea.script_args["--env"] == entorno
        assert tarea.verbose is True


def test_prod_usa_perfiles_mayores_que_dev(dag):
    dev = dag.get_task("silver_dev").run_job_kwargs["NumberOfWorkers"]
    prod = dag.get_task("silver_prod").run_job_kwargs["NumberOfWorkers"]
    assert prod > dev
