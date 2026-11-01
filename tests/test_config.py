from __future__ import annotations

from datetime import date

import pytest

from pipeline.settings import ConfigError, cargar, inicio_fin_mes, rango_meses, validar_mes


def test_local_lee_la_muestra_con_rutas_absolutas():
    cfg = cargar("local")
    assert cfg["rutas"]["bronze"].endswith("/lake/muestra")
    assert cfg["rutas"]["bronze"].startswith("/")
    assert cfg["muestra"]["sincronizar_desde"] == "muestra"
    assert cfg["muestra"]["max_rows"] is None
    assert cfg["meses"] == ["2024-01"]


def test_dev_exige_lake_bucket(monkeypatch):
    monkeypatch.delenv("LAKE_BUCKET", raising=False)
    with pytest.raises(ConfigError, match="LAKE_BUCKET"):
        cargar("dev")


@pytest.mark.parametrize("env", ["dev", "prod"])
def test_dev_y_prod_comparten_bronze_y_separan_silver_y_gold(monkeypatch, env):
    monkeypatch.setenv("LAKE_BUCKET", "bigdata-lake-test-us-east-2")
    cfg = cargar(env)
    assert cfg["rutas"]["bronze"] == "s3://bigdata-lake-test-us-east-2/bronze"
    assert cfg["rutas"]["silver"] == f"s3://bigdata-lake-test-us-east-2/{env}/silver"
    assert cfg["rutas"]["gold"] == f"s3://bigdata-lake-test-us-east-2/{env}/gold"
    assert cfg["muestra"]["destino"] == "s3://bigdata-lake-test-us-east-2/muestra"
    assert cfg["muestra"]["max_rows"] is None


def test_prod_procesa_el_anio_y_dev_un_mes(monkeypatch):
    monkeypatch.setenv("LAKE_BUCKET", "x")
    assert cargar("dev")["meses"] == ["2024-01"]
    assert len(cargar("prod")["meses"]) == 12


def test_entorno_desconocido():
    with pytest.raises(ConfigError):
        cargar("qa")


def test_inicio_fin_mes_incluye_cambio_de_anio():
    assert inicio_fin_mes("2024-12") == (date(2024, 12, 1), date(2025, 1, 1))
    assert inicio_fin_mes("2024-02") == (date(2024, 2, 1), date(2024, 3, 1))


@pytest.mark.parametrize("mes", ["2024-13", "24-01", "2024/01", ""])
def test_validar_mes_rechaza_formato_invalido(mes):
    with pytest.raises(ValueError):
        validar_mes(mes)


def test_rango_meses_ordena_y_cubre_todo():
    assert rango_meses(["2024-03", "2024-01"]) == (date(2024, 1, 1), date(2024, 4, 1))
    with pytest.raises(ValueError):
        rango_meses([])
