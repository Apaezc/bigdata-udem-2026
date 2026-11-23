"""Formulario de pipeline_taxi: Params, defectos de pipeline.yaml y barandillas de prod.

- El entorno NO es un parámetro y el doc_md lo dice.
- En dev los valores iniciales salen de pipeline.yaml; un yaml roto no rompe el parseo.
- En prod los enums solo traen glue_* y `todos`, y no se lee el yaml.
- Un cómputo o un límite ajenos (por `dags trigger --conf`) hacen fallar la tarea antes de
  tocar nada.
"""

from __future__ import annotations

import logging
from pathlib import Path

import pytest

AIRFLOW_ROOT = Path(__file__).resolve().parents[1]
DAGS_DIR = AIRFLOW_ROOT / "dags"
ARCHIVO_DAG = DAGS_DIR / "pipeline_taxi.py"


def _parsear(monkeypatch, entorno=None, yaml_texto=None, tmp_path=None):
    """Parsea pipeline_taxi.py en un entorno (y con un pipeline.yaml) dados; devuelve el DagBag."""
    from airflow.dag_processing.dagbag import DagBag

    if entorno is None:
        monkeypatch.delenv("PIPELINE_ENTORNO", raising=False)
    else:
        monkeypatch.setenv("PIPELINE_ENTORNO", entorno)
    if yaml_texto is not None:
        archivo = tmp_path / "pipeline.yaml"
        archivo.write_text(yaml_texto, encoding="utf-8")
        monkeypatch.setenv("PIPELINE_YAML", str(archivo))
    else:
        monkeypatch.delenv("PIPELINE_YAML", raising=False)
    return DagBag(dag_folder=str(ARCHIVO_DAG))


def _formulario(bolsa) -> dict:
    assert bolsa.import_errors == {}, bolsa.import_errors
    return bolsa.dags["pipeline_taxi"]


def _opciones(dag, nombre):
    return dag.params.get_param(nombre).schema.get("enum")


YAML_BUENO = """\
computo: glue_small
limite: "100000"
mes: "2024-03"
reprocesar: true
"""


# --- dev: el formulario -----------------------------------------------------------------------


def test_cuatro_params_y_ninguno_es_el_entorno(monkeypatch):
    dag = _formulario(_parsear(monkeypatch))
    assert set(dag.params) == {"computo", "limite", "mes", "reprocesar"}
    assert "entorno" not in dag.params
    assert "env" not in dag.params


def test_el_doc_md_dice_que_el_entorno_no_se_elige(monkeypatch):
    dag = _formulario(_parsear(monkeypatch))
    assert "Entorno: DEV" in dag.doc_md
    assert "no se elige" in dag.doc_md
    assert "PROD" not in dag.doc_md.replace("BIGDATA.PROD", "").replace("CONTROL_PROD", "")


def test_los_enums_de_dev_ofrecen_los_cuatro_computos_y_los_tres_limites(monkeypatch):
    dag = _formulario(_parsear(monkeypatch))
    assert _opciones(dag, "computo") == ["code_editor", "glue_small", "glue_medium", "glue_large"]
    assert _opciones(dag, "limite") == ["1000", "100000", "todos"]  # texto, no números


def test_el_mes_se_valida_con_el_patron_aaaa_mm(monkeypatch):
    from airflow.sdk.definitions.param import ParamValidationError

    dag = _formulario(_parsear(monkeypatch))
    mes = dag.params.get_param("mes")
    for bueno in ("2024-01", "2024-12", ""):
        assert mes.resolve(bueno) == bueno
    for malo in ("2024-13", "2024-00", "24-01", "enero", "2024-1", "2024-01-01"):
        with pytest.raises(ParamValidationError):
            mes.resolve(malo)


def test_reprocesar_es_una_casilla(monkeypatch):
    dag = _formulario(_parsear(monkeypatch))
    assert dag.params.get_param("reprocesar").schema["type"] == "boolean"


def test_los_defectos_salen_de_pipeline_yaml_de_la_raiz(monkeypatch):
    from pipeline.herramientas.corrida import valores_de_pipeline_yaml

    esperado = valores_de_pipeline_yaml()
    dag = _formulario(_parsear(monkeypatch))
    assert dag.params["computo"] == esperado["computo"]
    assert dag.params["limite"] == esperado["limite"]
    assert dag.params["mes"] == esperado["mes"]
    assert dag.params["reprocesar"] == esperado["reprocesar"]


