"""Pruebas de tus funciones de ingesta (src/pipeline/ingesta_alumno.py).

Son las mismas comprobaciones del lab de la clase 5 (huella, rutas, marcador, metadatos y regla
de la tabla de control), con dos diferencias: no usan la red (los archivos salen de tests/data)
y no tocan Snowflake (la tabla de control es una lista en memoria que imita a
consultar_watermark y registrar_watermark).

- Si una función sigue vacía, su prueba se OMITE con el aviso «PENDIENTE: pega tu función ...».
- Para probar otro módulo (por ejemplo la solución del instructor), apunta la variable de
  entorno INGESTA_ALUMNO_MODULO a su archivo .py o a su nombre importable:

      INGESTA_ALUMNO_MODULO=/ruta/a/solucion.py python -m pytest tests/test_ingesta_alumno.py
"""

from __future__ import annotations

import contextlib
import hashlib
import importlib
import importlib.util
import inspect
import json
import os
import re
import time
from io import StringIO
from pathlib import Path

import pytest

from conftest import DATA
from pipeline import bronze, io
from pipeline.watermark import MES_SIN_MES, PREFIJOS_DE_PRUEBA

MES_PRUEBA = "2099-01"  # un mes que todavía no existe
LIMITE_DE_PRUEBA = 40
FORMATO_ID_LOTE = re.compile(r"^\d{8}T\d{6}Z_[0-9a-f]{6}$")

# Parámetros de cada función, en el orden del lab: si los cambias, el DAG deja de poder llamarlas.
FIRMAS = {
    "calcular_hash_fila": ["columnas"],
    "ingestar_clima": ["mes", "reprocesar", "base_bronze", "tabla", "obtener"],
    "ingestar_zonas": ["reprocesar", "base_bronze", "tabla", "obtener"],
    "ingestar_viajes": ["mes", "reprocesar", "base_bronze", "tabla", "obtener", "limite_filas"],
}


def _cargar_modulo():
    destino = os.environ.get("INGESTA_ALUMNO_MODULO")
    if not destino:
        return importlib.import_module("pipeline.ingesta_alumno")
    if destino.endswith(".py") or os.sep in destino:
        spec = importlib.util.spec_from_file_location("ingesta_alumno_alterno", destino)
        modulo = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(modulo)
        return modulo
    return importlib.import_module(destino)


@pytest.fixture(scope="module")
def ia():
    """El módulo con tus funciones (o el que indique INGESTA_ALUMNO_MODULO)."""
    return _cargar_modulo()


def _omitir_si_pendiente(ia, *nombres):
    for nombre in nombres:
        if ia.esta_pendiente(getattr(ia, nombre)):
            pytest.skip(
                f"PENDIENTE: pega tu función {nombre} del lab en src/pipeline/ingesta_alumno.py"
            )


# --- la tabla de control: un doble en memoria --------------------------------------------------


class ControlEnMemoria:
    """Imita consultar_watermark y registrar_watermark sin conectarse a Snowflake."""

    def __init__(self):
        self.registros = []
        self.consultas = 0

    def consultar(self, tabla, capa, mes, connection_name=None):
        self.consultas += 1
        coinciden = [
            r for r in self.registros if (r["tabla"], r["capa"], r["mes"]) == (tabla, capa, mes)
        ]
        return json.dumps(coinciden, ensure_ascii=False)

    def registrar(self, fuente, capa, tabla, mes, filas, inicio, reprocesar, connection_name=None):
        self.registros.append(
            {
                "fuente": fuente,
                "capa": capa,
                "tabla": tabla,
                "mes": mes,
                "filas": int(filas),
                "inicio": inicio.isoformat(),
                "reprocesar": bool(reprocesar),
            }
        )

    def de(self, tabla, mes):
        return json.loads(self.consultar(tabla, "bronze", mes))


