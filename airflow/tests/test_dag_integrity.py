"""Integridad de los DAGs: carga sin errores, tareas, orden y qué se queda fuera de prod.

pipeline_taxi son cuatro tareas lineales con el nombre de las funciones de pipeline/correr.py;
resetear_entorno son seis; ingesta_mensual (tres tareas) y hola_airflow son ejercicios del Airflow
del Code Editor y no se sincronizan con la VM. Los parámetros y las barandillas de prod están en
test_params.py; la lógica del reseteo, en test_reseteo_dag.py.
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
    assert {DAG_ID, "resetear_entorno", "ingesta_mensual", "hola_airflow"} <= set(dag_bag.dags)


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


# --- DAG ingesta_mensual (práctica de las clases 5 y 6): zonas -> clima -> viajes ---------------

DAG_MENSUAL = "ingesta_mensual"
CADENA_MENSUAL = ["ingestar_zonas", "ingestar_clima", "ingestar_viajes"]


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
    assert dag_mensual.get_task("ingestar_viajes").downstream_task_ids == set()


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
    reprocesar = jinja2.Template(dag_mensual.get_task("ingestar_zonas").op_kwargs["reprocesar"])
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
