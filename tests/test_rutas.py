"""Rutas del lake: una sola regla, s3://<lake>/<entorno>/<capa>/<tabla>/mes=AAAA-MM/.

Ninguna prueba de este archivo usa Spark ni la red (sts va con un doble).
"""

from __future__ import annotations

from datetime import date

import pytest

from pipeline.herramientas.rutas import (
    CAPAS,
    ENTORNOS,
    ConfigError,
    bucket_del_lake,
    describir_rutas,
    dir_del_crudo,
    dir_del_lote,
    donde_estoy,
    inicio_fin_mes,
    nombre_tabla_snowflake,
    prefijo_lake,
    rango_meses,
    ruta_del_crudo,
    ruta_lake,
    ultimo_dia_mes,
    validar_entorno,
    validar_mes,
)

# Las fixtures entorno_limpio y poner_yaml viven en tests/p1_fixtures.py.
pytest_plugins = ["p1_fixtures"]
BUCKET = "bigdata-lake-123456789012-us-east-2"  # el que devuelve el doble de sts

MES = "2024-01"


# --- ruta_lake ---------------------------------------------------------------------------------


@pytest.mark.parametrize("entorno", ENTORNOS)
@pytest.mark.parametrize("capa", CAPAS)
def test_cada_tabla_de_cada_capa_cuelga_de_su_entorno(entorno, capa):
    assert ruta_lake(entorno, capa, bucket=BUCKET) == f"s3://{BUCKET}/{entorno}/{capa}"
    esperada = f"s3://{BUCKET}/{entorno}/{capa}/fhvhv"
    assert ruta_lake(entorno, capa, "fhvhv", bucket=BUCKET) == esperada
    assert ruta_lake(entorno, capa, "fhvhv", MES, bucket=BUCKET) == f"{esperada}/mes={MES}"


def test_las_rutas_del_diseno():
    assert ruta_lake("dev", bucket=BUCKET) == f"s3://{BUCKET}/dev"
    assert ruta_lake("dev", "silver", "fhvhv", MES, BUCKET) == (
        f"s3://{BUCKET}/dev/silver/fhvhv/mes=2024-01"
    )
    assert ruta_lake("prod", "gold", "tarifa_por_milla_barrio", MES, BUCKET) == (
        f"s3://{BUCKET}/prod/gold/tarifa_por_milla_barrio/mes=2024-01"
    )
    assert ruta_lake("dev", "silver", "taxi_zones", bucket=BUCKET).endswith(
        "/dev/silver/taxi_zones"
    )


def test_dev_y_prod_no_comparten_ningun_prefijo():
    for capa in CAPAS:
        dev = ruta_lake("dev", capa, "fhvhv", MES, BUCKET)
        prod = ruta_lake("prod", capa, "fhvhv", MES, BUCKET)
        assert "/prod/" not in dev + "/"
        assert "/dev/" not in prod + "/"


def test_prefijo_lake_siempre_empieza_por_el_entorno():
    assert prefijo_lake("dev", "bronze", "clima", MES) == "dev/bronze/clima/mes=2024-01"
    assert prefijo_lake("prod") == "prod"


@pytest.mark.parametrize("entorno", ["local", "qa", "", "DEV"])
def test_un_entorno_invalido_falla(entorno):
    with pytest.raises(ConfigError):
        ruta_lake(entorno, "bronze", bucket=BUCKET)


def test_local_dice_que_ya_no_existe():
    with pytest.raises(ConfigError, match="'local' ya no existe"):
        validar_entorno("local")


@pytest.mark.parametrize("tabla", ["../prod/bronze", "a/b", "tabla con espacio", "", "t;drop"])
def test_un_nombre_de_tabla_no_puede_salirse_de_la_carpeta(tabla):
    with pytest.raises(ConfigError):
        ruta_lake("dev", "silver", tabla, bucket=BUCKET)


def test_capa_desconocida_y_argumentos_sueltos_fallan():
    with pytest.raises(ConfigError, match="Capa desconocida"):
        ruta_lake("dev", "platino", bucket=BUCKET)
    with pytest.raises(ConfigError):
        ruta_lake("dev", tabla="fhvhv", bucket=BUCKET)
    with pytest.raises(ConfigError):
        ruta_lake("dev", "silver", mes=MES, bucket=BUCKET)


def test_un_mes_invalido_falla():
    with pytest.raises(ValueError):
        ruta_lake("dev", "silver", "fhvhv", "2024-13", BUCKET)


# --- el bucket ---------------------------------------------------------------------------------


def test_el_argumento_gana_sobre_la_variable(entorno_limpio, monkeypatch):
    monkeypatch.setenv("LAKE_BUCKET", "de-la-variable")
    assert bucket_del_lake("del-argumento") == "del-argumento"
    assert bucket_del_lake() == "de-la-variable"
    assert entorno_limpio == []


def test_en_dev_sin_variable_el_bucket_sale_de_sts(entorno_limpio):
    assert bucket_del_lake() == BUCKET
    assert entorno_limpio == ["sts"]


def test_en_prod_sin_variable_no_se_adivina_el_bucket(entorno_limpio, monkeypatch):
    monkeypatch.setenv("PIPELINE_ENTORNO", "prod")
    with pytest.raises(ConfigError, match="LAKE_BUCKET"):
        bucket_del_lake()
    assert entorno_limpio == []


