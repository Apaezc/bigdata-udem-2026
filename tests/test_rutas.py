"""Rutas del lake: una sola regla, s3://<lake>/<entorno>/<capa>/<tabla>/mes=AAAA-MM/.

Las pruebas de arriba no usan Spark ni red. Las últimas sí (Spark local) para comprobar que las
funciones de la casa dicen la ruta completa que leen o escriben.
"""

from __future__ import annotations

import logging

import pytest

from pipeline import io, settings
from pipeline.settings import (
    CAPAS,
    ENTORNOS_S3,
    TABLAS_POR_CAPA,
    ConfigError,
    cargar,
    describir_rutas,
    donde_estoy,
    prefijo_lake,
    ruta_lake,
)

BUCKET = "bigdata-lake-123456789012-us-east-2"
MES = "2024-01"


def _todas_las_rutas(entorno: str) -> list[str]:
    """Cada ruta que se puede pedir de un entorno: entorno, capas, tablas y tablas con mes."""
    rutas = [ruta_lake(entorno, bucket=BUCKET)]
    for capa in CAPAS:
        rutas.append(ruta_lake(entorno, capa, bucket=BUCKET))
        for tabla in TABLAS_POR_CAPA[capa]:
            rutas.append(ruta_lake(entorno, capa, tabla, bucket=BUCKET))
            rutas.append(ruta_lake(entorno, capa, tabla, MES, bucket=BUCKET))
    return rutas


# --- el constructor de rutas -------------------------------------------------------------------


@pytest.mark.parametrize("entorno", ENTORNOS_S3)
@pytest.mark.parametrize("capa", CAPAS)
def test_cada_tabla_de_cada_capa_cuelga_de_su_entorno(entorno, capa):
    assert ruta_lake(entorno, capa, bucket=BUCKET) == f"s3://{BUCKET}/{entorno}/{capa}"
    for tabla in TABLAS_POR_CAPA[capa]:
        esperada = f"s3://{BUCKET}/{entorno}/{capa}/{tabla}"
        assert ruta_lake(entorno, capa, tabla, bucket=BUCKET) == esperada
        assert ruta_lake(entorno, capa, tabla, MES, bucket=BUCKET) == f"{esperada}/mes={MES}"


def test_ejemplos_de_la_regla():
    assert ruta_lake("dev", "silver", "fhvhv_trips", bucket=BUCKET).endswith(
        "/dev/silver/fhvhv_trips"
    )
    assert ruta_lake("prod", "bronze", "fhvhv", "2024-03", bucket=BUCKET) == (
        f"s3://{BUCKET}/prod/bronze/fhvhv/mes=2024-03"
    )
    assert prefijo_lake("prod", "muestra") == "prod/muestra"
    assert prefijo_lake("dev") == "dev"


def test_con_dev_nunca_sale_una_ruta_de_prod():
    rutas = _todas_las_rutas("dev")
    assert len(rutas) > 20
    for ruta in rutas:
        assert ruta.startswith(f"s3://{BUCKET}/dev"), ruta
        assert "/prod" not in ruta, ruta
    # tampoco en los prefijos ni en la configuración que se arma con las rutas
    for capa in CAPAS:
        assert "prod" not in prefijo_lake("dev", capa)


def test_con_prod_nunca_sale_una_ruta_de_dev():
    for ruta in _todas_las_rutas("prod"):
        assert ruta.startswith(f"s3://{BUCKET}/prod"), ruta
        assert "/dev" not in ruta, ruta


def test_dev_y_prod_no_comparten_ningun_prefijo():
    prefijos_dev = {prefijo_lake("dev", c, t) for c in CAPAS for t in TABLAS_POR_CAPA[c]}
    prefijos_prod = {prefijo_lake("prod", c, t) for c in CAPAS for t in TABLAS_POR_CAPA[c]}
    assert prefijos_dev.isdisjoint(prefijos_prod)
    # ninguno de un entorno está dentro del otro (ni siquiera como carpeta padre)
    for prefijo in prefijos_dev:
        assert not prefijo.startswith("prod/")
    for prefijo in prefijos_prod:
        assert not prefijo.startswith("dev/")


def test_la_variable_lake_bucket_pone_el_bucket(monkeypatch):
    monkeypatch.setenv("LAKE_BUCKET", "mi-bucket")
    assert ruta_lake("dev", "gold") == "s3://mi-bucket/dev/gold"
    monkeypatch.delenv("LAKE_BUCKET")
    with pytest.raises(ConfigError, match="LAKE_BUCKET"):
        ruta_lake("dev", "gold")


