"""Los pasos bronze, silver, gold y snowflake de punta a punta, con la muestra de tests/data.

Spark local, lake en un tmp_path (PIPELINE_RAIZ_LAKE=file://...), tabla de control en memoria y
Athena/Snowflake falsos: ni red ni nube. Estas pruebas valen con las funciones que traen los .py
(con sus problemas a propósito) y también cuando se pasan las del equipo ya resueltas: lo que
cambia es lo que esperan, y cada prueba lo dice.

Hay dos estados que importan (hueco.esta_pendiente mira la marca # PENDIENTE(equipo)):
  - agregar_metadatos pendiente: bronze no agrega metadatos.
  - deduplicar pendiente: silver espeja bronze y al reprocesar se multiplica.
"""

from __future__ import annotations

import importlib.util
import os
import subprocess
import sys
from pathlib import Path

import pytest

from hueco import MES, esta_pendiente
from pipeline import bronze, silver
from pipeline.gold import COLUMNAS_TARIFA_POR_MILLA
from pipeline.herramientas.capas import COLUMNAS_METADATOS
from pipeline.herramientas.equipo import (
    probar_mis_funciones,
    usar_mis_funciones,
)
from pipeline.herramientas.rutas import TABLA_CLIMA, TABLA_VIAJES, TABLA_ZONAS

pytest_plugins = ["p1_fixtures", "p4_fixtures"]

# La muestra: 100 viajes (90 válidos), 12 zonas y 31 días de clima.
VIAJES_CRUDOS = 100
VIAJES_VALIDOS = 90
ZONAS = 12
DIAS_DE_CLIMA = 31


def _decisiones(resultados) -> list[str]:
    return [r.decision for r in resultados]


def _viajes_de_gold(lake) -> int:
    filas = lake.tabla("gold", "tarifa_por_milla_barrio").agg({"viajes": "sum"}).first()
    return filas[0]


def _viajes_con_zona_conocida(lake) -> tuple[int, int]:
    """(viajes cuya zona está en el lookup, viajes cuya zona no está) en silver de la muestra."""
    viajes = lake.tabla("silver", TABLA_VIAJES)
    zonas = lake.tabla("silver", TABLA_ZONAS).select("LocationID").distinct()
    conocidos = viajes.join(zonas, viajes.pu_location_id == zonas.LocationID).count()
    return conocidos, viajes.count() - conocidos


# --- el pipeline corre con las funciones de la casa ---------------------------------------------


def test_pipeline_corre_con_los_huecos_vacios(lake):
    """bronze -> silver -> gold -> snowflake corren con lo que traen los .py y dejan registro."""
    r_bronze = lake.bronze()
    assert [(r.tabla, r.decision) for r in r_bronze] == [
        (TABLA_VIAJES, "REGISTRÓ"),
        (TABLA_ZONAS, "REGISTRÓ"),
        (TABLA_CLIMA, "REGISTRÓ"),
    ]
    assert [r.leidas for r in r_bronze] == [VIAJES_CRUDOS, ZONAS, DIAS_DE_CLIMA]

    r_silver = lake.silver()
    assert _decisiones(r_silver) == ["REGISTRÓ"] * 3
    por_tabla = {r.tabla: r for r in r_silver}
    assert por_tabla[TABLA_VIAJES].leidas == VIAJES_CRUDOS
    assert por_tabla[TABLA_VIAJES].escritas == VIAJES_VALIDOS  # la limpieza descarta los outliers
    assert por_tabla[TABLA_ZONAS].escritas == ZONAS
    assert por_tabla[TABLA_CLIMA].escritas == DIAS_DE_CLIMA

    r_gold = lake.gold()
    assert _decisiones(r_gold) == ["REGISTRÓ"]
    assert r_gold[0].tabla == "tarifa_por_milla_barrio"
    assert lake.tabla("gold", "tarifa_por_milla_barrio").columns == COLUMNAS_TARIFA_POR_MILLA
    assert _viajes_de_gold(lake) == VIAJES_VALIDOS

    r_carga = lake.carga()
    assert _decisiones(r_carga) == ["REGISTRÓ"]
    assert [llamada[0] for llamada in lake.llamadas_a_snowflake] == ["athena", "cargar"]

    # La tabla de control quedó con un registro por capa, tabla y mes.
    registrados = {(r["capa"], r["tabla"], r["mes"]) for r in lake.control.registros}
    assert registrados == {
        ("bronze", "fhvhv", MES),
        ("bronze", "taxi_zones", "sin_mes"),
        ("bronze", "clima", MES),
        ("silver", "fhvhv", MES),
        ("silver", "taxi_zones", "sin_mes"),
        ("silver", "clima", MES),
        ("gold", "tarifa_por_milla_barrio", MES),
        ("snowflake", "tarifa_por_milla_barrio", MES),
    }


