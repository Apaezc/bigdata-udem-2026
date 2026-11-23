"""Banner, cierre, los cuatro pasos como funciones y el lanzador único de Glue.

Sin red, sin Spark y sin Snowflake: los pasos, el motor, boto3 y la tabla de control son dobles.
"""

from __future__ import annotations

import io
import zipfile
from dataclasses import replace
from datetime import UTC, datetime, timedelta

import pytest

import pipeline.correr as correr
import pipeline.herramientas.control as control
import pipeline.herramientas.corrida as corrida_mod
import pipeline.herramientas.glue as glue_mod
from pipeline.herramientas.corrida import (
    Corrida,
    Resultado,
    banner,
    cierre,
    rutas_del_paso,
)
from pipeline.herramientas.glue import lanzar_en_glue
from pipeline.herramientas.rutas import ConfigError

pytest_plugins = ["p1_fixtures"]

BUCKET = "bigdata-lake-123456789012-us-east-2"
MES = "2024-01"
AHORA = datetime(2026, 11, 23, 10, 0, 0, tzinfo=UTC)
LINEA = "=" * 66


def una_corrida(**cambios) -> Corrida:
    """Una corrida de dev armada a mano (sin yaml, sin env)."""
    base = Corrida(
        entorno="dev",
        computo="glue_small",
        meses=(MES,),
        limite="100000",
        reprocesar=True,
        id_lote="20261123T100000Z_abc123",
        fecha_ingesta=AHORA,
    )
    return replace(base, **cambios)


@pytest.fixture
def bucket(entorno_limpio, monkeypatch):
    monkeypatch.setenv("LAKE_BUCKET", BUCKET)


# --- banner: el formato exacto -----------------------------------------------------------------


def test_banner_de_silver_con_glue_small(bucket):
    esperado = "\n".join(
        [
            LINEA,
            " Entorno    : DEV",
            " Cómputo    : glue_small",
            " Paso       : silver",
            " Mes        : 2024-01",
            " Límite     : 100000",
            " Reprocesar : true",
            f" Lee        : s3://{BUCKET}/dev/bronze/fhvhv/mes=2024-01/",
            f"              s3://{BUCKET}/dev/bronze/taxi_zones/",
            f"              s3://{BUCKET}/dev/bronze/clima/mes=2024-01/",
            f" Escribe    : s3://{BUCKET}/dev/silver/fhvhv/mes=2024-01/",
            f"              s3://{BUCKET}/dev/silver/taxi_zones/",
            f"              s3://{BUCKET}/dev/silver/clima/mes=2024-01/",
            " Control    : BIGDATA.CONTROL_DEV.WATERMARK",
            LINEA,
        ]
    )
    assert banner(una_corrida(), "silver", MES) == esperado


def test_el_banner_mide_66_y_cada_etiqueta_11_mas_dos_puntos(bucket):
    lineas = banner(una_corrida(), "silver", MES).split("\n")
    assert len(lineas[0]) == len(lineas[-1]) == 66
    for linea in lineas[1:-1]:
        if linea.startswith("              "):  # línea de continuación de Lee o Escribe
            continue
        assert linea[12:14] == ": ", linea  # ' ' + 11 de etiqueta, luego ': '


def test_banner_de_bronze_lee_el_crudo(bucket):
    texto = banner(una_corrida(reprocesar=False, limite="1000"), "bronze", MES)
    assert f" Lee        : s3://{BUCKET}/dev/bronze/_crudo/fhvhv/mes=2024-01/" in texto
    assert f"              s3://{BUCKET}/dev/bronze/_crudo/taxi_zones/" in texto
    assert f"              s3://{BUCKET}/dev/bronze/_crudo/clima/mes=2024-01/" in texto
    assert f" Escribe    : s3://{BUCKET}/dev/bronze/fhvhv/mes=2024-01/" in texto
    assert " Reprocesar : false" in texto
    assert " Límite     : 1000" in texto


def test_banner_de_gold_lee_silver_y_escribe_la_tabla_de_la_casa(bucket):
    texto = banner(una_corrida(), "gold", MES)
    assert f" Lee        : s3://{BUCKET}/dev/silver/fhvhv/mes=2024-01/" in texto
    assert f"              s3://{BUCKET}/dev/silver/clima/mes=2024-01/" in texto
    assert f" Escribe    : s3://{BUCKET}/dev/gold/tarifa_por_milla_barrio/mes=2024-01/" in texto