def test_local_vive_en_disco_y_su_bronze_es_la_muestra():
    assert ruta_lake("local", "bronze").endswith("/lake/muestra")
    assert ruta_lake("local", "muestra").endswith("/lake/muestra")
    assert ruta_lake("local", "silver", "fhvhv_trips").endswith("/lake/silver/fhvhv_trips")
    for capa in CAPAS:
        assert "s3://" not in ruta_lake("local", capa)
        assert ruta_lake("local", capa).startswith("/")
    with pytest.raises(ConfigError, match="no tiene prefijo en S3"):
        prefijo_lake("local", "silver")


@pytest.mark.parametrize(
    "pedido",
    [
        {"entorno": "qa"},
        {"entorno": "dev", "capa": "platino"},
        {"entorno": "dev", "capa": "silver", "tabla": "../prod/silver"},
        {"entorno": "dev", "capa": "silver", "tabla": "a/b"},
        {"entorno": "dev", "capa": "silver", "tabla": ""},
        {"entorno": "dev", "capa": "silver", "tabla": "fhvhv_trips", "mes": "2024-13"},
        {"entorno": "dev", "tabla": "fhvhv"},
        {"entorno": "dev", "capa": "silver", "mes": MES},
    ],
)
def test_pedidos_invalidos_se_rechazan(pedido):
    with pytest.raises((ConfigError, ValueError)):
        ruta_lake(bucket=BUCKET, **pedido)


def test_los_nombres_de_io_son_los_de_settings():
    # io los reexporta con los nombres de siempre: los notebooks y los DAGs siguen igual.
    assert (io.VIAJES, io.ZONAS, io.CLIMA) == ("fhvhv", "taxi_zones", "clima")
    assert io.CARPETA_CAPA == {"silver": "fhvhv_trips", "gold": "daily_zone_metrics"}
    assert io.ruta_lake is settings.ruta_lake
    assert io.donde_estoy is settings.donde_estoy
    assert set(TABLAS_POR_CAPA["bronze"]) == {io.VIAJES, io.ZONAS, io.CLIMA}


# --- la configuración se arma con esas rutas -------------------------------------------------


@pytest.mark.parametrize("entorno", ENTORNOS_S3)
def test_ninguna_ruta_de_la_configuracion_sale_del_entorno(monkeypatch, entorno):
    monkeypatch.setenv("LAKE_BUCKET", BUCKET)
    cfg = cargar(entorno)
    rutas = [*cfg["rutas"].values(), cfg["muestra"]["destino"]]
    for ruta in rutas:
        assert ruta.startswith(f"s3://{BUCKET}/{entorno}/"), ruta


def test_la_configuracion_dev_no_menciona_prod(monkeypatch):
    monkeypatch.setenv("LAKE_BUCKET", BUCKET)
    cfg = cargar("dev")
    rutas = [*cfg["rutas"].values(), cfg["muestra"]["destino"]]
    assert not [r for r in rutas if "/prod" in r]


def test_el_bronze_y_la_muestra_de_cada_entorno_son_distintos(monkeypatch):
    monkeypatch.setenv("LAKE_BUCKET", BUCKET)
    dev, prod = cargar("dev"), cargar("prod")
    assert dev["rutas"]["bronze"] != prod["rutas"]["bronze"]
    assert dev["muestra"]["destino"] != prod["muestra"]["destino"]
    assert prod["muestra"]["destino"] == f"s3://{BUCKET}/prod/muestra"


def test_si_una_ruta_se_sale_del_entorno_la_configuracion_se_rechaza(monkeypatch):
    monkeypatch.setenv("LAKE_BUCKET", BUCKET)
    cfg = {
        "rutas": {"bronze": f"s3://{BUCKET}/prod/bronze"},
        "muestra": {"destino": f"s3://{BUCKET}/dev/muestra"},
    }
    with pytest.raises(ConfigError, match="dev y prod no se mezclan"):
        settings._verificar_aislamiento("dev", cfg)


def test_local_baja_la_muestra_de_prod(monkeypatch):
    monkeypatch.delenv("LAKE_BUCKET", raising=False)
    assert cargar("local")["muestra"]["sincronizar_desde"] == "prod/muestra"


# --- la tabla "dónde estoy" -------------------------------------------------------------------


