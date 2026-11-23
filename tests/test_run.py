"""CLI del pipeline: --paso, las perillas, los alias viejos y lo que ya no existe."""

from __future__ import annotations

import pytest

import pipeline.correr as correr
from pipeline.run import build_parser, main


@pytest.fixture
def llamadas(monkeypatch):
    """correr_paso falso: anota (paso, perillas) y no hace nada."""
    anotadas = []

    def falso(paso, **perillas):
        anotadas.append((paso, perillas))

    monkeypatch.setattr(correr, "correr_paso", falso)
    return anotadas


def test_sin_argumentos_corre_los_cuatro_pasos_en_orden(llamadas):
    assert main([]) == 0
    assert [paso for paso, _ in llamadas] == ["bronze", "silver", "gold", "snowflake"]
    # sin perilla: todo None, o sea lo que diga pipeline.yaml
    assert llamadas[0][1] == {"mes": None, "computo": None, "limite": None, "reprocesar": None}


def test_un_paso_con_todas_las_perillas(llamadas):
    argv = ["--paso", "silver", "--computo", "glue_small", "--mes", "2024-02"]
    argv += ["--limite", "100000", "--reprocesar", "true"]
    assert main(argv) == 0
    assert llamadas == [
        (
            "silver",
            {"mes": "2024-02", "computo": "glue_small", "limite": "100000", "reprocesar": True},
        )
    ]


def test_reprocesar_sin_valor_es_verdadero_y_con_false_es_falso():
    assert build_parser().parse_args(["--reprocesar"]).reprocesar is True
    assert build_parser().parse_args(["--reprocesar", "false"]).reprocesar is False
    assert build_parser().parse_args(["--reprocesar", "true"]).reprocesar is True
    assert build_parser().parse_args([]).reprocesar is None


@pytest.mark.parametrize(
    "argv",
    [
        ["--paso", "muestra"],
        ["--paso", "todo"],
        ["--step", "gold"],
        ["--env", "prod"],
        ["--engine", "glue"],
        ["--computo", "spark_local"],
        ["--limite", "5"],
        ["--mes", "2024-13"],
        ["--reprocesar", "quizas"],
    ],
)
def test_los_valores_que_no_existen_se_rechazan(argv, llamadas):
    with pytest.raises(SystemExit) as salida:
        main(argv)
    assert salida.value.code == 2
    assert llamadas == []


def test_un_error_de_configuracion_sale_con_codigo_2_y_mensaje(monkeypatch, capsys):
    from pipeline.herramientas.corrida import LimiteNoPermitido

    def rechaza(paso, **perillas):
        raise LimiteNoPermitido("usa un cómputo de Glue")

    monkeypatch.setattr(correr, "correr_paso", rechaza)
    assert main(["--paso", "silver", "--computo", "code_editor", "--limite", "todos"]) == 2
    assert "ERROR: usa un cómputo de Glue" in capsys.readouterr().err


def test_un_error_del_paso_no_se_esconde(monkeypatch):
    def falla(paso, **perillas):
        raise RuntimeError("falló la escritura")

    monkeypatch.setattr(correr, "correr_paso", falla)
    with pytest.raises(RuntimeError, match="falló la escritura"):
        main(["--paso", "bronze"])
