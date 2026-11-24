"""Lógica del DAG resetear_entorno con S3, Snowflake y la tabla de control falsos.

Las funciones que de verdad borran (pipeline/herramientas/reseteo.py) se prueban aparte en
tests/test_reseteo.py. Aquí se prueba lo del DAG: validación y confirmación, que `solo_listar` no
borre nada, el orden control -> Snowflake -> S3 y que un recuento que cambia detenga el borrado.
"""

from __future__ import annotations

import pytest

CUENTA = "123456789012"


def _formulario(**cambios):
    base = {
        "entorno": "dev",
        "solo_listar": True,
        "confirmacion": "",
        "conservar_crudo": False,
    }
    return {**base, **cambios}


# --- validación y confirmación --------------------------------------------------------------------


def test_la_confirmacion_esperada_de_dev_y_de_prod():
    from framework.tasks import confirmacion_esperada

    assert confirmacion_esperada("dev") == "borrar dev"
    assert confirmacion_esperada("prod", CUENTA) == f"borrar prod {CUENTA}"
    with pytest.raises(ValueError):
        confirmacion_esperada("prod")  # sin cuenta no hay confirmación de prod


def test_solo_listar_no_pide_confirmacion():
    from framework.tasks import validar_reseteo

    valores = validar_reseteo("dev", _formulario())
    assert valores == {"entorno": "dev", "solo_listar": True, "conservar_crudo": False}


@pytest.mark.parametrize("escrito", ["", "borrar", "borrar prod", "borrar dev ahora", "dev"])
def test_una_confirmacion_mala_no_deja_borrar_en_dev(escrito):
    from framework.tasks import ParametrosNoPermitidos, validar_reseteo

    with pytest.raises(ParametrosNoPermitidos, match="no coincide"):
        validar_reseteo("dev", _formulario(solo_listar=False, confirmacion=escrito))


def test_la_confirmacion_correcta_deja_borrar_en_dev():
    from framework.tasks import validar_reseteo

    for escrito in ("borrar dev", "  borrar   dev  ", "BORRAR DEV", "«Borrar dev»"):
        valores = validar_reseteo("dev", _formulario(solo_listar=False, confirmacion=escrito))
        assert valores["solo_listar"] is False


def test_el_entorno_del_formulario_solo_puede_ser_el_de_este_airflow():
    from framework.tasks import ParametrosNoPermitidos, validar_reseteo

    with pytest.raises(ParametrosNoPermitidos, match="solo resetea su propio entorno"):
        validar_reseteo(
            "dev", _formulario(entorno="prod", solo_listar=False, confirmacion="borrar dev")
        )


def test_si_el_proceso_dice_otro_entorno_no_se_borra(monkeypatch):
    from framework.tasks import ParametrosNoPermitidos, validar_reseteo

    monkeypatch.setenv("PIPELINE_ENTORNO", "prod")
    with pytest.raises(ParametrosNoPermitidos, match="PIPELINE_ENTORNO"):
        validar_reseteo("dev", _formulario())


def test_prod_exige_borrar_prod_y_el_id_de_la_cuenta(monkeypatch):
    from framework import tasks

    monkeypatch.setenv("PIPELINE_ENTORNO", "prod")
    monkeypatch.setattr(tasks, "cuenta_aws", lambda: CUENTA)
    prod = _formulario(entorno="prod", solo_listar=False)
    for escrito in (
        "borrar prod",
        "borrar dev",
        f"borrar dev {CUENTA}",
        "borrar prod 999999999999",
        CUENTA,
    ):
        with pytest.raises(tasks.ParametrosNoPermitidos):
            tasks.validar_reseteo("prod", {**prod, "confirmacion": escrito})
    ok = tasks.validar_reseteo("prod", {**prod, "confirmacion": f"borrar prod {CUENTA}"})
    assert ok["solo_listar"] is False


def test_prod_con_solo_listar_no_necesita_confirmar_ni_pregunta_la_cuenta(monkeypatch):
    from framework import tasks

    monkeypatch.setenv("PIPELINE_ENTORNO", "prod")

    def no_debe_llamarse():
        raise AssertionError("no hacía falta preguntarle la cuenta a sts")

    monkeypatch.setattr(tasks, "cuenta_aws", no_debe_llamarse)
    valores = tasks.validar_reseteo("prod", _formulario(entorno="prod"))
    assert valores["solo_listar"] is True


