"""Integridad de los DAGs: carga sin errores, tareas, orden y qué se queda fuera de prod.

pipeline_taxi son cuatro tareas lineales con el nombre de las funciones de pipeline/correr.py;
resetear_entorno son seis. Los parámetros y las barandillas de prod están en test_params.py; la
lógica del reseteo, en test_reseteo_dag.py.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

AIRFLOW_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = AIRFLOW_ROOT.parent
DAGS_DIR = AIRFLOW_ROOT / "dags"
DAG_ID = "pipeline_taxi"
CADENA_PIPELINE = ["correr_bronze", "correr_silver", "correr_gold", "cargar_snowflake"]
CADENA_RESETEO = [
    "validar",
    "contar",
    "vaciar_control",
    "borrar_snowflake",
    "borrar_s3",
    "resumen",
]


@pytest.fixture(scope="module")
def dag_bag():
    from airflow.dag_processing.dagbag import DagBag

    return DagBag(dag_folder=str(DAGS_DIR))


@pytest.fixture(scope="module")
def dag(dag_bag):
    # dags[...] evita consultar la base de datos de Airflow (no hay DB en el test).
    return dag_bag.dags[DAG_ID]


def _cadena(dag_con_tareas, ids: list[str]) -> None:
    """Las tareas forman una línea recta, en ese orden."""
    assert sorted(dag_con_tareas.task_ids) == sorted(ids)
    assert dag_con_tareas.get_task(ids[0]).upstream_task_ids == set()
    for anterior, siguiente in zip(ids, ids[1:], strict=False):
        assert dag_con_tareas.get_task(siguiente).upstream_task_ids == {anterior}
        assert dag_con_tareas.get_task(anterior).downstream_task_ids == {siguiente}
    assert dag_con_tareas.get_task(ids[-1]).downstream_task_ids == set()


def test_no_import_errors(dag_bag):
    assert dag_bag.import_errors == {}, dag_bag.import_errors
    assert {DAG_ID, "resetear_entorno"} <= set(dag_bag.dags)


def test_pipeline_taxi_son_cuatro_tareas_lineales_con_el_nombre_de_las_funciones(dag):
    _cadena(dag, CADENA_PIPELINE)
    from pipeline import correr

    for nombre in CADENA_PIPELINE:
        assert callable(getattr(correr, nombre)), nombre  # misma función que la celda y make


def test_pipeline_taxi_sin_ramas_ni_tareas_de_la_version_anterior(dag):
    viejas = {"preparar_entorno", "elegir_computo", "bronze", "silver", "gold", "cargar_gold"}
    assert not viejas & set(dag.task_ids)
    assert not [t for t in dag.task_ids if "snowpark" in t or "spark_local" in t]
    assert [type(t).__name__ for t in dag.tasks] == ["PythonOperator"] * 4  # sin Branch ni Glue


def test_pipeline_taxi_es_manual_y_corre_de_a_una(dag):
    assert type(dag.timetable).__name__ == "NullTimetable"
    assert dag.catchup is False
    assert dag.max_active_runs == 1
    assert dag.max_active_tasks == 1
    for tarea in dag.tasks:
        assert tarea.retries == 0, tarea.task_id  # una corrida mal hecha no se repite sola


def test_pipeline_taxi_dice_el_entorno_en_la_descripcion_y_el_doc_md(dag):
    assert "DEV" in dag.description
    assert "DEV" in dag.doc_md
    assert "dev" in dag.tags


def test_el_dag_se_parsea_sin_pyspark():
    """En un intérprete limpio: parsear los DAGs no importa pyspark (la VM no lo tiene)."""
    codigo = (
        "import sys; from airflow.dag_processing.dagbag import DagBag; "
        f"b = DagBag(dag_folder={str(DAGS_DIR)!r}); "
        "assert b.import_errors == {}, b.import_errors; "
        "assert 'pyspark' not in sys.modules, 'se importó pyspark al parsear'"
    )
    resultado = subprocess.run(
        [sys.executable, "-c", codigo], capture_output=True, text=True, timeout=180
    )
    assert resultado.returncode == 0, resultado.stderr[-2000:]


# --- resetear_entorno ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def dag_reseteo(dag_bag):
    return dag_bag.dags["resetear_entorno"]


def test_resetear_entorno_orden_control_snowflake_s3(dag_reseteo):
    _cadena(dag_reseteo, CADENA_RESETEO)
    # el control primero: si algo falla a medias queda «no procesado», nunca «procesado sin datos»
    ids = CADENA_RESETEO
    assert ids.index("vaciar_control") < ids.index("borrar_snowflake") < ids.index("borrar_s3")


def test_resetear_entorno_nace_pausado_manual_y_con_salvaguardas(dag_reseteo):
    assert dag_reseteo.is_paused_upon_creation is True
    assert type(dag_reseteo.timetable).__name__ == "NullTimetable"
    assert dag_reseteo.max_active_runs == 1
    assert set(dag_reseteo.params) == {"entorno", "solo_listar", "confirmacion", "conservar_crudo"}
    assert dag_reseteo.params["solo_listar"] is True  # por defecto no borra
    assert dag_reseteo.params["confirmacion"] == ""  # por defecto no confirma nada
    assert dag_reseteo.params["conservar_crudo"] is False
    # el entorno solo admite el de este Airflow (dev en el Code Editor)
    assert dag_reseteo.params["entorno"] == "dev"
    assert dag_reseteo.params.get_param("entorno").schema["enum"] == ["dev"]
    assert "dev" in dag_reseteo.doc_md


def test_resetear_entorno_no_reintenta(dag_reseteo):
    for tarea in dag_reseteo.tasks:
        assert tarea.retries == 0, tarea.task_id
