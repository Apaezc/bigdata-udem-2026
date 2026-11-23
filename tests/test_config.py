"""Entorno automático, pipeline.yaml y cargar_configuracion (precedencia y reglas de dev y prod)."""

from __future__ import annotations

import os
import re
from dataclasses import FrozenInstanceError
from pathlib import Path

import pytest

from pipeline.herramientas.corrida import (
    DEFECTOS,
    EntornoNoPermitido,
    LimiteNoPermitido,
    cargar_configuracion,
    entorno_actual,
    valores_de_pipeline_yaml,
)
from pipeline.herramientas.rutas import ConfigError

# Las fixtures entorno_limpio y poner_yaml viven en tests/p1_fixtures.py.
pytest_plugins = ["p1_fixtures"]
BUCKET = "bigdata-lake-123456789012-us-east-2"  # el que devuelve el doble de sts

YAML_COMPLETO = """
computo: glue_small
limite: "100000"
mes: "2024-03"
reprocesar: true
"""


# --- entorno_actual: nadie lo elige -----------------------------------------------------------


def test_el_entorno_por_defecto_es_dev(entorno_limpio):
    assert entorno_actual() == "dev"


def test_el_entorno_sale_de_la_variable_de_la_vm(entorno_limpio, monkeypatch):
    monkeypatch.setenv("PIPELINE_ENTORNO", "prod")
    assert entorno_actual() == "prod"


def test_dentro_de_glue_manda_el_env_que_paso_el_dag(entorno_limpio):
    assert entorno_actual({"env": "prod"}) == "prod"
    assert entorno_actual({"env": "dev"}) == "dev"


def test_un_entorno_desconocido_se_rechaza(entorno_limpio, monkeypatch):
    monkeypatch.setenv("PIPELINE_ENTORNO", "local")
    with pytest.raises(EntornoNoPermitido, match="solo hay dev y prod"):
        entorno_actual()


def test_cargar_configuracion_no_tiene_argumento_de_entorno(entorno_limpio):
    with pytest.raises(TypeError):
        cargar_configuracion(entorno="prod")


# --- valores_de_pipeline_yaml: nunca lanza -----------------------------------------------------


def test_el_pipeline_yaml_que_se_entrega_es_valido_y_trae_los_defectos(entorno_limpio):
    valores = valores_de_pipeline_yaml()
    assert valores["avisos"] == []
    assert valores["computo"] == DEFECTOS["computo"] == "code_editor"
    assert valores["limite"] == DEFECTOS["limite"] == "1000"
    assert valores["mes"] == DEFECTOS["mes"] == "2024-01"
    assert valores["reprocesar"] is False


def test_lee_los_cuatro_campos(poner_yaml):
    poner_yaml(YAML_COMPLETO)
    assert valores_de_pipeline_yaml() == {
        "computo": "glue_small",
        "limite": "100000",
        "mes": "2024-03",
        "reprocesar": True,
        "avisos": [],
    }


def test_un_limite_numerico_sin_comillas_tambien_vale(poner_yaml):
    poner_yaml("computo: code_editor\nlimite: 100000\nmes: ''\nreprocesar: false\n")
    valores = valores_de_pipeline_yaml()
    assert valores["limite"] == "100000"
    assert valores["mes"] == ""  # vacío = todos los meses de config/dev.yaml
    assert valores["avisos"] == []


def test_un_limite_invalido_no_lanza_y_da_el_defecto_con_aviso(poner_yaml):
    poner_yaml("computo: code_editor\nlimite: 12345\nmes: '2024-01'\nreprocesar: false\n")
    valores = valores_de_pipeline_yaml()
    assert valores["limite"] == "1000"
    assert valores["avisos"] == ["limite inválido en pipeline.yaml; se usó 1000"]


def test_un_computo_invalido_no_lanza_y_da_el_defecto_con_aviso(poner_yaml):
    poner_yaml("computo: foo\nlimite: '1000'\nmes: '2024-01'\nreprocesar: false\n")
    valores = valores_de_pipeline_yaml()
    assert valores["computo"] == "code_editor"
    assert valores["avisos"] == ["computo inválido en pipeline.yaml; se usó code_editor"]


