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


def test_cadena_glue_y_spark_local_desde_el_branch(dag):
    assert dag.get_task("elegir_computo").upstream_task_ids == {"preparar_entorno"}
    assert dag.get_task("bronze").upstream_task_ids == {"elegir_computo"}
    assert dag.get_task("silver").upstream_task_ids == {"bronze"}
    assert dag.get_task("gold").upstream_task_ids == {"silver"}
    assert dag.get_task("cargar_gold").upstream_task_ids == {"gold"}
    assert dag.get_task("silver_spark_local").upstream_task_ids == {"elegir_computo"}
    assert dag.get_task("gold_spark_local").upstream_task_ids == {"silver_spark_local"}
    assert dag.get_task("gold_spark_local").downstream_task_ids == set()


def test_no_quedan_ramas_de_snowpark_ni_de_prod(dag):
    assert not [t for t in dag.task_ids if "snowpark" in t or "prod" in t]


def test_dag_es_manual_con_computo(dag):
    assert type(dag.timetable).__name__ == "NullTimetable"
    assert set(dag.params) == {"computo", "mes", "limite"}
    # Sin PIPELINE_ENTORNO el DAG es el de dev (Code Editor): spark_local por defecto.
    assert dag.params["computo"] == "spark_local"
    assert dag.params["mes"] is None
    assert dag.params["limite"] is None


def test_glue_toma_el_perfil_de_computo(dag):
    for step in ("silver", "gold"):
        tarea = dag.get_task(step)
        assert "params.computo" in tarea.job_name
        assert "params.computo" in str(tarea.run_job_kwargs["NumberOfWorkers"])
        assert tarea.run_job_kwargs["WorkerType"] == "G.1X"
        assert tarea.script_args["--env"] == "dev"
        assert tarea.verbose is True
    bronze = dag.get_task("bronze")
    assert bronze.job_name.endswith("-small") and bronze.run_job_kwargs["NumberOfWorkers"] == 2


def test_perfil_por_computo_se_renderiza_a_entero():
    import jinja2
    from framework.tasks import _segun_computo

    plantilla = jinja2.Template(_segun_computo({"small": 2, "medium": 4, "large": 6}))
    assert int(plantilla.render(params={"computo": "glue_large"})) == 6


@pytest.mark.parametrize(
    ("entorno", "computo", "limite", "esperado"),
    [
        ("dev", "spark_local", None, 10_000),
        ("dev", "spark_local", 100, 100),
        ("dev", "spark_local", 50_000, 10_000),
        ("dev", "glue_small", None, None),
        ("dev", "glue_small", 500, 500),
        ("prod", "glue_large", 500, None),
    ],
)
def test_limite_efectivo(entorno, computo, limite, esperado):
    from framework.tasks import limite_efectivo

    assert limite_efectivo(entorno, computo, limite) == esperado