@pytest.fixture
def control(ia, monkeypatch):
    doble = ControlEnMemoria()
    monkeypatch.setattr(ia, "consultar_watermark", doble.consultar)
    monkeypatch.setattr(ia, "registrar_watermark", doble.registrar)
    return doble


# --- lo que siempre corre (sin Spark): el módulo importa y las firmas son las del lab ------------


def test_el_modulo_importa_y_tiene_las_cuatro_funciones(ia):
    for nombre in FIRMAS:
        assert callable(getattr(ia, nombre)), f"Falta la función {nombre} en ingesta_alumno.py"


@pytest.mark.parametrize("nombre", sorted(FIRMAS))
def test_la_firma_es_la_del_lab(ia, nombre):
    parametros = list(inspect.signature(getattr(ia, nombre)).parameters)
    assert parametros == FIRMAS[nombre], (
        f"{nombre} debe tener los parámetros {FIRMAS[nombre]} (los del lab) y tiene {parametros}: "
        "el DAG la llama con esos nombres."
    )


# --- archivos de prueba, sin red ---------------------------------------------------------------


@pytest.fixture(scope="module")
def parquet_de_viajes(tmp_path_factory, request):
    """El CSV de 100 viajes de tests/data, convertido en Parquet: hace de archivo de la fuente."""
    spark = request.getfixturevalue("spark")
    carpeta = tmp_path_factory.mktemp("viajes_parquet") / "parquet"
    viajes = (
        spark.read.option("header", True)
        .option("inferSchema", True)
        .csv(str(DATA / "fhvhv_tripdata_sample.csv"))
    )
    viajes.coalesce(1).write.mode("overwrite").parquet(str(carpeta))
    return sorted(carpeta.glob("part-*.parquet"))[0]


def _huella_en_python(ia, valores):
    """La definición de la huella con hashlib: texto, nulo -> MARCADOR_NULO, unir y SHA-256."""
    partes = []
    for valor in valores:
        partes.append(ia.MARCADOR_NULO if valor is None else str(valor))
    return hashlib.sha256(ia.SEPARADOR_HASH.join(partes).encode("utf-8")).hexdigest()


# --- ejercicio 1: la huella ---------------------------------------------------------------------


@pytest.fixture
def huella(ia, request):
    _omitir_si_pendiente(ia, "calcular_hash_fila")
    return request.getfixturevalue("spark")


def test_huella_coincide_con_la_definicion(ia, huella):
    spark = huella
    datos = [("a", "b"), ("a", None), ("a", ""), (None, "a"), ("a", None)]
    df = spark.createDataFrame(datos, "x string, y string").withColumn(
        "h", ia.calcular_hash_fila(["x", "y"])
    )
    for fila in df.collect():
        esperada = _huella_en_python(ia, [fila["x"], fila["y"]])
        assert fila["h"] == esperada, (
            f"Para la fila {(fila['x'], fila['y'])} la huella debería ser {esperada[:12]}... "
            f"y es {str(fila['h'])[:12]}..."
        )


def test_huella_distingue_nulo_vacio_y_orden(ia, huella):
    spark = huella
    datos = [("a", None), ("a", ""), (None, "a")]
    df = spark.createDataFrame(datos, "x string, y string").withColumn(
        "h", ia.calcular_hash_fila(["x", "y"])
    )
    huellas = {fila["h"] for fila in df.collect()}
    assert len(huellas) == 3, "(a, nulo), (a, '') y (nulo, a) deben dar tres huellas distintas."

    ab = spark.createDataFrame([("a", "b")], "x string, y string")
    h_xy = ab.select(ia.calcular_hash_fila(["x", "y"]).alias("h")).first()["h"]
    h_yx = ab.select(ia.calcular_hash_fila(["y", "x"]).alias("h")).first()["h"]
    assert h_xy != h_yx, "El orden de las columnas debe cambiar la huella."