def test_un_mes_y_un_reprocesar_invalidos_dan_el_defecto_con_aviso(poner_yaml):
    poner_yaml("computo: code_editor\nlimite: '1000'\nmes: enero\nreprocesar: quizas\n")
    valores = valores_de_pipeline_yaml()
    assert (valores["mes"], valores["reprocesar"]) == ("2024-01", False)
    assert len(valores["avisos"]) == 2


def test_un_campo_que_falta_da_el_defecto_con_aviso(poner_yaml):
    poner_yaml("computo: glue_small\n")
    valores = valores_de_pipeline_yaml()
    assert valores["computo"] == "glue_small"
    assert valores["limite"] == "1000"
    assert "falta limite en pipeline.yaml; se usó 1000" in valores["avisos"]
    assert len(valores["avisos"]) == 3


@pytest.mark.parametrize("texto", ["", "- una\n- lista\n", "computo: [sin cerrar\n", "solo texto"])
def test_un_yaml_roto_o_vacio_no_lanza(poner_yaml, texto):
    poner_yaml(texto)
    valores = valores_de_pipeline_yaml()
    assert (valores["computo"], valores["limite"]) == ("code_editor", "1000")
    assert valores["avisos"]


def test_un_yaml_que_no_existe_no_lanza(entorno_limpio, tmp_path):
    valores = valores_de_pipeline_yaml(str(tmp_path / "no_existe.yaml"))
    assert valores["computo"] == "code_editor"
    assert "no encontré pipeline.yaml" in valores["avisos"][0]


# --- cargar_configuracion en dev: argumento > yaml > defecto -----------------------------------


def test_sin_argumentos_manda_el_yaml(entorno_limpio, poner_yaml):
    poner_yaml(YAML_COMPLETO)
    corrida = cargar_configuracion()
    assert corrida.entorno == "dev"
    assert corrida.computo == "glue_small"
    assert corrida.limite == "100000"
    assert corrida.meses == ("2024-03",)
    assert corrida.reprocesar is True
    assert corrida.avisos == ()


def test_el_argumento_gana_sobre_el_yaml(entorno_limpio, poner_yaml):
    poner_yaml(YAML_COMPLETO)
    corrida = cargar_configuracion(
        mes="2024-05", computo="glue_large", limite="todos", reprocesar=False
    )
    assert corrida.meses == ("2024-05",)
    assert corrida.computo == "glue_large"
    assert corrida.limite == "todos"
    assert corrida.reprocesar is False


def test_cada_perilla_se_decide_por_separado(entorno_limpio, poner_yaml):
    poner_yaml(YAML_COMPLETO)
    corrida = cargar_configuracion(limite="1000")
    assert corrida.limite == "1000"  # del argumento
    assert corrida.computo == "glue_small"  # del yaml
    assert corrida.meses == ("2024-03",)  # del yaml


def test_sin_yaml_legible_se_usan_los_defectos_con_aviso(entorno_limpio, tmp_path, monkeypatch):
    monkeypatch.setenv("PIPELINE_YAML", str(tmp_path / "no_existe.yaml"))
    corrida = cargar_configuracion()
    assert (corrida.computo, corrida.limite, corrida.meses) == ("code_editor", "1000", ("2024-01",))
    assert "no encontré pipeline.yaml" in corrida.avisos[0]


def test_un_valor_invalido_del_yaml_pasa_a_la_corrida_como_aviso(entorno_limpio, poner_yaml):
    poner_yaml("computo: code_editor\nlimite: 12345\nmes: '2024-01'\nreprocesar: false\n")
    corrida = cargar_configuracion()
    assert corrida.limite == "1000"
    assert corrida.avisos == ("limite inválido en pipeline.yaml; se usó 1000",)


def test_un_aviso_del_yaml_no_sale_si_el_argumento_reemplaza_ese_campo(entorno_limpio, poner_yaml):
    poner_yaml("computo: code_editor\nlimite: 12345\nmes: '2024-01'\nreprocesar: false\n")
    assert cargar_configuracion(limite="100000").avisos == ()


