"""run_glue.py: entrada mínima y estable de Glue; lee argumentos, deja el entorno, corre el paso."""

from __future__ import annotations

import inspect
import os

import pytest

import pipeline.correr as correr
import pipeline.run_glue as run_glue
from pipeline.run_glue import build_parser, main, resueltos_a_argv

pytest_plugins = ["p1_fixtures"]


@pytest.fixture
def llamadas(monkeypatch, entorno_limpio):
    anotadas = []

    def falso(paso, **extra):
        anotadas.append((paso, extra))
        return []

    monkeypatch.setattr(correr, "correr_paso", falso)
    return anotadas


def test_resueltos_a_argv_normaliza_guiones_y_ignora_lo_ajeno():
    argv = resueltos_a_argv(
        {
            "step": "silver",
            "env": "dev",
            "lake_bucket": "bigdata-lake-x",
            "JOB_NAME": "bigdata-small",
            "job_bookmark_option": None,
            "mes": None,
        }
    )
    args = build_parser().parse_args(argv)
    assert (args.step, args.env, args.lake_bucket, args.mes) == (
        "silver",
        "dev",
        "bigdata-lake-x",
        None,
    )


def test_el_run_de_glue_pasa_todas_las_perillas_a_correr_paso(llamadas):
    argv = ["--step", "silver", "--env", "dev", "--mes", "2024-01", "--limite", "100000"]
    argv += ["--reprocesar", "true", "--computo", "glue_small", "--lake-bucket", "b-x"]
    argv += ["--snowflake-secret", "p/snowflake"]
    assert main(argv) == 0
    assert llamadas == [
        (
            "silver",
            {
                "en_glue": True,
                "mes": "2024-01",
                "computo": "glue_small",
                "limite": "100000",
                "reprocesar": True,
            },
        )
    ]


def test_deja_el_entorno_y_las_conexiones_en_variables(llamadas, monkeypatch):
    # entorno_limpio ya dejó estas variables restauradas al terminar la prueba
    argv = ["--step", "gold", "--env", "prod", "--lake-bucket", "b-prod"]
    argv += ["--snowflake-secret", "p/snowflake_prod"]
    main(argv)
    assert os.environ["PIPELINE_ENTORNO"] == "prod"
    assert os.environ["LAKE_BUCKET"] == "b-prod"
    assert os.environ["WATERMARK_SECRET"] == "p/snowflake_prod"
    from pipeline.herramientas.corrida import entorno_actual

    assert entorno_actual() == "prod"
    for variable in ("PIPELINE_ENTORNO", "LAKE_BUCKET", "WATERMARK_SECRET"):
        monkeypatch.delenv(variable)


@pytest.mark.parametrize("mes", ["todos", "0", ""])
def test_un_mes_vacio_o_todos_son_todos_los_meses(llamadas, mes):
    main(["--step", "silver", "--mes", mes])
    assert llamadas[0][1]["mes"] == ""  # '' y no None: None sería «lo que diga el yaml»


def test_sin_mes_en_glue_son_todos_los_meses_y_sin_reprocesar_es_none(llamadas):
    main(["--step", "silver"])
    assert (
        llamadas[0][1]["mes"] == ""
    )  # en Glue no hay yaml: sin mes = los de config/<entorno>.yaml
    assert llamadas[0][1]["reprocesar"] is None


def test_reprocesar_false_llega_como_falso(llamadas):
    main(["--step", "silver", "--reprocesar", "false"])
    assert llamadas[0][1]["reprocesar"] is False


def test_el_paso_es_obligatorio(llamadas):
    with pytest.raises(SystemExit):
        main(["--env", "dev"])


def test_run_glue_no_tiene_logica_propia():
    """El script del job no se puede cambiar por corrida: tiene que ser corto y sin Spark."""
    fuente = inspect.getsource(run_glue)
    assert len(fuente.splitlines()) < 110
    assert "import pyspark" not in fuente
    assert "from pyspark" not in fuente