def test_huella_con_numeros_e_igual_a_la_del_pipeline(ia, huella):
    spark = huella
    numeros = (
        spark.createDataFrame([(1, 2.5, "x")], "n int, d double, t string")
        .withColumn("h", ia.calcular_hash_fila(["n", "d", "t"]))
        .first()
    )
    assert numeros["h"] == _huella_en_python(ia, [1, 2.5, "x"]), (
        "Con números la huella debe ser la de «1||2.5||x»: usa cast('string') en cada columna."
    )
    ab = spark.createDataFrame([("a", "b")], "x string, y string")
    mia = ab.select(ia.calcular_hash_fila(["x", "y"]).alias("h")).first()["h"]
    pipeline = ab.select(bronze.hash_fila(["x", "y"]).alias("h")).first()["h"]
    assert mia == pipeline, "Tu huella debe ser igual a la de bronze.hash_fila del pipeline."


# --- ejercicios 2, 3 y 4: las tres ingestas -----------------------------------------------------


def _caso(ia, request, fuente):
    """Descripción de cada fuente: dónde está su archivo de prueba y qué se espera de ella."""
    _omitir_si_pendiente(ia, "calcular_hash_fila", f"ingestar_{fuente}")
    spark = request.getfixturevalue("spark")
    if fuente == "clima":
        archivo = DATA / "open_meteo_sample.json"
        dias = len(json.loads(archivo.read_text(encoding="utf-8"))["daily"]["time"])
        return dict(
            spark=spark,
            tabla="prueba_clima",
            mes=MES_PRUEBA,
            nombre=io.nombre_clima(MES_PRUEBA),
            url=bronze.url_clima(MES_PRUEBA),
            archivo=archivo,
            originales=["fecha", "lluvia_mm", "temperatura"],
            filas_con_limite=dias,
            filas_total=dias,
            limite=None,
        )
    if fuente == "zonas":
        archivo = DATA / "taxi_zone_lookup_sample.csv"
        zonas = len(archivo.read_text(encoding="utf-8").strip().splitlines()) - 1
        return dict(
            spark=spark,
            tabla="prueba_taxi_zones",
            mes=None,
            nombre=io.NOMBRE_ZONAS,
            url=bronze.URL_ZONAS,
            archivo=archivo,
            originales=["LocationID", "Borough", "Zone", "service_zone"],
            filas_con_limite=zonas,
            filas_total=zonas,
            limite=None,
        )
    archivo = request.getfixturevalue("parquet_de_viajes")
    return dict(
        spark=spark,
        tabla="prueba_fhvhv",
        mes=MES_PRUEBA,
        nombre=io.nombre_viajes(MES_PRUEBA),
        url=ia.url_viajes(MES_PRUEBA),
        archivo=archivo,
        originales=spark.read.parquet(str(archivo)).columns,
        filas_con_limite=LIMITE_DE_PRUEBA,
        filas_total=spark.read.parquet(str(archivo)).count(),
        limite=LIMITE_DE_PRUEBA,
    )


def _llamar(ia, fuente, reprocesar, base, caso, obtener, limite):
    """Llama a la función de la fuente con los mismos argumentos con que la llama el DAG."""
    if fuente == "clima":
        return ia.ingestar_clima(
            caso["mes"],
            reprocesar=reprocesar,
            base_bronze=base,
            tabla=caso["tabla"],
            obtener=obtener,
        )
    if fuente == "zonas":
        return ia.ingestar_zonas(
            reprocesar=reprocesar, base_bronze=base, tabla=caso["tabla"], obtener=obtener
        )
    return ia.ingestar_viajes(
        caso["mes"],
        reprocesar=reprocesar,
        base_bronze=base,
        tabla=caso["tabla"],
        obtener=obtener,
        limite_filas=limite,
    )


def _obtener_de_prueba(caso, descargas):
    """Reemplaza la descarga: copia el archivo pequeño de tests/data y anota qué se pidió."""

    def obtener(url_pedida, destino):
        descargas.append((url_pedida, destino))
        io.publicar(caso["archivo"], destino)

    return obtener