def test_otro_pipeline_yaml_cambia_los_defectos_del_formulario(monkeypatch, tmp_path):
    dag = _formulario(_parsear(monkeypatch, yaml_texto=YAML_BUENO, tmp_path=tmp_path))
    assert dag.params["computo"] == "glue_small"
    assert dag.params["limite"] == "100000"
    assert dag.params["mes"] == "2024-03"
    assert dag.params["reprocesar"] is True


# --- dev: yaml inválido (nunca un error de importación) ---------------------------------------


@pytest.mark.parametrize(
    ("yaml_texto", "esperado", "aviso"),
    [
        (
            'computo: code_editor\nlimite: 12345\nmes: "2024-01"\nreprocesar: false\n',
            "limite",
            "1000",
        ),
        (
            'computo: foo\nlimite: "1000"\nmes: "2024-01"\nreprocesar: false\n',
            "computo",
            "code_editor",
        ),
        (
            'computo: code_editor\nlimite: "1000"\nmes: "enero"\nreprocesar: false\n',
            "mes",
            "2024-01",
        ),
        (
            'computo: code_editor\nlimite: "1000"\nmes: "2024-01"\nreprocesar: quizas\n',
            "reprocesar",
            "False",
        ),
        ("computo: code_editor\n", "limite", "1000"),  # faltan campos
    ],
)
def test_un_yaml_con_valores_malos_parsea_con_defectos_y_avisa(
    monkeypatch, tmp_path, yaml_texto, esperado, aviso
):
    dag = _formulario(_parsear(monkeypatch, yaml_texto=yaml_texto, tmp_path=tmp_path))
    defectos = {"computo": "code_editor", "limite": "1000", "mes": "2024-01", "reprocesar": False}
    assert dag.params[esperado] == defectos[esperado]
    assert esperado in dag.doc_md  # el aviso sale en el doc_md
    assert "Avisos al leer `pipeline.yaml`" in dag.doc_md
    assert aviso in dag.doc_md


@pytest.mark.parametrize(
    "contenido", ["", "- una\n- lista\n", "computo: [sin cerrar\n", "\t\tmalo: : :"]
)
def test_un_yaml_roto_o_vacio_tampoco_rompe_el_parseo(monkeypatch, tmp_path, contenido):
    dag = _formulario(_parsear(monkeypatch, yaml_texto=contenido, tmp_path=tmp_path))
    assert dag.params["computo"] == "code_editor"
    assert dag.params["limite"] == "1000"
    assert "Avisos" in dag.doc_md


def test_un_yaml_que_no_existe_tampoco_rompe_el_parseo(monkeypatch, tmp_path):
    monkeypatch.setenv("PIPELINE_YAML", str(tmp_path / "no_existe.yaml"))
    from airflow.dag_processing.dagbag import DagBag

    dag = _formulario(DagBag(dag_folder=str(ARCHIVO_DAG)))
    assert dag.params["limite"] == "1000"
    assert "no encontré pipeline.yaml" in dag.doc_md


def test_si_pipeline_no_se_puede_importar_el_dag_igual_parsea(monkeypatch):
    """Sin el paquete `pipeline` (por ejemplo, un montaje roto) el formulario usa los defectos."""
    from framework import tasks

    def falla():
        raise ImportError("no hay pipeline")

    monkeypatch.setattr(tasks, "preparar_importaciones", falla)
    valores, avisos = tasks.defectos_del_formulario("dev")
    assert valores == tasks.DEFECTOS
    assert any("no pude leer pipeline.yaml" in a for a in avisos)


def test_el_aviso_del_yaml_tambien_va_al_log(monkeypatch, tmp_path, caplog):
    with caplog.at_level(logging.WARNING):
        _parsear(monkeypatch, yaml_texto='computo: foo\nlimite: "1000"\n', tmp_path=tmp_path)
    assert any("computo inválido" in r.getMessage() for r in caplog.records)


def test_yaml_con_todos_y_code_editor_arranca_con_1000_y_avisa(monkeypatch, tmp_path):
    texto = 'computo: code_editor\nlimite: "todos"\nmes: "2024-01"\nreprocesar: false\n'
    dag = _formulario(_parsear(monkeypatch, yaml_texto=texto, tmp_path=tmp_path))
    assert dag.params["limite"] == "1000"
    assert "todos con code_editor" in dag.doc_md