@pytest.mark.parametrize(
    "perilla",
    [
        {"computo": "spark_local"},
        {"limite": "12345"},
        {"mes": "2024-13"},
        {"reprocesar": "quizas"},
    ],
)
def test_un_valor_invalido_de_un_argumento_es_config_error(entorno_limpio, poner_yaml, perilla):
    poner_yaml(YAML_COMPLETO)
    with pytest.raises(ConfigError):
        cargar_configuracion(**perilla)


def test_un_limite_entero_y_un_reprocesar_en_texto_se_aceptan(entorno_limpio, poner_yaml):
    poner_yaml(YAML_COMPLETO)
    corrida = cargar_configuracion(limite=100000, reprocesar="false")
    assert corrida.limite == "100000"
    assert corrida.reprocesar is False


def test_mes_vacio_son_todos_los_meses_de_config_dev(entorno_limpio, poner_yaml):
    poner_yaml(YAML_COMPLETO)
    assert cargar_configuracion(mes="").meses == ("2024-01",)


def test_limite_filas(entorno_limpio, poner_yaml):
    poner_yaml(YAML_COMPLETO)
    assert cargar_configuracion(limite="1000").limite_filas == 1000
    assert cargar_configuracion(limite="100000").limite_filas == 100000
    assert cargar_configuracion(limite="todos", computo="glue_small").limite_filas is None


# --- code_editor y limite todos ----------------------------------------------------------------


def test_todos_con_code_editor_pide_glue(entorno_limpio, poner_yaml):
    poner_yaml(YAML_COMPLETO)
    with pytest.raises(LimiteNoPermitido, match="Glue"):
        cargar_configuracion(computo="code_editor", limite="todos")


def test_todos_en_el_yaml_con_code_editor_tambien_falla(entorno_limpio, poner_yaml):
    poner_yaml("computo: code_editor\nlimite: todos\nmes: '2024-01'\nreprocesar: false\n")
    with pytest.raises(LimiteNoPermitido):
        cargar_configuracion()


@pytest.mark.parametrize("computo", ["glue_small", "glue_medium", "glue_large"])
def test_todos_con_glue_se_permite(entorno_limpio, poner_yaml, computo):
    poner_yaml(YAML_COMPLETO)
    assert cargar_configuracion(computo=computo, limite="todos").limite == "todos"


# --- prod: ignora el yaml, exige Glue y todos --------------------------------------------------


def test_prod_ignora_el_yaml_y_usa_glue_medium_con_todos(entorno_limpio, poner_yaml, monkeypatch):
    poner_yaml(YAML_COMPLETO)
    monkeypatch.setenv("PIPELINE_ENTORNO", "prod")
    corrida = cargar_configuracion()
    assert corrida.entorno == "prod"
    assert corrida.computo == "glue_medium"
    assert corrida.limite == "todos"
    assert corrida.reprocesar is False
    assert len(corrida.meses) == 12  # sin mes: los de config/prod.yaml
    assert corrida.avisos == ()


def test_prod_acepta_otro_glue_y_un_mes(entorno_limpio, monkeypatch):
    monkeypatch.setenv("PIPELINE_ENTORNO", "prod")
    corrida = cargar_configuracion(mes="2024-01", computo="glue_large", reprocesar=True)
    assert (corrida.computo, corrida.meses, corrida.reprocesar) == (
        "glue_large",
        ("2024-01",),
        True,
    )


def test_prod_rechaza_code_editor(entorno_limpio, monkeypatch):
    monkeypatch.setenv("PIPELINE_ENTORNO", "prod")
    with pytest.raises(EntornoNoPermitido, match="Glue"):
        cargar_configuracion(computo="code_editor")


@pytest.mark.parametrize("limite", ["1000", "100000"])
def test_prod_rechaza_un_limite_distinto_de_todos(entorno_limpio, monkeypatch, limite):
    monkeypatch.setenv("PIPELINE_ENTORNO", "prod")
    with pytest.raises(EntornoNoPermitido, match="todo"):
        cargar_configuracion(limite=limite)


def test_prod_acepta_limite_todos_explicito(entorno_limpio, monkeypatch):
    monkeypatch.setenv("PIPELINE_ENTORNO", "prod")
    assert cargar_configuracion(limite="todos").limite == "todos"