def _lotes_de(base, tabla, mes):
    nombres = io.listar_subcarpetas(io.dir_fuente(base, tabla, mes))
    return [n for n in nombres if n.startswith(io.PREFIJO_LOTE)]


def _id_de_lote(carpeta_lote):
    return str(carpeta_lote).rstrip("/").split("/")[-1][len(io.PREFIJO_LOTE) :]


@pytest.mark.parametrize("fuente", ["clima", "zonas", "viajes"])
def test_primera_ingesta_escribe_crudo_lote_metadatos_y_registro(
    ia, control, tmp_path, request, fuente
):
    caso = _caso(ia, request, fuente)
    spark, tabla, mes, nombre, url = (caso[k] for k in ("spark", "tabla", "mes", "nombre", "url"))
    mes_control = MES_SIN_MES if mes is None else mes
    base = str(tmp_path / "bronze")
    descargas = []

    lote = _llamar(
        ia, fuente, False, base, caso, _obtener_de_prueba(caso, descargas), caso["limite"]
    )

    assert lote is not None, "La primera llamada debe devolver la ruta del lote que escribió."
    id_lote = _id_de_lote(lote)
    assert FORMATO_ID_LOTE.match(id_lote), (
        f"El id del lote es {id_lote!r}: AAAAMMDDTHHMMSSZ_xxxxxx."
    )
    assert str(lote) == io.dir_lote(base, tabla, id_lote, mes)

    # Rutas: se descargó una vez, desde la fuente original, al crudo del lote.
    assert len(descargas) == 1
    assert descargas[0][0] == url
    crudo = io.unir(io.dir_crudo(base, tabla, mes), f"lote={id_lote}", nombre)
    assert descargas[0][1] == crudo
    assert Path(crudo).exists()
    assert (Path(lote) / io.MARCA_LOTE_COMPLETO).exists(), "Falta el marcador _LOTE_COMPLETO."

    # Columnas y metadatos.
    df = spark.read.parquet(str(lote))
    assert df.columns == caso["originales"] + bronze.COLUMNAS_METADATOS
    assert df.count() == caso["filas_con_limite"]
    metadatos = df.select("_id_lote", "_fuente", "_archivo_origen").distinct().collect()
    assert len(metadatos) == 1
    assert metadatos[0]["_id_lote"] == id_lote
    assert metadatos[0]["_fuente"] == url
    assert metadatos[0]["_archivo_origen"] == nombre
    assert dict(df.dtypes)["_fecha_ingesta"] == "timestamp"

    # La huella sale de las columnas originales, no de los metadatos.
    textos = [df[c].cast("string").alias(c) for c in caso["originales"]]
    for fila in df.select(*textos, "_hash_fila").limit(20).collect():
        valores = [fila[c] for c in caso["originales"]]
        assert fila["_hash_fila"] == _huella_en_python(ia, valores)

    # Tabla de control: un registro de bronze con las filas que quedaron escritas.
    registros = control.de(tabla, mes_control)
    assert len(registros) == 1, "Debe quedar un registro en la tabla de control."
    registro = registros[0]
    assert registro["fuente"] == url
    assert (registro["capa"], registro["tabla"], registro["mes"]) == ("bronze", tabla, mes_control)
    assert registro["filas"] == df.count()
    assert registro["reprocesar"] is False