def test_bronze_agrega_metadatos_solo_si_el_equipo_los_escribio(lake):
    """Con agregar_metadatos pendiente, bronze guarda las columnas originales y nada más."""
    lake.bronze()
    columnas = lake.tabla("bronze", TABLA_ZONAS).columns
    if esta_pendiente(bronze.agregar_metadatos):
        assert columnas == ["LocationID", "Borough", "Zone", "service_zone"]
    else:
        assert columnas == ["LocationID", "Borough", "Zone", "service_zone", *COLUMNAS_METADATOS]


def test_los_pasos_no_imprimen_banner_ni_cierre(lake, capsys):
    """Solo correr.py imprime el banner y el cierre: los main de los pasos devuelven Resultado."""
    lake.bronze()
    lake.silver()
    lake.gold()
    salida = capsys.readouterr().out
    assert " Entorno    :" not in salida
    assert " Cierre     :" not in salida


# --- la puerta: sin reprocesar se salta; con reprocesar, otro lote ------------------------------


def test_segunda_corrida_sin_reprocesar_se_salta_en_todos_los_pasos(lake):
    lake.bronze()
    lake.silver()
    lake.gold()
    lake.carga()
    registros_antes = len(lake.control.registros)

    assert _decisiones(lake.bronze()) == ["SE SALTÓ"] * 3
    assert _decisiones(lake.silver()) == ["SE SALTÓ"] * 3
    assert _decisiones(lake.gold()) == ["SE SALTÓ"]
    assert _decisiones(lake.carga()) == ["SE SALTÓ"]

    assert len(lake.control.registros) == registros_antes  # saltar no registra nada
    assert len(lake.lotes_de_bronze(TABLA_VIAJES)) == 1  # y no escribió un lote nuevo


def test_al_saltarse_el_resultado_trae_las_cifras_del_ultimo_registro(lake):
    lake.bronze()
    segunda = {r.tabla: r for r in lake.bronze()}
    assert segunda[TABLA_VIAJES].leidas == VIAJES_CRUDOS
    assert segunda[TABLA_VIAJES].escritas == VIAJES_CRUDOS
    assert segunda[TABLA_ZONAS].escritas == ZONAS


def test_reprocesar_agrega_un_lote_nuevo_de_bronze_y_no_borra_el_anterior(lake):
    lake.bronze()
    lake.bronze(reprocesar=True)
    assert len(lake.lotes_de_bronze(TABLA_VIAJES)) == 2
    assert len(lake.lotes_de_bronze(TABLA_CLIMA)) == 2
    assert len(lake.lotes_de_bronze(TABLA_ZONAS)) == 2
    assert lake.tabla("bronze", TABLA_VIAJES).count() == 2 * VIAJES_CRUDOS


# --- el problema de la clase: al reprocesar, silver y gold se multiplican -----------------------