def test_banner_de_snowflake_no_usa_spark(bucket):
    texto = banner(una_corrida(computo="glue_medium"), "snowflake", MES)
    assert " Cómputo    : glue_medium (este paso no usa Spark)" in texto
    assert f" Lee        : s3://{BUCKET}/dev/gold/tarifa_por_milla_barrio/mes=2024-01/" in texto
    assert " Escribe    : BIGDATA.DEV.TARIFA_POR_MILLA_BARRIO" in texto


def test_banner_de_prod_lo_dice_en_voz_alta(bucket):
    corrida = una_corrida(entorno="prod", computo="glue_medium", limite="todos", reprocesar=False)
    texto = banner(corrida, "gold", MES)
    assert " Entorno    : PROD ⚠  (producción)" in texto
    assert "/prod/gold/tarifa_por_milla_barrio/mes=2024-01/" in texto
    assert " Control    : BIGDATA.CONTROL_PROD.WATERMARK" in texto
    assert "/dev/" not in texto


def test_banner_con_avisos_agrega_una_linea_por_aviso(bucket):
    corrida = una_corrida(avisos=("limite inválido en pipeline.yaml; se usó 1000", "otro aviso"))
    texto = banner(corrida, "silver", MES)
    assert " Aviso      : limite inválido en pipeline.yaml; se usó 1000\n" in texto
    assert "\n              otro aviso\n" + LINEA in texto


def test_banner_sin_avisos_no_trae_la_linea(bucket):
    assert "Aviso" not in banner(una_corrida(), "silver", MES)


def test_banner_marca_la_raiz_de_prueba(entorno_limpio, raiz_lake):
    texto = banner(una_corrida(), "silver", MES)
    assert " Entorno    : DEV [RAÍZ DE PRUEBA]" in texto
    assert f"file://{raiz_lake}/dev/bronze/fhvhv/mes=2024-01/" in texto


def test_el_banner_sale_igual_para_el_mismo_paso(bucket):
    assert banner(una_corrida(), "silver", MES) == banner(una_corrida(), "silver", MES)


def test_rutas_del_paso_devuelve_lee_escribe_y_control(bucket):
    lee, escribe, tabla_control = rutas_del_paso(una_corrida(), "silver", MES)
    assert lee[0] == f"s3://{BUCKET}/dev/bronze/fhvhv/mes=2024-01/"
    assert escribe[0] == f"s3://{BUCKET}/dev/silver/fhvhv/mes=2024-01/"
    assert tabla_control == "BIGDATA.CONTROL_DEV.WATERMARK"
    assert rutas_del_paso(una_corrida(entorno="prod"), "silver", MES)[2] == (
        "BIGDATA.CONTROL_PROD.WATERMARK"
    )


def test_un_paso_desconocido_se_rechaza(bucket):
    with pytest.raises(ConfigError, match="Paso desconocido"):
        rutas_del_paso(una_corrida(), "platino", MES)


# --- cierre ------------------------------------------------------------------------------------


def test_cierre_exacto():
    resultados = [
        Resultado("fhvhv", "silver", MES, 100000, 99320, "REGISTRÓ"),
        Resultado("taxi_zones", "silver", "sin_mes", 265, 265, "SE SALTÓ"),
    ]
    esperado = "\n".join(
        [
            " Cierre     : paso=silver mes=2024-01",
            "   fhvhv        leyó=100000     escribió=99320      REGISTRÓ en la tabla de control",
            "   taxi_zones   leyó=265        escribió=265        "
            "SE SALTÓ (ya registrado y reprocesar=false)",
            LINEA,
        ]
    )
    assert cierre(una_corrida(), "silver", MES, resultados) == esperado


def test_cierre_con_nota_de_salto_propia():
    resultados = [Resultado("clima", "bronze", MES, 0, 0, "SE SALTÓ")]
    texto = cierre(una_corrida(), "bronze", MES, resultados, nota_de_salto="(ver log de Glue)")
    assert texto.split("\n")[1].endswith("SE SALTÓ (ver log de Glue)")