@pytest.mark.parametrize("fuente", ["clima", "zonas", "viajes"])
def test_segunda_llamada_se_salta_y_reprocesar_crea_lote_nuevo(
    ia, control, tmp_path, request, fuente
):
    caso = _caso(ia, request, fuente)
    spark, tabla, mes, nombre = (caso[k] for k in ("spark", "tabla", "mes", "nombre"))
    mes_control = MES_SIN_MES if mes is None else mes
    base = str(tmp_path / "bronze")
    descargas = []
    obtener = _obtener_de_prueba(caso, descargas)

    lote_1 = str(_llamar(ia, fuente, False, base, caso, obtener, caso["limite"]))

    # Segunda llamada con reprocesar=False: ya hay registro, no descarga ni escribe.
    def obtener_prohibido(url_pedida, destino):
        raise AssertionError(
            "Con registro en la tabla de control y reprocesar=False no se descarga."
        )

    salida = StringIO()
    with contextlib.redirect_stdout(salida):
        resultado = _llamar(ia, fuente, False, base, caso, obtener_prohibido, caso["limite"])
    assert resultado is None, "Si ya hay registro y reprocesar es False, devuelve None."
    assert salida.getvalue().strip(), "Cuando no hace nada debe imprimir por qué."
    assert len(_lotes_de(base, tabla, mes)) == 1, "No debe escribir un lote nuevo."
    assert len(control.de(tabla, mes_control)) == 1, "No debe registrar nada."

    # Tercera llamada con reprocesar=True: lote nuevo, crudo nuevo, registro nuevo.
    # El id del lote empieza con la fecha hasta el segundo: con la tabla de control en memoria las
    # dos ingestas caerían en el mismo segundo (con Snowflake de por medio no pasa).
    time.sleep(1.1)
    lote_3 = _llamar(ia, fuente, True, base, caso, obtener, None)
    assert lote_3 is not None and str(lote_3) != lote_1
    assert len(descargas) == 2, "Reprocesar descarga otra vez."
    crudo_3 = io.unir(io.dir_crudo(base, tabla, mes), f"lote={_id_de_lote(lote_3)}", nombre)
    assert Path(crudo_3).exists()
    assert Path(lote_1).exists(), "Reprocesar no debe borrar el lote anterior."
    assert len(_lotes_de(base, tabla, mes)) == 2
    assert io.lote_mas_reciente(base, tabla, mes) == _id_de_lote(lote_3)
    assert spark.read.parquet(str(lote_3)).count() == caso["filas_total"]
    registros = control.de(tabla, mes_control)
    assert len(registros) == 2
    assert registros[-1]["reprocesar"] is True
    assert registros[-1]["filas"] == caso["filas_total"]


@pytest.mark.parametrize("fuente", ["clima", "zonas", "viajes"])
def test_un_fallo_a_la_mitad_no_deja_registro_y_el_reintento_ingesta(
    ia, control, tmp_path, request, fuente
):
    """Lo que hace el DAG al reintentar: el registro va al final, así que un fallo no lo deja."""
    caso = _caso(ia, request, fuente)
    tabla, mes = caso["tabla"], caso["mes"]
    mes_control = MES_SIN_MES if mes is None else mes
    base = str(tmp_path / "bronze")

    def obtener_que_falla(url_pedida, destino):
        raise ConnectionError("la fuente no respondió")

    with pytest.raises(ConnectionError):
        _llamar(ia, fuente, False, base, caso, obtener_que_falla, caso["limite"])
    assert control.de(tabla, mes_control) == [], "Una ingesta que falló no debe registrarse."

    descargas = []
    lote = _llamar(
        ia, fuente, False, base, caso, _obtener_de_prueba(caso, descargas), caso["limite"]
    )
    assert lote is not None, "El reintento debe ingestar, porque no había registro."
    assert len(control.de(tabla, mes_control)) == 1
    assert len(_lotes_de(base, tabla, mes)) == 1


def test_viajes_rechaza_limite_filas_con_la_tabla_real(ia, control, tmp_path, request):
    """La guarda del lab: un lote recortado nunca se registra como si fuera el mes completo."""
    _caso(ia, request, "viajes")

    def obtener_prohibido(url_pedida, destino):
        raise AssertionError("La guarda debe rechazar limite_filas antes de descargar.")

    assert not io.VIAJES.startswith(PREFIJOS_DE_PRUEBA)
    with pytest.raises(ValueError):
        ia.ingestar_viajes(
            MES_PRUEBA,
            base_bronze=str(tmp_path / "bronze"),
            tabla=io.VIAJES,
            obtener=obtener_prohibido,
            limite_filas=10,
        )
    assert control.registros == []