def test_reproceso_con_hueco_vacio_duplica_silver(lake):
    """Con deduplicar pendiente, cada reproceso suma una copia a cada tabla de silver.

    gold junta viajes, zonas y clima con enriquecer: con n copias de cada tabla, un viaje de zona
    conocida aparece n · n · n veces (×8 con dos copias, ×27 con tres: viaje · zona · clima) y uno
    de zona desconocida, que no cruza con ninguna zona, n · n veces (viaje · clima).
    Con deduplicar hecho (y metadatos), nada se multiplica.
    """
    if esta_pendiente(silver.deduplicar):
        espera_duplicados = True
    elif esta_pendiente(bronze.agregar_metadatos):
        pytest.skip("PENDIENTE: deduplicar necesita que bronze agregue _hash_fila")
    else:
        espera_duplicados = False

    lake.bronze()
    lake.silver()
    lake.gold()
    conocidos, desconocidos = _viajes_con_zona_conocida(lake)
    viajes_1 = lake.tabla("silver", TABLA_VIAJES).count()
    zonas_1 = lake.tabla("silver", TABLA_ZONAS).count()
    clima_1 = lake.tabla("silver", TABLA_CLIMA).count()
    gold_1 = _viajes_de_gold(lake)
    assert viajes_1 == conocidos + desconocidos

    for copias in (2, 3):
        lake.bronze(reprocesar=True)
        lake.silver(reprocesar=True)
        lake.gold(reprocesar=True)

        viajes = lake.tabla("silver", TABLA_VIAJES).count()
        zonas = lake.tabla("silver", TABLA_ZONAS).count()
        clima = lake.tabla("silver", TABLA_CLIMA).count()
        if espera_duplicados:
            assert (viajes, zonas, clima) == (copias * viajes_1, copias * zonas_1, copias * clima_1)
            assert _viajes_de_gold(lake) == copias**3 * conocidos + copias**2 * desconocidos
        else:
            assert (viajes, zonas, clima) == (viajes_1, zonas_1, clima_1)
            assert _viajes_de_gold(lake) == gold_1

    assert gold_1 == VIAJES_VALIDOS if espera_duplicados else gold_1 <= VIAJES_VALIDOS


def test_el_hash_de_bronze_muestra_la_duplicacion_cuando_hay_metadatos(lake):
    """Con metadatos pero sin deduplicar: COUNT(*) es el doble de COUNT(DISTINCT _hash_fila)."""
    if esta_pendiente(bronze.agregar_metadatos):
        pytest.skip("PENDIENTE: sin metadatos no hay _hash_fila que contar")
    if not esta_pendiente(silver.deduplicar):
        pytest.skip("deduplicar ya está hecho: no hay duplicados que mostrar")
    lake.bronze()
    lake.silver()
    lake.bronze(reprocesar=True)
    lake.silver(reprocesar=True)
    viajes = lake.tabla("silver", TABLA_VIAJES)
    assert viajes.count() == 2 * viajes.select("_hash_fila").distinct().count()


# --- usar_mis_funciones y probar_mis_funciones (las ayudas del cuaderno) ------------------------

# Lo que escribiría un equipo en el cuaderno: las dos funciones que le faltan a la casa.
SOLUCION_DEL_EQUIPO = """
from pyspark.sql import functions as F

from pipeline.herramientas.capas import COLUMNAS_METADATOS, hash_fila


def agregar_metadatos(df, fuente, archivo_origen, id_lote, fecha_ingesta):
    originales = df.columns
    con_hash = df.withColumn("_hash_fila", hash_fila(originales))
    return (
        con_hash.withColumn("_fecha_ingesta", F.lit(fecha_ingesta).cast("timestamp"))
        .withColumn("_id_lote", F.lit(id_lote))
        .withColumn("_fuente", F.lit(fuente))
        .withColumn("_archivo_origen", F.lit(archivo_origen))
        .select(*originales, *COLUMNAS_METADATOS)
    )


def deduplicar(df):
    return df.dropDuplicates(["_hash_fila"])
"""