def test_un_entorno_invalido_si_es_un_error_claro(monkeypatch):
    bolsa = _parsear(monkeypatch, entorno="staging")
    assert "pipeline_taxi" not in bolsa.dags
    assert any("PIPELINE_ENTORNO inválido" in e for e in bolsa.import_errors.values())


# --- prod -------------------------------------------------------------------------------------


def test_prod_solo_ofrece_glue_y_todos_y_no_lee_el_yaml(monkeypatch, tmp_path):
    texto = 'computo: code_editor\nlimite: "100000"\nmes: "2024-07"\nreprocesar: true\n'
    dag = _formulario(_parsear(monkeypatch, entorno="prod", yaml_texto=texto, tmp_path=tmp_path))
    assert _opciones(dag, "computo") == ["glue_small", "glue_medium", "glue_large"]
    assert _opciones(dag, "limite") == ["todos"]
    assert dag.params["computo"] == "glue_medium"
    assert dag.params["limite"] == "todos"
    assert dag.params["mes"] == "2024-01"  # durante el curso: un solo mes
    assert dag.params["reprocesar"] is False
    assert "Avisos" not in dag.doc_md  # el yaml ni se mira


def test_prod_dice_prod_y_tampoco_tiene_param_de_entorno(monkeypatch):
    dag = _formulario(_parsear(monkeypatch, entorno="prod"))
    assert set(dag.params) == {"computo", "limite", "mes", "reprocesar"}
    assert "PROD ⚠" in dag.description
    assert "PROD ⚠" in dag.doc_md
    assert "prod" in dag.tags and "dev" not in dag.tags
    assert [t for t in dag.task_ids] and sorted(dag.task_ids) == sorted(
        ["correr_bronze", "correr_silver", "correr_gold", "cargar_snowflake"]
    )


def test_resetear_entorno_en_prod_solo_admite_prod(monkeypatch):
    from airflow.dag_processing.dagbag import DagBag

    monkeypatch.setenv("PIPELINE_ENTORNO", "prod")
    bolsa = DagBag(dag_folder=str(DAGS_DIR / "resetear_entorno.py"))
    assert bolsa.import_errors == {}
    dag = bolsa.dags["resetear_entorno"]
    assert dag.params["entorno"] == "prod"
    assert dag.params.get_param("entorno").schema["enum"] == ["prod"]
    assert dag.params["solo_listar"] is True
    assert "PROD ⚠" in dag.description


# --- validar_corrida: dev y prod --------------------------------------------------------------


def _params(**cambios):
    base = {"computo": "code_editor", "limite": "1000", "mes": "2024-01", "reprocesar": False}
    return {**base, **cambios}


@pytest.mark.parametrize(
    "cambios",
    [
        {},
        {"limite": "100000"},
        {"computo": "glue_small", "limite": "todos"},
        {"computo": "glue_large", "limite": "100000", "mes": "", "reprocesar": True},
    ],
)
def test_dev_acepta_las_combinaciones_validas(cambios):
    from framework.tasks import validar_corrida

    valores = validar_corrida("dev", _params(**cambios))
    assert set(valores) == {"computo", "limite", "mes", "reprocesar"}
    assert isinstance(valores["reprocesar"], bool) and isinstance(valores["limite"], str)


def test_dev_code_editor_con_todos_falla_con_mensaje_claro():
    from framework.tasks import ParametrosNoPermitidos, validar_corrida

    with pytest.raises(ParametrosNoPermitidos, match="1000 o 100000"):
        validar_corrida("dev", _params(limite="todos"))


@pytest.mark.parametrize(
    "cambios",
    [
        {"computo": "foo"},
        {"limite": "12345"},
        {"mes": "2024-13"},
        {"reprocesar": "quizas"},
        {"computo": ""},
    ],
)
def test_valores_fuera_de_las_listas_no_pasan_en_ningun_entorno(cambios):
    from framework.tasks import ParametrosNoPermitidos, validar_corrida

    for entorno in ("dev", "prod"):
        base = _params(computo="glue_medium", limite="todos")
        with pytest.raises(ParametrosNoPermitidos):
            validar_corrida(entorno, {**base, **cambios})


def test_prod_acepta_glue_con_todos():
    from framework.tasks import validar_corrida

    for computo in ("glue_small", "glue_medium", "glue_large"):
        valores = validar_corrida("prod", _params(computo=computo, limite="todos"))
        assert valores["computo"] == computo and valores["limite"] == "todos"


