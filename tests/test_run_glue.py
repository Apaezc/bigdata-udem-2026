from __future__ import annotations

import os
from datetime import UTC, datetime

import pytest

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


# --- registro en la tabla de control desde los pasos de Glue -------------------------------------


def test_run_glue_acepta_el_secreto_de_snowflake():
    argv = resueltos_a_argv({"step": "silver", "env": "dev", "snowflake_secret": "p/snowflake"})
    assert build_parser().parse_args(argv).snowflake_secret == "p/snowflake"


def _preparar_run(monkeypatch, falla_en=None):
    """Deja run.main con Spark y pasos falsos; devuelve (run, orden de llamadas)."""
    from pipeline import run

    llamadas = []

    class PasoFalso:
        def __init__(self, nombre):
            self.nombre = nombre

        def main(self, spark, cfg, ns):
            llamadas.append(f"paso:{self.nombre}")
            if self.nombre == falla_en:
                raise RuntimeError("falló")

    def registrar_falso(spark, cfg, paso, meses, inicio):
        llamadas.append(f"registro:{paso}:{','.join(meses)}")

    monkeypatch.setattr(run, "PASOS", {n: PasoFalso(n) for n in ("bronze", "silver", "gold")})
    monkeypatch.setattr(run.engine, "get_spark", lambda motor: object())
    monkeypatch.setattr(run, "registrar_paso", registrar_falso)
    monkeypatch.setenv("LAKE_BUCKET", "bucket-x")
    return run, llamadas


def test_glue_registra_despues_de_cada_paso_que_termina_bien(monkeypatch):
    run, llamadas = _preparar_run(monkeypatch)
    run.main(["--step", "all", "--env", "dev", "--engine", "glue", "--mes", "2024-01"])
    assert llamadas == [
        "paso:bronze",
        "registro:bronze:2024-01",
        "paso:silver",
        "registro:silver:2024-01",
        "paso:gold",
        "registro:gold:2024-01",
    ]


def test_glue_no_registra_el_paso_que_falla(monkeypatch):
    run, llamadas = _preparar_run(monkeypatch, falla_en="silver")
    with pytest.raises(RuntimeError):
        run.main(["--step", "all", "--env", "dev", "--engine", "glue", "--mes", "2024-01"])
    assert llamadas == ["paso:bronze", "registro:bronze:2024-01", "paso:silver"]


def test_fuera_de_glue_no_se_registra(monkeypatch):
    run, llamadas = _preparar_run(monkeypatch)
    run.main(["--step", "silver", "--env", "dev", "--engine", "local", "--mes", "2024-01"])
    assert llamadas == ["paso:silver"]


def test_el_argumento_del_secreto_fija_la_variable_de_entorno(monkeypatch):
    run, _ = _preparar_run(monkeypatch)
    monkeypatch.delenv("WATERMARK_SECRET", raising=False)
    argv = ["--step", "silver", "--env", "dev", "--engine", "local", "--snowflake-secret", "p/sf"]
    run.main(argv)
    assert os.environ.pop("WATERMARK_SECRET") == "p/sf"


class DataFrameContable:
    def __init__(self, filas):
        self.filas = filas

    def count(self):
        return self.filas

    def where(self, condicion):
        return self


class SparkFalso:
    """Spark falso: cualquier parquet que se lea tiene 40 filas (sirve para gold)."""

    class read:  # noqa: N801
        @staticmethod
        def parquet(ruta):
            return DataFrameContable(40)


def test_registrar_paso_arma_la_fila_con_el_entorno_en_la_tabla(monkeypatch):
    from pipeline import run

    guardadas = []
    monkeypatch.setattr(run.io, "leer_viajes", lambda spark, base, meses: DataFrameContable(1000))
    monkeypatch.setattr(run.io, "leer_silver", lambda spark, cfg, meses: DataFrameContable(900))
    monkeypatch.setattr(run.watermark, "registrar_watermark", lambda *a: guardadas.append(a))
    cfg = {
        "entorno": "prod",
        "rutas": {
            "bronze": "s3://b/prod/bronze",
            "silver": "s3://b/prod/silver",
            "gold": "s3://b/prod/gold",
        },
    }
    inicio = datetime(2026, 11, 20, tzinfo=UTC)
    for paso in ("bronze", "silver", "gold"):
        run.registrar_paso(SparkFalso(), cfg, paso, ["2024-01"], inicio)

    bronze, silver, gold = guardadas
    assert bronze[0].endswith("fhvhv_tripdata_2024-01.parquet")
    assert bronze[1:] == ("bronze", "prod/fhvhv", "2024-01", 1000, inicio, False)
    assert silver == (
        "s3://b/prod/bronze",
        "silver",
        "prod/fhvhv_trips",
        "2024-01",
        900,
        inicio,
        False,
    )
    assert gold == (
        "s3://b/prod/silver",
        "gold",
        "prod/daily_zone_metrics",
        "2024-01",
        40,
        inicio,
        False,
    )