# --- defectos de conexión ----------------------------------------------------------------------


def test_dev_resuelve_el_secreto_y_el_bucket_sin_variables(entorno_limpio, poner_yaml):
    poner_yaml(YAML_COMPLETO)
    cargar_configuracion()
    assert os.environ["WATERMARK_SECRET"] == "bigdata/snowflake"
    assert os.environ["LAKE_BUCKET"] == BUCKET
    assert entorno_limpio == ["sts"]  # una sola pregunta a sts


def test_dev_usa_el_prefijo_del_fork_para_el_secreto(entorno_limpio, poner_yaml, monkeypatch):
    poner_yaml(YAML_COMPLETO)
    monkeypatch.setenv("PREFIX", "curso")
    cargar_configuracion()
    assert os.environ["WATERMARK_SECRET"] == "curso/snowflake"


def test_dev_respeta_las_variables_que_ya_existen(entorno_limpio, poner_yaml, monkeypatch):
    poner_yaml(YAML_COMPLETO)
    monkeypatch.setenv("WATERMARK_SECRET", "otro/secreto")
    monkeypatch.setenv("LAKE_BUCKET", "mi-bucket")
    cargar_configuracion()
    assert os.environ["WATERMARK_SECRET"] == "otro/secreto"
    assert os.environ["LAKE_BUCKET"] == "mi-bucket"
    assert entorno_limpio == []  # con bucket puesto no se pregunta a sts


def test_con_raiz_de_prueba_no_se_pregunta_a_sts(entorno_limpio, poner_yaml, raiz_lake):
    poner_yaml(YAML_COMPLETO)
    cargar_configuracion()
    assert entorno_limpio == []
    assert "LAKE_BUCKET" not in os.environ


def test_si_sts_falla_no_se_rompe_la_configuracion(entorno_limpio, poner_yaml, monkeypatch):
    import pipeline.herramientas.rutas as rutas

    def sts_sin_credenciales():
        raise RuntimeError("sin credenciales")

    poner_yaml(YAML_COMPLETO)
    monkeypatch.setattr(rutas, "_bucket_por_sts", sts_sin_credenciales)
    cargar_configuracion()  # el error claro sale al armar la primera ruta
    assert "LAKE_BUCKET" not in os.environ
    with pytest.raises(ConfigError, match="LAKE_BUCKET"):
        rutas.ruta_lake("dev", "bronze")


def test_prod_usa_el_secreto_de_prod_y_no_adivina_el_bucket(entorno_limpio, monkeypatch):
    monkeypatch.setenv("PIPELINE_ENTORNO", "prod")
    cargar_configuracion()
    assert os.environ["WATERMARK_SECRET"] == "bigdata/snowflake_prod"
    assert "LAKE_BUCKET" not in os.environ
    assert entorno_limpio == []


# --- la corrida --------------------------------------------------------------------------------


def test_la_corrida_trae_un_id_y_una_fecha_sin_microsegundos(entorno_limpio, poner_yaml):
    poner_yaml(YAML_COMPLETO)
    corrida = cargar_configuracion()
    assert re.fullmatch(r"\d{8}T\d{6}Z_[0-9a-f]{6}", corrida.id_lote)
    assert corrida.fecha_ingesta.microsecond == 0
    assert corrida.fecha_ingesta.tzinfo is not None
    assert corrida.id_lote.startswith(corrida.fecha_ingesta.strftime("%Y%m%dT%H%M%SZ"))


def test_cada_corrida_tiene_su_propio_id(entorno_limpio, poner_yaml):
    poner_yaml(YAML_COMPLETO)
    assert cargar_configuracion().id_lote != cargar_configuracion().id_lote


def test_la_corrida_no_se_puede_modificar(entorno_limpio, poner_yaml):
    poner_yaml(YAML_COMPLETO)
    corrida = cargar_configuracion()
    with pytest.raises(FrozenInstanceError):
        corrida.computo = "glue_large"


def test_el_pipeline_yaml_de_la_raiz_esta_donde_lo_busca_el_codigo():
    raiz = Path(__file__).resolve().parents[1]
    assert (raiz / "pipeline.yaml").is_file()