# --- el flujo completo con cosas falsas -----------------------------------------------------------


class XComs:
    """El `ti` de las tareas: guarda lo que cada tarea devuelve."""

    def __init__(self):
        self.valores = {}

    def xcom_pull(self, task_ids):
        return self.valores.get(task_ids)


class Registro:
    """Anota, en orden, todo lo que el flujo hizo en S3, Snowflake y la tabla de control."""

    def __init__(self, tablas=("BIGDATA.DEV.T1", "BIGDATA.DEV.V1"), registros=7, objetos=40):
        self.eventos: list[tuple] = []
        self.tablas = list(tablas)
        self.registros = registros
        self.objetos = objetos
        self.cerradas = 0


@pytest.fixture
def mundo(monkeypatch):
    """Reemplaza reseteo, la conexión y las funciones de control por dobles que anotan."""
    from framework import tasks

    from pipeline.herramientas import control

    reg = Registro()

    class Conexion:
        def close(self):
            reg.cerradas += 1

    class ReseteoFalso:
        @staticmethod
        def esquema_del_entorno(entorno):
            return f"BIGDATA.{entorno.upper()}"

        @staticmethod
        def contar_control(entorno, conexion=None):
            reg.eventos.append(("contar_control", entorno))
            return reg.registros

        @staticmethod
        def borrar_tablas_snowflake(entorno, solo_listar=True, conexion=None):
            reg.eventos.append(("snowflake", entorno, "listar" if solo_listar else "borrar"))
            return list(reg.tablas)

        @staticmethod
        def borrar_capas_s3(entorno, solo_listar=True, conservar_crudo=False):
            reg.eventos.append(
                ("s3", entorno, "listar" if solo_listar else "borrar", conservar_crudo)
            )
            return {
                "prefijo": f"s3://lake/{entorno}/",
                "objetos": reg.objetos,
                "bytes": 1234,
                "por_capa": {"bronze": 30, "silver": 5, "gold": 5, "otros": 0},
                "conservados": 0,
                "borrados": 0 if solo_listar else reg.objetos,
            }

    monkeypatch.setattr(tasks, "_reseteo", lambda: ReseteoFalso)
    monkeypatch.setattr(tasks, "conexion_snowflake", lambda: Conexion())
    monkeypatch.setattr(
        control,
        "exigir_rol_del_entorno",
        lambda entorno, conexion=None: reg.eventos.append(("rol", entorno)),
    )

    def vaciar_control(entorno, conexion=None):
        reg.eventos.append(("vaciar_control", entorno))
        return reg.registros

    monkeypatch.setattr(control, "vaciar_control", vaciar_control)
    return reg


def _correr_todo(params, hasta=None):
    """Corre las seis tareas en orden, como el DAG, y devuelve lo que cada una devolvió."""
    from framework import tasks

    ti = XComs()
    for tarea in tasks.TAREAS_DEL_RESETEO:
        ti.valores[tarea] = tasks._cuerpo_del_reseteo(tarea, "dev", params, ti)
        if tarea == hasta:
            break
    return ti.valores


def _escrituras(reg):
    """Lo que de verdad borra: ni listar ni contar."""
    return [
        e
        for e in reg.eventos
        if e[0] == "vaciar_control" or (e[0] in ("s3", "snowflake") and e[2] == "borrar")
    ]


def test_solo_listar_cuenta_y_lista_pero_no_borra_nada(mundo, capsys):
    resultados = _correr_todo(_formulario())
    assert _escrituras(mundo) == []
    assert resultados["contar"]["control"] == 7
    assert resultados["contar"]["tablas"] == ["BIGDATA.DEV.T1", "BIGDATA.DEV.V1"]
    assert resultados["contar"]["s3_objetos"] == 40
    assert resultados["resumen"] == {"borro": False}
    assert "NO se borró nada" in capsys.readouterr().out


def test_una_confirmacion_mala_no_toca_nada(mundo):
    from framework.tasks import ParametrosNoPermitidos

    with pytest.raises(ParametrosNoPermitidos):
        _correr_todo(_formulario(solo_listar=False, confirmacion="borrar prod"), hasta="validar")
    assert mundo.eventos == []  # ni siquiera se contó