def test_si_sts_falla_el_mensaje_dice_que_hacer(entorno_limpio, monkeypatch):
    import pipeline.herramientas.rutas as rutas

    def sin_credenciales():
        raise RuntimeError("sin credenciales")

    monkeypatch.setattr(rutas, "_bucket_por_sts", sin_credenciales)
    with pytest.raises(ConfigError, match="credenciales de AWS"):
        bucket_del_lake()


# --- PIPELINE_RAIZ_LAKE (solo pruebas) ---------------------------------------------------------


def test_con_raiz_de_prueba_las_rutas_son_de_disco(raiz_lake):
    assert ruta_lake("dev") == f"file://{raiz_lake}/dev"
    assert ruta_lake("prod", "silver", "fhvhv", MES) == (
        f"file://{raiz_lake}/prod/silver/fhvhv/mes=2024-01"
    )


def test_la_raiz_de_prueba_solo_acepta_file(entorno_limpio, monkeypatch):
    monkeypatch.setenv("PIPELINE_RAIZ_LAKE", "s3://otro-bucket/x")
    with pytest.raises(ConfigError, match="solo acepta rutas file://"):
        ruta_lake("dev", "bronze")
    monkeypatch.setenv("PIPELINE_RAIZ_LAKE", "/tmp/sin-esquema")
    with pytest.raises(ConfigError, match="file://"):
        ruta_lake("dev", "bronze")


def test_la_raiz_de_prueba_no_cambia_el_entorno(raiz_lake, monkeypatch):
    from pipeline.herramientas.corrida import entorno_actual

    monkeypatch.delenv("PIPELINE_ENTORNO", raising=False)
    assert entorno_actual() == "dev"


# --- crudo, lotes y Snowflake ------------------------------------------------------------------


def test_rutas_del_crudo():
    base = f"s3://{BUCKET}/dev/bronze/_crudo"
    assert dir_del_crudo("dev", "fhvhv", MES, BUCKET) == f"{base}/fhvhv/mes=2024-01"
    assert ruta_del_crudo("dev", "fhvhv", MES, BUCKET) == (
        f"{base}/fhvhv/mes=2024-01/fhvhv_tripdata_2024-01.parquet"
    )
    assert ruta_del_crudo("dev", "clima", MES, BUCKET) == (
        f"{base}/clima/mes=2024-01/open_meteo_2024-01.json"
    )
    assert dir_del_crudo("dev", "taxi_zones", bucket=BUCKET) == f"{base}/taxi_zones"
    assert ruta_del_crudo("prod", "taxi_zones", bucket=BUCKET) == (
        f"s3://{BUCKET}/prod/bronze/_crudo/taxi_zones/taxi_zone_lookup.csv"
    )


def test_las_zonas_no_llevan_mes_y_las_demas_si():
    with pytest.raises(ConfigError, match="no se parte por mes"):
        dir_del_crudo("dev", "taxi_zones", MES, BUCKET)
    with pytest.raises(ConfigError, match="falta el mes"):
        dir_del_crudo("dev", "fhvhv", None, BUCKET)
    with pytest.raises(ConfigError):
        ruta_del_crudo("dev", "desconocida", MES, BUCKET)


def test_dir_del_lote():
    id_lote = "20260115T143005Z_a3f9c1"
    assert dir_del_lote("dev", "fhvhv", id_lote, MES, BUCKET) == (
        f"s3://{BUCKET}/dev/bronze/fhvhv/mes=2024-01/lote={id_lote}"
    )
    assert dir_del_lote("dev", "taxi_zones", id_lote, bucket=BUCKET) == (
        f"s3://{BUCKET}/dev/bronze/taxi_zones/lote={id_lote}"
    )
    with pytest.raises(ConfigError):
        dir_del_lote("dev", "fhvhv", "../otro", MES, BUCKET)


def test_nombre_tabla_snowflake():
    assert nombre_tabla_snowflake("dev", "tarifa_por_milla_barrio") == (
        "BIGDATA.DEV.TARIFA_POR_MILLA_BARRIO"
    )
    assert nombre_tabla_snowflake("prod", "mi_tabla") == "BIGDATA.PROD.MI_TABLA"
    with pytest.raises(ConfigError):
        nombre_tabla_snowflake("dev", "x; DROP TABLE y")
    with pytest.raises(ConfigError):
        nombre_tabla_snowflake("local", "t")


# --- describir_rutas y donde_estoy -------------------------------------------------------------


def test_describir_rutas_dice_bucket_y_capas():
    texto = describir_rutas("dev", BUCKET)
    assert BUCKET in texto
    assert "No toca prod/" in texto
    for capa in CAPAS:
        assert f"s3://{BUCKET}/dev/{capa}" in texto
    assert f"s3://{BUCKET}/dev/bronze/_crudo" in texto


def test_describir_rutas_sin_bucket_avisa(entorno_limpio, monkeypatch):
    monkeypatch.setenv("LAKE_BUCKET", "")
    texto = describir_rutas("prod")
    assert "<tu-bucket>" in texto
    assert "define LAKE_BUCKET" in texto


def test_describir_rutas_marca_la_raiz_de_prueba(raiz_lake):
    assert "RAÍZ DE PRUEBA" in describir_rutas("dev")


def test_donde_estoy_imprime(capsys):
    donde_estoy("prod", BUCKET)
    assert f"s3://{BUCKET}/prod/silver" in capsys.readouterr().out


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


def test_ultimo_dia_mes():
    assert ultimo_dia_mes("2024-02") == date(2024, 2, 29)
    assert ultimo_dia_mes("2024-12") == date(2024, 12, 31)