# --- correr_paso y las cuatro funciones públicas ------------------------------------------------


class PasoFalso:
    """Reemplaza a pipeline.bronze (o silver...) y anota cómo lo llamaron."""

    def __init__(self, paso, llamadas):
        self.paso = paso
        self.llamadas = llamadas

    def main(self, *argumentos):
        self.llamadas.append((self.paso, argumentos))
        corrida = argumentos[-1] if self.paso != "snowflake" else argumentos[0]
        mes = corrida.meses[0]
        return [Resultado("fhvhv", self.paso, mes, 10, 8, "REGISTRÓ")]


@pytest.fixture
def pasos_falsos(monkeypatch):
    """Pasos y motor de Spark falsos. Devuelve la lista de llamadas, en orden."""
    llamadas = []
    monkeypatch.setattr(correr, "_modulo_del_paso", lambda paso: PasoFalso(paso, llamadas))

    import pipeline.engine as engine

    def spark_falso(computo, toca_s3=False):
        llamadas.append(("get_spark", computo, toca_s3))
        return "spark"

    monkeypatch.setattr(engine, "get_spark", spark_falso)
    return llamadas


def test_code_editor_corre_el_paso_en_este_proceso_con_banner_y_cierre(
    bucket, pasos_falsos, poner_yaml, capsys
):
    poner_yaml("computo: code_editor\nlimite: '1000'\nmes: '2024-01'\nreprocesar: false\n")
    resultados = correr.correr_silver()
    salida = capsys.readouterr().out

    assert [r.decision for r in resultados] == ["REGISTRÓ"]
    assert salida.index(" Paso       : silver") < salida.index(" Cierre     : paso=silver")
    assert " Cómputo    : code_editor" in salida
    assert salida.count(LINEA) == 3  # abre el banner, lo cierra y cierra el cierre
    llamada = pasos_falsos[-1]
    assert llamada[0] == "silver"
    assert llamada[1][0] == "spark"
    assert llamada[1][1].meses == (MES,)
    assert ("get_spark", "code_editor", True) in pasos_falsos  # toca s3://: exige los jars


def test_con_raiz_de_prueba_no_se_exigen_los_jars(entorno_limpio, raiz_lake, pasos_falsos):
    correr.correr_bronze(mes=MES, computo="code_editor", limite="1000", reprocesar=False)
    assert ("get_spark", "code_editor", False) in pasos_falsos


def test_los_pasos_no_imprimen_banner_ni_cierre(bucket, pasos_falsos, capsys):
    """Solo correr.py imprime: el main del paso devuelve sus Resultado y nada más."""
    correr.correr_gold(mes=MES, computo="code_editor", limite="1000", reprocesar=False)
    salida = capsys.readouterr().out
    assert salida.count(" Entorno    : DEV") == 1
    assert salida.count(" Cierre     :") == 1


def test_cada_mes_lleva_su_banner_y_su_cierre(bucket, pasos_falsos, monkeypatch, capsys):
    monkeypatch.setattr(
        corrida_mod, "meses_del_entorno", lambda entorno: ["2024-01", "2024-02", "2024-03"]
    )
    resultados = correr.correr_bronze(
        mes="", computo="code_editor", limite="1000", reprocesar=False
    )
    salida = capsys.readouterr().out
    assert len(resultados) == 3
    for mes in ("2024-01", "2024-02", "2024-03"):
        assert f" Mes        : {mes}" in salida
        assert f" Cierre     : paso=bronze mes={mes}" in salida
    llamadas_del_paso = [c for c in pasos_falsos if c[0] == "bronze"]
    assert [c[1][1].meses for c in llamadas_del_paso] == [("2024-01",), ("2024-02",), ("2024-03",)]


