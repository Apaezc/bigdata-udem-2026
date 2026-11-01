from __future__ import annotations

from pipeline.run import build_parser
from pipeline.run_glue import resueltos_a_argv


def test_argv_de_glue_fija_engine_y_normaliza_guiones():
    argv = resueltos_a_argv(
        {"step": "silver", "env": "dev", "mes": "2024-01", "lake_bucket": "bigdata-lake-x"}
    )
    args = build_parser().parse_args(argv)
    assert args.engine == "glue"
    assert (args.step, args.env, args.mes, args.lake_bucket) == (
        "silver",
        "dev",
        "2024-01",
        "bigdata-lake-x",
    )


def test_argv_de_glue_ignora_claves_ajenas_y_valores_none():
    argv = resueltos_a_argv(
        {"step": "bronze", "env": "dev", "JOB_NAME": None, "job_bookmark_option": None, "mes": None}
    )
    args = build_parser().parse_args(argv)
    assert (args.step, args.env, args.mes) == ("bronze", "dev", None)


def test_argv_de_glue_ignora_todos_y_cero():
    argv = resueltos_a_argv({"step": "silver", "env": "prod", "mes": "todos", "limite": "0"})
    args = build_parser().parse_args(argv)
    assert (args.mes, args.limite) == (None, None)
    argv = resueltos_a_argv({"step": "silver", "env": "dev", "mes": "2024-03", "limite": "500"})
    args = build_parser().parse_args(argv)
    assert (args.mes, args.limite) == ("2024-03", 500)