@pytest.mark.parametrize(
    ("computo", "limite", "texto"),
    [
        ("code_editor", "todos", "solo corre con Glue"),
        ("code_editor", "1000", "solo corre con Glue"),
        ("glue_medium", "1000", "siempre procesa todo"),
        ("glue_large", "100000", "siempre procesa todo"),
    ],
)
def test_prod_rechaza_computo_o_limite_ajenos(computo, limite, texto):
    from framework.tasks import ParametrosNoPermitidos, validar_corrida

    with pytest.raises(ParametrosNoPermitidos, match=texto):
        validar_corrida("prod", _params(computo=computo, limite=limite))


# --- las tareas -------------------------------------------------------------------------------


@pytest.fixture
def lanzadores(monkeypatch, tmp_path):
    """Reemplaza todo lo que sale de este proceso (CLI, Glue, Snowflake) y anota qué se pidió."""
    from framework import tasks

    from pipeline import correr

    anotado = {"cli": [], "correr": [], "snowflake": [], "conexiones": []}

    class Conexion:
        def __init__(self, rol):
            self.rol = rol
            self.cerrada = False

        def cursor(self):
            return self

        def execute(self, sql, *_):
            return self

        def fetchone(self):
            return (self.rol,)

        def close(self):
            self.cerrada = True

    def correr_comando(comando, env, cwd):
        anotado["cli"].append((comando, env, cwd))
        return anotado.get("codigo", 0)

    def falso(nombre):
        def _falso(**valores):
            anotado["correr"].append((nombre, valores))

        return _falso

    def cargar_snowflake(conexion=None, **valores):
        anotado["snowflake"].append((conexion, valores))

    def conexion_snowflake():
        conexion = Conexion(anotado.get("rol", "BIGDATA_DEV"))
        anotado["conexiones"].append(conexion)
        return conexion

    monkeypatch.setattr(tasks, "_correr_comando", correr_comando)
    monkeypatch.setattr(tasks, "conexion_snowflake", conexion_snowflake)
    monkeypatch.setattr(tasks, "PYTHON_DEL_REPO", Path(__file__))  # «existe»
    for nombre in ("correr_bronze", "correr_silver", "correr_gold"):
        monkeypatch.setattr(correr, nombre, falso(nombre))
    monkeypatch.setattr(correr, "cargar_snowflake", cargar_snowflake)
    return anotado


def test_code_editor_llama_al_cli_con_el_python_del_repo_y_dev_forzado(lanzadores, monkeypatch):
    from framework import tasks

    monkeypatch.setenv("PIPELINE_ENTORNO", "prod")  # aunque el proceso lo traiga, el CLI es dev
    monkeypatch.setenv("LAKE_BUCKET", "mi-bucket")
    tasks.ejecutar_paso("correr_silver", "dev", _params(limite="100000", reprocesar=True))
    ((comando, env, cwd),) = lanzadores["cli"]
    assert comando[1:] == [
        "-m",
        "pipeline.run",
        "--paso",
        "silver",
        "--computo",
        "code_editor",
        "--limite",
        "100000",
        "--mes",
        "2024-01",
        "--reprocesar",
        "true",
    ]
    assert env["PIPELINE_ENTORNO"] == "dev"
    assert env["LAKE_BUCKET"] == "mi-bucket"  # hereda todo lo demás
    assert env["PYTHONPATH"].split(":")[0].endswith("/src")
    assert cwd == tasks.REPO_ROOT
    assert lanzadores["correr"] == []


def test_code_editor_con_mes_vacio_corre_cada_mes_del_entorno(lanzadores):
    from framework import tasks

    from pipeline.herramientas.rutas import meses_del_entorno

    tasks.ejecutar_paso("correr_gold", "dev", _params(mes=""))
    meses = [c[0][c[0].index("--mes") + 1] for c in lanzadores["cli"]]
    assert meses == meses_del_entorno("dev")


def test_si_el_cli_falla_la_tarea_falla(lanzadores):
    from framework import tasks

    lanzadores["codigo"] = 2
    with pytest.raises(RuntimeError, match="código 2"):
        tasks.ejecutar_paso("correr_bronze", "dev", _params())