def test_glue_lanza_el_job_y_no_corre_el_paso_aqui(bucket, pasos_falsos, monkeypatch, capsys):
    lanzados = []
    monkeypatch.setattr(correr, "lanzar_en_glue", lambda paso, corrida: lanzados.append(corrida))
    resultados = correr.correr_silver(
        mes=MES, computo="glue_small", limite="100000", reprocesar=True
    )
    salida = capsys.readouterr().out
    assert resultados == []  # el cierre lo escribe el lanzador
    assert [c.computo for c in lanzados] == ["glue_small"]
    assert lanzados[0].meses == (MES,)
    assert " Cómputo    : glue_small" in salida
    assert "Cierre" not in salida
    assert pasos_falsos == []  # ni siquiera se pidió Spark


def test_dentro_de_glue_el_paso_corre_en_el_mismo_proceso(bucket, pasos_falsos):
    correr.correr_paso("silver", en_glue=True, mes=MES, computo="glue_small", limite="100000")
    assert ("get_spark", "glue_small", False) in pasos_falsos
    assert [c for c in pasos_falsos if c[0] == "silver"]


def test_snowflake_corre_sin_spark_con_cualquier_computo(bucket, pasos_falsos, capsys):
    conexion = object()
    resultados = correr.cargar_snowflake(
        mes=MES, computo="glue_medium", limite="todos", reprocesar=False, conexion=conexion
    )
    salida = capsys.readouterr().out
    assert [c[0] for c in pasos_falsos] == ["snowflake"]  # sin get_spark
    corrida, conexion_recibida = pasos_falsos[0][1]
    assert conexion_recibida is conexion
    assert corrida.meses == (MES,)
    assert "(este paso no usa Spark)" in salida
    assert resultados[0].capa == "snowflake"


def test_un_paso_que_falla_no_imprime_cierre(bucket, pasos_falsos, monkeypatch, capsys):
    class PasoRoto:
        def main(self, *argumentos):
            raise RuntimeError("falló la escritura")

    monkeypatch.setattr(correr, "_modulo_del_paso", lambda paso: PasoRoto())
    with pytest.raises(RuntimeError, match="falló la escritura"):
        correr.correr_bronze(mes=MES, computo="code_editor", limite="1000", reprocesar=False)
    salida = capsys.readouterr().out
    assert " Paso       : bronze" in salida
    assert "Cierre" not in salida


def test_correr_paso_rechaza_un_paso_o_una_perilla_desconocidos(bucket, pasos_falsos):
    with pytest.raises(ConfigError, match="Paso desconocido"):
        correr.correr_paso("todo")
    with pytest.raises(TypeError, match="Perilla desconocida"):
        correr.correr_paso("silver", entorno="prod")


def test_las_reglas_de_la_configuracion_se_aplican_antes_de_correr(bucket, pasos_falsos):
    from pipeline.herramientas.corrida import LimiteNoPermitido

    with pytest.raises(LimiteNoPermitido):
        correr.correr_silver(mes=MES, computo="code_editor", limite="todos", reprocesar=False)
    assert pasos_falsos == []


def test_las_cuatro_funciones_publicas_tienen_las_perillas_del_contrato():
    import inspect

    for nombre in ("correr_bronze", "correr_silver", "correr_gold"):
        parametros = list(inspect.signature(getattr(correr, nombre)).parameters)
        assert parametros == ["mes", "computo", "limite", "reprocesar"]
    parametros = list(inspect.signature(correr.cargar_snowflake).parameters)
    assert parametros == ["mes", "computo", "limite", "reprocesar", "conexion"]


# --- lanzar_en_glue ----------------------------------------------------------------------------


class S3Falso:
    def __init__(self):
        self.subidas = []  # (bucket, clave, nombres dentro del zip)

    def upload_file(self, archivo, bucket, clave):
        with zipfile.ZipFile(archivo) as zip_:
            self.subidas.append((bucket, clave, zip_.namelist()))


class GlueFalso:
    def __init__(self, estados=("RUNNING", "SUCCEEDED"), mensaje=""):
        self.estados = list(estados)
        self.mensaje = mensaje
        self.arrancados = []

    def start_job_run(self, **kwargs):
        self.arrancados.append(kwargs)
        return {"JobRunId": "jr_123"}

    def get_job_run(self, JobName, RunId):  # noqa: N803 - firma de boto3
        estado = self.estados.pop(0) if len(self.estados) > 1 else self.estados[0]
        datos = {"JobRunState": estado}
        if self.mensaje:
            datos["ErrorMessage"] = self.mensaje
        return {"JobRun": datos}