def test_borra_en_el_orden_control_snowflake_s3(mundo):
    resultados = _correr_todo(_formulario(solo_listar=False, confirmacion="borrar dev"))
    assert _escrituras(mundo) == [
        ("vaciar_control", "dev"),
        ("snowflake", "dev", "borrar"),
        ("s3", "dev", "borrar", False),
    ]
    assert resultados["vaciar_control"] == {"borrados": 7}
    assert resultados["borrar_snowflake"] == {"borradas": ["BIGDATA.DEV.T1", "BIGDATA.DEV.V1"]}
    assert resultados["borrar_s3"] == {"borrados": 40, "conservados": 0}
    assert resultados["resumen"] == {"borro": True}


def test_el_rol_del_entorno_se_exige_antes_de_vaciar_la_tabla_de_control(mundo):
    _correr_todo(_formulario(solo_listar=False, confirmacion="borrar dev"))
    nombres = [e[0] for e in mundo.eventos]
    assert nombres.index("rol") < nombres.index("vaciar_control")


def test_todo_lo_que_se_toca_es_del_entorno_dev(mundo):
    _correr_todo(_formulario(solo_listar=False, confirmacion="borrar dev"))
    assert {e[1] for e in mundo.eventos} == {"dev"}


def test_conservar_crudo_llega_a_s3(mundo):
    _correr_todo(_formulario(solo_listar=False, confirmacion="borrar dev", conservar_crudo=True))
    s3 = [e for e in mundo.eventos if e[0] == "s3"]
    assert s3 and all(e[3] is True for e in s3)


def test_si_cambia_el_recuento_de_la_tabla_de_control_no_se_borra_nada(mundo):
    from framework import tasks

    ti = XComs()
    params = _formulario(solo_listar=False, confirmacion="borrar dev")
    for tarea in ("validar", "contar"):
        ti.valores[tarea] = tasks._cuerpo_del_reseteo(tarea, "dev", params, ti)
    mundo.registros = 9  # alguien registró algo entre contar y borrar
    with pytest.raises(RuntimeError, match="me detengo"):
        tasks._cuerpo_del_reseteo("vaciar_control", "dev", params, ti)
    assert _escrituras(mundo) == []


def test_si_cambian_las_tablas_no_se_borran(mundo):
    from framework import tasks

    ti = XComs()
    params = _formulario(solo_listar=False, confirmacion="borrar dev")
    for tarea in ("validar", "contar"):
        ti.valores[tarea] = tasks._cuerpo_del_reseteo(tarea, "dev", params, ti)
    mundo.tablas.append("BIGDATA.DEV.NUEVA")
    with pytest.raises(RuntimeError, match="cambiaron"):
        tasks._cuerpo_del_reseteo("borrar_snowflake", "dev", params, ti)
    assert [e for e in mundo.eventos if e[:3] == ("snowflake", "dev", "borrar")] == []


def test_si_cambian_los_objetos_de_s3_no_se_borran(mundo):
    from framework import tasks

    ti = XComs()
    params = _formulario(solo_listar=False, confirmacion="borrar dev")
    for tarea in ("validar", "contar"):
        ti.valores[tarea] = tasks._cuerpo_del_reseteo(tarea, "dev", params, ti)
    mundo.objetos = 41
    with pytest.raises(RuntimeError, match="me detengo"):
        tasks._cuerpo_del_reseteo("borrar_s3", "dev", params, ti)
    assert [e for e in mundo.eventos if e[:3] == ("s3", "dev", "borrar")] == []


def test_sin_el_recuento_previo_las_tareas_de_borrado_se_detienen(mundo):
    from framework import tasks

    with pytest.raises(RuntimeError, match="No encontré el resultado"):
        tasks._cuerpo_del_reseteo(
            "borrar_s3", "dev", _formulario(solo_listar=False, confirmacion="borrar dev"), XComs()
        )


def test_las_conexiones_de_snowflake_se_cierran(mundo):
    _correr_todo(_formulario(solo_listar=False, confirmacion="borrar dev"))
    assert mundo.cerradas == 3  # contar, vaciar_control y borrar_snowflake abren una cada una


def test_las_tareas_del_dag_estan_en_la_tabla_de_cuerpos():
    from framework import tasks

    assert set(tasks.TAREAS_DEL_RESETEO) == set(tasks._CUERPOS_DEL_RESETEO)
    with pytest.raises(ValueError):
        tasks.tarea_del_reseteo("otra", "dev")
    with pytest.raises(ValueError):
        tasks.tarea_del_reseteo("validar", "staging")