def test_glue_llama_directo_a_la_funcion_del_paso(lanzadores):
    from framework import tasks

    tasks.ejecutar_paso("correr_bronze", "dev", _params(computo="glue_small", limite="todos"))
    assert lanzadores["cli"] == []
    assert lanzadores["correr"] == [
        (
            "correr_bronze",
            {"computo": "glue_small", "limite": "todos", "mes": "2024-01", "reprocesar": False},
        )
    ]


def test_cada_tarea_llama_a_la_funcion_que_lleva_su_nombre(lanzadores):
    from framework import tasks

    for tarea in ("correr_bronze", "correr_silver", "correr_gold"):
        tasks.ejecutar_paso(tarea, "dev", _params(computo="glue_medium", limite="todos"))
    assert [nombre for nombre, _ in lanzadores["correr"]] == [
        "correr_bronze",
        "correr_silver",
        "correr_gold",
    ]


def test_cargar_snowflake_usa_la_conexion_de_airflow_sin_spark_ni_glue(lanzadores):
    from framework import tasks

    tasks.ejecutar_paso("cargar_snowflake", "dev", _params())  # aun con code_editor: sin CLI
    assert lanzadores["cli"] == [] and lanzadores["correr"] == []
    ((conexion, valores),) = lanzadores["snowflake"]
    assert conexion is lanzadores["conexiones"][0]
    assert conexion.cerrada is True
    assert valores["computo"] == "code_editor"


def test_cargar_snowflake_exige_el_rol_del_entorno(lanzadores):
    from framework import tasks

    from pipeline.herramientas.corrida import EntornoNoPermitido

    lanzadores["rol"] = "ACCOUNTADMIN"
    with pytest.raises(EntornoNoPermitido):
        tasks.ejecutar_paso("cargar_snowflake", "dev", _params())
    assert lanzadores["snowflake"] == []
    assert lanzadores["conexiones"][0].cerrada is True


@pytest.mark.parametrize(
    "tarea", ["correr_bronze", "correr_silver", "correr_gold", "cargar_snowflake"]
)
def test_en_prod_un_computo_ajeno_falla_antes_de_tocar_nada(lanzadores, tarea):
    from framework import tasks

    for ajeno in (_params(), _params(computo="glue_medium", limite="1000")):
        with pytest.raises(tasks.ParametrosNoPermitidos):
            tasks.ejecutar_paso(tarea, "prod", ajeno)
    assert lanzadores["cli"] == [] and lanzadores["correr"] == [] and lanzadores["snowflake"] == []
    assert lanzadores["conexiones"] == []  # ni siquiera se abrió Snowflake


def test_en_prod_glue_con_todos_si_corre(lanzadores):
    from framework import tasks

    tasks.ejecutar_paso("correr_bronze", "prod", _params(computo="glue_medium", limite="todos"))
    assert lanzadores["correr"][0][1]["computo"] == "glue_medium"
    assert lanzadores["cli"] == []


def test_sin_el_venv_del_repo_el_mensaje_dice_que_hacer(lanzadores, monkeypatch, tmp_path):
    from framework import tasks

    monkeypatch.setattr(tasks, "PYTHON_DEL_REPO", tmp_path / "no_hay" / "python")
    with pytest.raises(RuntimeError, match="make setup"):
        tasks.ejecutar_paso("correr_bronze", "dev", _params())


def test_las_constantes_del_dag_son_las_del_contrato_de_pipeline():
    from framework import tasks

    from pipeline.herramientas import corrida

    assert tasks.COMPUTOS == corrida.COMPUTOS
    assert tasks.LIMITES == corrida.LIMITES
    assert tasks.DEFECTOS == corrida.DEFECTOS
    assert tasks.COMPUTO_DE_PROD == corrida.COMPUTO_DE_PROD
    assert tasks.LIMITE_DE_PROD == corrida.LIMITE_DE_PROD
    assert set(tasks.TAREAS_DEL_PIPELINE.values()) == set(corrida.PASOS)


def test_el_perfil_small_de_glue_tiene_el_plazo_de_15_minutos():
    """profiles.yaml (que lee lanzar_en_glue) y el respaldo de glue.py dicen lo mismo."""
    import yaml

    from pipeline.herramientas.glue import PERFILES_DE_GLUE

    perfiles = yaml.safe_load((AIRFLOW_ROOT / "framework" / "profiles.yaml").read_text())[
        "profiles"
    ]
    for perfil, (workers, plazo) in PERFILES_DE_GLUE.items():
        assert perfiles[perfil]["number_of_workers"] == workers
        assert perfiles[perfil]["timeout"] == plazo