REPO = Path(__file__).resolve().parents[1]
YAML_CODE_EDITOR = "computo: code_editor\nlimite: '1000'\nmes: '2024-01'\nreprocesar: false\n"


@pytest.fixture
def mis_funciones(tmp_path):
    """El módulo con la solución del equipo (en un archivo, para que inspect.getsource la lea)."""
    archivo = tmp_path / "mis_funciones_del_cuaderno.py"
    archivo.write_text(SOLUCION_DEL_EQUIPO, encoding="utf-8")
    especificacion = importlib.util.spec_from_file_location("mis_funciones_del_cuaderno", archivo)
    modulo = importlib.util.module_from_spec(especificacion)
    especificacion.loader.exec_module(modulo)
    modulo.archivo = archivo
    return modulo


@pytest.fixture
def restaurar_funciones(monkeypatch):
    """Al terminar la prueba, bronze y silver vuelven a tener las funciones de la casa."""
    for modulo, nombre in [
        (bronze, "agregar_metadatos"),
        (bronze, "debe_ingestar"),
        (bronze, "registrar_ingesta"),
        (silver, "deduplicar"),
    ]:
        monkeypatch.setattr(modulo, nombre, getattr(modulo, nombre))


def test_usar_mis_funciones_rechaza_un_nombre_que_no_es_del_equipo():
    with pytest.raises(ValueError, match="no es una función del equipo"):
        usar_mis_funciones(limpiar_viajes=lambda df: df)


def test_usar_mis_funciones_pone_las_funciones_en_su_modulo(
    mis_funciones, restaurar_funciones, poner_yaml
):
    poner_yaml(YAML_CODE_EDITOR)
    usar_mis_funciones(
        agregar_metadatos=mis_funciones.agregar_metadatos, deduplicar=mis_funciones.deduplicar
    )
    assert bronze.agregar_metadatos is mis_funciones.agregar_metadatos
    assert silver.deduplicar is mis_funciones.deduplicar


def test_usar_mis_funciones_falla_con_computo_de_glue(
    mis_funciones, restaurar_funciones, poner_yaml
):
    poner_yaml(YAML_CODE_EDITOR.replace("code_editor", "glue_small"))
    la_de_la_casa = silver.deduplicar
    with pytest.raises(RuntimeError, match="no viajan a Glue"):
        usar_mis_funciones(deduplicar=mis_funciones.deduplicar)
    assert silver.deduplicar is la_de_la_casa  # no cambió nada


def test_con_las_funciones_del_equipo_el_pipeline_no_duplica(
    lake, mis_funciones, restaurar_funciones, poner_yaml
):
    """Las dos funciones que escribe el equipo: bronze con metadatos y silver sin repetidos."""
    poner_yaml(YAML_CODE_EDITOR)
    usar_mis_funciones(
        agregar_metadatos=mis_funciones.agregar_metadatos, deduplicar=mis_funciones.deduplicar
    )

    lake.bronze()
    assert lake.tabla("bronze", TABLA_ZONAS).columns[-5:] == COLUMNAS_METADATOS
    lake.silver()
    lake.gold()
    viajes_1 = lake.tabla("silver", TABLA_VIAJES).count()
    gold_1 = _viajes_de_gold(lake)

    lake.bronze(reprocesar=True)
    lake.silver(reprocesar=True)
    lake.gold(reprocesar=True)

    assert len(lake.lotes_de_bronze(TABLA_VIAJES)) == 2  # bronze sí agregó el lote
    assert lake.tabla("silver", TABLA_VIAJES).count() == viajes_1
    assert lake.tabla("silver", TABLA_ZONAS).count() == ZONAS
    assert lake.tabla("silver", TABLA_CLIMA).count() == DIAS_DE_CLIMA
    assert _viajes_de_gold(lake) == gold_1