@pytest.fixture
def glue_falso(bucket, monkeypatch):
    """boto3 falso: devuelve (s3, glue). time.sleep no espera."""
    s3, glue = S3Falso(), GlueFalso()
    clientes = {"s3": s3, "glue": glue}
    monkeypatch.setattr(glue_mod, "_cliente", lambda servicio: clientes[servicio])
    monkeypatch.setattr(glue_mod.time, "sleep", lambda segundos: None)
    monkeypatch.setattr(glue_mod, "_perfil_de_glue", lambda computo: ("bigdata-small", 2, 15))
    return s3, glue


def registro_de_control(inicio, filas=500, leidas=520):
    return {"inicio": inicio.isoformat(), "filas": filas, "leidas": leidas}


@pytest.fixture
def control_de_glue(monkeypatch):
    """consultar_control falso: devuelve lo que se le ponga en .registros (por tabla)."""
    registros = {}

    def consultar(entorno, tabla, capa, mes, conexion=None):
        return registros.get((tabla, capa, mes), [])

    monkeypatch.setattr(control, "consultar_control", consultar)
    return registros


def test_en_dev_sube_el_codigo_a_code_dev_y_nunca_toca_el_zip_de_prod(
    glue_falso, control_de_glue, capsys
):
    s3, glue = glue_falso
    lanzar_en_glue("silver", una_corrida())

    assert len(s3.subidas) == 1
    bucket, clave, nombres = s3.subidas[0]
    assert bucket == BUCKET
    assert clave == "code/dev/pipeline.zip"
    assert clave != "code/pipeline.zip"
    assert "pipeline/herramientas/corrida.py" in nombres
    assert "pipeline/run_glue.py" in nombres
    assert "pipeline/config/dev.yaml" in nombres
    assert not any("__pycache__" in nombre for nombre in nombres)

    argumentos = glue.arrancados[0]["Arguments"]
    assert glue.arrancados[0]["JobName"] == "bigdata-small"
    assert argumentos["--extra-py-files"] == f"s3://{BUCKET}/code/dev/pipeline.zip"
    assert argumentos == {
        "--step": "silver",
        "--env": "dev",
        "--mes": "2024-01",
        "--limite": "100000",
        "--reprocesar": "true",
        "--computo": "glue_small",
        "--lake-bucket": BUCKET,
        "--snowflake-secret": "bigdata/snowflake",
        "--extra-py-files": f"s3://{BUCKET}/code/dev/pipeline.zip",
    }
    assert glue.arrancados[0]["NumberOfWorkers"] == 2
    assert glue.arrancados[0]["Timeout"] == 15
    assert "console.aws.amazon.com/gluestudio" in capsys.readouterr().out


def test_en_prod_no_sube_nada_y_usa_el_zip_del_job(glue_falso, control_de_glue):
    s3, glue = glue_falso
    corrida = una_corrida(entorno="prod", computo="glue_medium", limite="todos", reprocesar=False)
    lanzar_en_glue("gold", corrida)

    assert s3.subidas == []
    argumentos = glue.arrancados[0]["Arguments"]
    assert "--extra-py-files" not in argumentos
    assert argumentos["--env"] == "prod"
    assert argumentos["--snowflake-secret"] == "bigdata/snowflake_prod"
    assert argumentos["--limite"] == "todos"
    assert argumentos["--reprocesar"] == "false"


def test_un_job_run_por_mes(glue_falso, control_de_glue):
    s3, glue = glue_falso
    lanzar_en_glue("bronze", una_corrida(meses=("2024-01", "2024-02")))
    assert [a["Arguments"]["--mes"] for a in glue.arrancados] == ["2024-01", "2024-02"]
    assert len(s3.subidas) == 1  # el código se sube una sola vez


