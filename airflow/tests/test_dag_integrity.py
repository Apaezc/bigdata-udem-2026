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
    for step in ("bronze", "silver", "gold"):
        tarea = dag.get_task(step)
        assert "params.computo" in tarea.job_name
        assert "params.computo" in str(tarea.run_job_kwargs["NumberOfWorkers"])
        assert tarea.run_job_kwargs["WorkerType"] == "G.1X"
        assert tarea.script_args["--env"] == "dev"
        assert tarea.verbose is True


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


# --- DAG ingesta_mensual (clase 6): zonas -> clima -> viajes -> silver -> gold -----------------

DAG_MENSUAL = "ingesta_mensual"
CADENA_MENSUAL = ["ingestar_zonas", "ingestar_clima", "ingestar_viajes", "silver", "gold"]


@pytest.fixture(scope="module")
def dag_mensual(dag_bag):
    return dag_bag.dags[DAG_MENSUAL]


def test_ingesta_mensual_carga_sin_errores(dag_bag):
    assert dag_bag.import_errors == {}, dag_bag.import_errors
    assert DAG_MENSUAL in dag_bag.dags


def test_ingesta_mensual_cadena_en_orden(dag_mensual):
    assert sorted(dag_mensual.task_ids) == sorted(CADENA_MENSUAL)
    assert dag_mensual.get_task("ingestar_zonas").upstream_task_ids == set()
    for anterior, siguiente in zip(CADENA_MENSUAL, CADENA_MENSUAL[1:], strict=False):
        assert dag_mensual.get_task(siguiente).upstream_task_ids == {anterior}
    assert dag_mensual.get_task("gold").downstream_task_ids == set()


def test_ingesta_mensual_params_y_calendario(dag_mensual):
    assert set(dag_mensual.params) == {"mes", "reprocesar"}
    assert dag_mensual.params["reprocesar"] is False
    assert dag_mensual.params["mes"] == ""  # vacío: las tareas exigen el mes al disparar a mano
    assert dag_mensual.catchup is False
    assert dag_mensual.is_paused_upon_creation is True
    assert type(dag_mensual.timetable).__name__ == "NullTimetable"  # en clase se dispara a mano


def test_ingesta_mensual_reintenta_una_vez_con_espera_corta(dag_mensual):
    for tarea in dag_mensual.tasks:
        assert tarea.retries == 1, tarea.task_id
        assert tarea.retry_delay.total_seconds() <= 60, tarea.task_id


def test_ingesta_mensual_corre_con_el_python_del_repo(dag_mensual):
    for tarea in dag_mensual.tasks:
        assert tarea.python.endswith(".venv/bin/python"), tarea.task_id


def test_ingesta_mensual_usa_modo_de_prueba_para_los_viajes(dag_mensual):
    viajes = dag_mensual.get_task("ingestar_viajes").op_kwargs
    assert viajes["limite_filas"] == 1000
    assert viajes["tabla"].startswith("prueba")  # la guarda del lab exige tabla de prueba
    assert dag_mensual.get_task("ingestar_zonas").op_kwargs["tabla"].startswith("prueba")


def test_ingesta_mensual_mes_y_reprocesar_vienen_de_params(dag_mensual):
    import jinja2

    plantilla = jinja2.Template(dag_mensual.get_task("ingestar_clima").op_kwargs["mes"])
    assert plantilla.render(params={"mes": "2024-01"}) == "2024-01"
    # Sin mes y sin corrida programada no hay mes: la tarea falla pidiéndolo.
    assert (
        plantilla.render(params={"mes": ""}, dag_run=type("R", (), {"run_type": "manual"})()) == ""
    )
    reprocesar = jinja2.Template(dag_mensual.get_task("silver").op_kwargs["reprocesar"])
    assert reprocesar.render(params={"reprocesar": True}) == "True"


# --- DAG hola_airflow (clase 6): saludar -> esperar -> reintentar -------------------------------

DAG_HOLA = "hola_airflow"
CADENA_HOLA = ["saludar", "esperar", "reintentar"]


@pytest.fixture(scope="module")
def dag_hola(dag_bag):
    return dag_bag.dags[DAG_HOLA]


def test_hola_airflow_carga_sin_errores(dag_bag):
    assert dag_bag.import_errors == {}, dag_bag.import_errors
    assert DAG_HOLA in dag_bag.dags


def test_hola_airflow_tres_tareas_en_orden(dag_hola):
    assert sorted(dag_hola.task_ids) == sorted(CADENA_HOLA)
    assert dag_hola.get_task("saludar").upstream_task_ids == set()
    for anterior, siguiente in zip(CADENA_HOLA, CADENA_HOLA[1:], strict=False):
        assert dag_hola.get_task(siguiente).upstream_task_ids == {anterior}
    assert dag_hola.get_task("reintentar").downstream_task_ids == set()


def test_hola_airflow_reintenta_una_vez_con_espera_de_10_segundos(dag_hola):
    for tarea in dag_hola.tasks:
        assert tarea.retries == 1, tarea.task_id
        assert tarea.retry_delay.total_seconds() == 10, tarea.task_id


def test_hola_airflow_param_mes_y_disparo_manual(dag_hola):
    assert set(dag_hola.params) == {"mes"}
    assert dag_hola.params["mes"] == "2024-02"
    assert dag_hola.catchup is False
    assert type(dag_hola.timetable).__name__ == "NullTimetable"


def test_hola_airflow_interruptor_del_reto_apagado():
    # El archivo se entrega con FALLAR_SIEMPRE = False: con True la tarea nunca pasa.
    texto = (DAGS_DIR / "hola_airflow.py").read_text(encoding="utf-8")
    assert "\nFALLAR_SIEMPRE = False\n" in texto