def test_describir_rutas_de_dev_dice_bucket_capas_y_tablas():
    texto = describir_rutas("dev", BUCKET)
    assert BUCKET in texto
    assert f"s3://{BUCKET}/dev/bronze/fhvhv" in texto
    assert f"s3://{BUCKET}/dev/bronze/_crudo" in texto
    assert f"s3://{BUCKET}/dev/silver/fhvhv_trips" in texto
    assert f"s3://{BUCKET}/dev/gold/daily_zone_metrics" in texto
    assert f"s3://{BUCKET}/dev/muestra/clima" in texto
    assert "No toca prod/" in texto
    assert "s3://" + BUCKET + "/prod" not in texto  # dev nunca nombra una ruta de prod
    for prefijo in ("code/", "dags/", "logs/", "tmp/"):
        assert prefijo in texto


def test_describir_rutas_de_local_dice_disco_y_de_donde_baja_la_muestra():
    texto = describir_rutas("local", BUCKET)
    assert "DISCO" in texto
    assert "/lake/silver/fhvhv_trips" in texto
    assert f"s3://{BUCKET}/prod/muestra/" in texto
    assert f"s3://{BUCKET}/dev" not in texto


def test_describir_rutas_sin_bucket_usa_un_marcador(monkeypatch):
    monkeypatch.delenv("LAKE_BUCKET", raising=False)
    texto = describir_rutas("prod")
    assert "s3://<tu-bucket>/prod/gold/daily_zone_metrics" in texto
    assert "LAKE_BUCKET" in texto


def test_donde_estoy_imprime_la_tabla(capsys, monkeypatch):
    monkeypatch.setenv("LAKE_BUCKET", BUCKET)
    donde_estoy("prod")
    salida = capsys.readouterr().out
    assert salida.strip() == describir_rutas("prod").strip()
    assert f"s3://{BUCKET}/prod/silver/fhvhv_trips" in salida


# --- las funciones de la casa dicen la ruta completa ------------------------------------------


def test_anunciar_va_al_log_cuando_hay_logging(caplog, capsys):
    with caplog.at_level(logging.INFO, logger="pipeline.io"):
        io.anunciar("LEE", "s3://b/dev/silver/fhvhv_trips", "silver")
    assert "LEE" in caplog.text
    assert "s3://b/dev/silver/fhvhv_trips" in caplog.text
    assert capsys.readouterr().out == ""  # no se repite en pantalla


def test_anunciar_imprime_si_nadie_configuro_el_logging(capsys, monkeypatch):
    sin_logging = logging.getLogger("prueba_sin_handlers")
    sin_logging.propagate = False
    monkeypatch.setattr(io, "log", sin_logging)
    io.anunciar("ESCRIBE", "s3://b/dev/gold/daily_zone_metrics")
    assert "ESCRIBE  s3://b/dev/gold/daily_zone_metrics" in capsys.readouterr().out


def test_publicar_borrar_y_copiar_en_s3_dicen_la_ruta_completa(monkeypatch, caplog, tmp_path):
    import boto3

    class ClienteFalso:
        def upload_file(self, *args):
            pass

        def delete_object(self, **kwargs):
            pass

        def copy(self, *args):
            pass

    monkeypatch.setattr(boto3, "client", lambda *a, **k: ClienteFalso())
    archivo = tmp_path / "datos.txt"
    archivo.write_text("x")
    origen = f"s3://{BUCKET}/dev/bronze/_crudo/clima/a.json"
    destino = f"s3://{BUCKET}/dev/bronze/_crudo/clima/b.json"
    with caplog.at_level(logging.INFO, logger="pipeline.io"):
        io.publicar(archivo, origen)
        io.copiar(origen, destino)
        io.borrar(origen)
    assert f"SUBE     {origen}" in caplog.text
    assert f"COPIA    {destino}" in caplog.text
    assert f"BORRA    {origen}" in caplog.text


def test_borrar_particiones_anuncia_lo_que_borra(tmp_path, caplog):
    ruta = tmp_path / "gold" / "daily_zone_metrics"
    (ruta / "mes=2024-01").mkdir(parents=True)
    with caplog.at_level(logging.INFO, logger="pipeline.io"):
        io.borrar_particiones(str(ruta), ["mes=2024-01/"])
    assert f"BORRA    {ruta}/mes=2024-01*" in caplog.text
    assert not (ruta / "mes=2024-01").exists()


def test_leer_zonas_dice_el_lote_que_lee(spark, tmp_path, armar_bronze, caplog):
    base = tmp_path / "bronze"
    armar_bronze(base)
    with caplog.at_level(logging.INFO, logger="pipeline.io"):
        io.leer_zonas(spark, str(base))
    assert f"LEE      {base}/taxi_zones/lote=" in caplog.text