def _correr_probar_mis_funciones(argumentos_de_python: str) -> subprocess.CompletedProcess:
    """probar_mis_funciones en un proceso aparte (corre pytest por dentro y arranca su Spark)."""
    entorno = {**os.environ, "PYTHONPATH": str(REPO / "src")}
    return subprocess.run(
        [sys.executable, "-c", argumentos_de_python],
        cwd=REPO,
        env=entorno,
        capture_output=True,
        text=True,
        timeout=600,
    )


def test_probar_mis_funciones_sin_funciones_marca_pendiente_lo_que_falta():
    """Con las funciones de los .py: PENDIENTE donde sigue la marca, OK donde ya está resuelto."""
    codigo = (
        "import sys\n"
        "from pipeline.herramientas.equipo import probar_mis_funciones\n"
        "sys.exit(probar_mis_funciones())\n"
    )
    resultado = _correr_probar_mis_funciones(codigo)
    assert resultado.returncode == 0, resultado.stdout + resultado.stderr
    assert "Pruebas del equipo (las mismas de make test)" in resultado.stdout
    metadatos = "PENDIENTE" if esta_pendiente(bronze.agregar_metadatos) else "OK       "
    dedup = "PENDIENTE" if esta_pendiente(silver.deduplicar) else "OK       "
    assert f"{metadatos}  agregar metadatos deja las cinco columnas en orden" in resultado.stdout
    assert f"{dedup}  deduplicar deja una fila por hash" in resultado.stdout
    assert "OK         debe ingestar salta si hay registro y no se reprocesa" in resultado.stdout


def test_probar_mis_funciones_con_la_solucion_pasa_de_pendiente_a_ok(mis_funciones):
    codigo = (
        "import sys\n"
        f"sys.path.insert(0, {str(mis_funciones.archivo.parent)!r})\n"
        "import mis_funciones_del_cuaderno as mf\n"
        "from pipeline.herramientas.equipo import probar_mis_funciones\n"
        "sys.exit(probar_mis_funciones(agregar_metadatos=mf.agregar_metadatos,"
        " deduplicar=mf.deduplicar))\n"
    )
    resultado = _correr_probar_mis_funciones(codigo)
    assert resultado.returncode == 0, resultado.stdout + resultado.stderr
    assert "PENDIENTE" not in resultado.stdout
    assert "FALLA" not in resultado.stdout
    assert "OK         agregar metadatos deja las cinco columnas en orden" in resultado.stdout
    assert "OK         deduplicar deja una fila por hash" in resultado.stdout


def test_probar_mis_funciones_rechaza_un_nombre_que_no_es_del_equipo():
    with pytest.raises(ValueError, match="no es una función del equipo"):
        probar_mis_funciones(gold=lambda df: df)


# --- por la puerta de la clase: correr_bronze(), correr_silver()... con banner y cierre ---------


def test_las_cuatro_funciones_de_correr_py_corren_el_pipeline_con_banner_y_cierre(
    lake, monkeypatch, capsys
):
    from pipeline import carga, correr

    monkeypatch.setattr(carga, "verificar_esquema_con_athena", lambda *a, **k: None)
    monkeypatch.setattr(carga, "cargar_gold", lambda *a, **k: 5)
    perillas = {"mes": MES, "computo": "code_editor", "limite": "1000", "reprocesar": False}

    resultados = (
        correr.correr_bronze(**perillas)
        + correr.correr_silver(**perillas)
        + correr.correr_gold(**perillas)
        + correr.cargar_snowflake(**perillas, conexion=object())
    )
    salida = capsys.readouterr().out

    assert [r.decision for r in resultados] == ["REGISTRÓ"] * 8
    for paso in ("bronze", "silver", "gold", "snowflake"):
        assert f" Paso       : {paso}" in salida
        assert f" Cierre     : paso={paso} mes={MES}" in salida
    assert "tarifa_por_milla_barrio" in salida
    assert "BIGDATA.DEV.TARIFA_POR_MILLA_BARRIO" in salida