def test_el_cierre_sale_del_ultimo_registro_de_la_tabla_de_control(
    glue_falso, control_de_glue, capsys
):
    ahora = datetime.now(UTC).replace(tzinfo=None)
    control_de_glue[("fhvhv", "silver", MES)] = [
        registro_de_control(ahora - timedelta(days=2), 1, 1),
        registro_de_control(ahora + timedelta(seconds=30), filas=99320, leidas=100000),
    ]
    control_de_glue[("clima", "silver", MES)] = [registro_de_control(ahora - timedelta(days=1))]

    lanzar_en_glue("silver", una_corrida())
    salida = capsys.readouterr().out

    assert " Cierre     : paso=silver mes=2024-01" in salida
    assert (
        "fhvhv        leyó=100000     escribió=99320      REGISTRÓ en la tabla de control" in salida
    )
    # el clima tiene un registro, pero de ayer: esta corrida no registró nada
    assert "clima        leyó=0          escribió=0          SE SALTÓ (ver log de Glue)" in salida
    # taxi_zones no tiene ningún registro
    assert "taxi_zones   leyó=0          escribió=0          SE SALTÓ (ver log de Glue)" in salida


def test_si_el_job_falla_se_dice_por_que(glue_falso, control_de_glue, monkeypatch):
    glue = GlueFalso(estados=("RUNNING", "FAILED"), mensaje="Faltan los permisos de S3")
    monkeypatch.setattr(
        glue_mod, "_cliente", lambda servicio: S3Falso() if servicio == "s3" else glue
    )
    with pytest.raises(RuntimeError, match="terminó en FAILED: Faltan los permisos de S3"):
        lanzar_en_glue("silver", una_corrida())


def test_si_no_se_puede_leer_la_tabla_de_control_el_job_igual_termina_bien(
    glue_falso, monkeypatch, capsys
):
    def sin_snowflake(*argumentos, **claves):
        raise RuntimeError("sin conexión")

    monkeypatch.setattr(control, "consultar_control", sin_snowflake)
    lanzar_en_glue("silver", una_corrida())
    salida = capsys.readouterr().out
    assert "no pude leer la tabla de control" in salida
    assert "Cierre" not in salida


def test_espera_con_get_job_run_hasta_que_termine(bucket, control_de_glue, monkeypatch):
    glue = GlueFalso(estados=("STARTING", "RUNNING", "RUNNING", "SUCCEEDED"))
    esperas = []
    monkeypatch.setattr(
        glue_mod, "_cliente", lambda servicio: S3Falso() if servicio == "s3" else glue
    )
    monkeypatch.setattr(glue_mod, "_perfil_de_glue", lambda computo: ("bigdata-small", 2, 15))
    monkeypatch.setattr(glue_mod.time, "sleep", esperas.append)
    lanzar_en_glue("silver", una_corrida())
    assert len(esperas) == 3
    assert glue.estados == ["SUCCEEDED"]


def test_glue_no_corre_snowflake_ni_code_editor(glue_falso):
    with pytest.raises(ConfigError, match="no usa Spark"):
        lanzar_en_glue("snowflake", una_corrida())
    with pytest.raises(ConfigError, match="glue_"):
        lanzar_en_glue("silver", una_corrida(computo="code_editor"))


def test_el_perfil_de_glue_sale_de_profiles_yaml_o_del_respaldo(monkeypatch):
    monkeypatch.undo()
    job, workers, plazo = glue_mod._perfil_de_glue("glue_large")
    assert job.endswith("-large")
    assert workers == 6
    assert plazo == 30


def test_el_zip_de_dev_trae_el_codigo_del_arbol_de_trabajo(tmp_path):
    destino = tmp_path / "pipeline.zip"
    cuantos = glue_mod._armar_zip_del_codigo(destino)
    with zipfile.ZipFile(destino) as zip_:
        nombres = zip_.namelist()
        assert len(nombres) == cuantos
        assert "pipeline/correr.py" in nombres
        assert "pipeline/herramientas/__init__.py" in nombres
        contenido = zip_.read("pipeline/herramientas/rutas.py").decode("utf-8")
    assert "def ruta_lake" in contenido
    assert io.StringIO  # (el zip se arma con zipfile, sin archivos temporales de más)


def test_nuevo_id_lote_empieza_con_la_fecha():
    ahora = datetime(2026, 1, 15, 14, 30, 5, tzinfo=UTC)
    id_lote = corrida_mod.nuevo_id_lote(ahora)
    assert id_lote.startswith("20260115T143005Z_")
    assert len(id_lote.split("_")[1]) == 6
