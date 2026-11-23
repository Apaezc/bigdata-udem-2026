"""El archivo crudo: se baja de la fuente una sola vez y se guarda tal cual en la capa bronze.

Las tres funciones que se enseñan en clase son `traer_crudo_viajes`, `traer_crudo_taxi_zones` y
`traer_crudo_clima`. Cada una devuelve la ruta s3:// completa donde quedó el archivo, y antes
de bajar nada revisa, en este orden:

    1. ¿El archivo ya está en _crudo?  -> no se descarga (ahorra los ~450 MB del mes).
    2. ¿Está en la ruta del diseño anterior (sin _crudo)? -> se mueve a _crudo.
    3. Si no está en ninguna parte -> se descarga de la fuente.

Este módulo no importa pyspark: la VM de Airflow no lo tiene.
"""

from __future__ import annotations

import logging
import shutil
import tempfile
import urllib.request
from pathlib import Path

from pipeline.herramientas import archivos
from pipeline.herramientas.rutas import (
    MES_SIN_MES,
    TABLA_CLIMA,
    TABLA_VIAJES,
    TABLA_ZONAS,
    ruta_del_crudo,
    ruta_lake,
    ultimo_dia_mes,
    validar_mes,
)

log = logging.getLogger(__name__)

URL_VIAJES = "https://d37ci6vzurychx.cloudfront.net/trip-data/fhvhv_tripdata_{mes}.parquet"
URL_ZONAS = "https://d37ci6vzurychx.cloudfront.net/misc/taxi_zone_lookup.csv"
URL_CLIMA = (
    "https://archive-api.open-meteo.com/v1/archive"
    "?latitude=40.71&longitude=-74.01"
    "&start_date={inicio}&end_date={fin}"
    "&daily=precipitation_sum,temperature_2m_mean"
    "&timezone=America%2FNew_York"
)
TIMEOUT_S = 300

__all__ = [
    "MES_SIN_MES",
    "URL_CLIMA",
    "URL_VIAJES",
    "URL_ZONAS",
    "descargar",
    "traer_crudo_clima",
    "traer_crudo_taxi_zones",
    "traer_crudo_viajes",
    "url_clima",
    "url_viajes",
    "url_zonas",
]


# --- de dónde se baja cada archivo ------------------------------------------------------------


def url_viajes(mes: str) -> str:
    return URL_VIAJES.format(mes=validar_mes(mes))


def url_zonas() -> str:
    return URL_ZONAS


def url_clima(mes: str) -> str:
    inicio = f"{validar_mes(mes)}-01"
    fin = ultimo_dia_mes(mes).isoformat()
    return URL_CLIMA.format(inicio=inicio, fin=fin)


# --- la descarga ------------------------------------------------------------------------------


def descargar(url: str, destino: str) -> None:
    """Descarga `url` a un archivo temporal y lo publica en `destino` (s3://).

    Se baja primero a disco temporal y no directo a S3 porque así, si la descarga se corta,
    en el lake no queda un archivo a medias que la próxima corrida creería completo.
    """
    with tempfile.TemporaryDirectory(prefix="crudo-") as tmp:
        local = Path(tmp) / "archivo"
        print(f"DESCARGA {url}  ->  {destino}")
        with urllib.request.urlopen(url, timeout=TIMEOUT_S) as resp, local.open("wb") as f:
            shutil.copyfileobj(resp, f)
        archivos.publicar(local, destino)


def _asegurar_crudo(url: str, destino: str, ruta_anterior: str) -> str:
    """Deja el archivo crudo en `destino` haciendo el menor trabajo posible."""
    if archivos.existe(destino):
        print(f"YA ESTÁ  {destino}  (no se descarga)")
        return destino
    if archivos.existe(ruta_anterior):
        print(f"MUEVE    {ruta_anterior}  ->  {destino}  (ruta del diseño anterior)")
        archivos.mover(ruta_anterior, destino)
        return destino
    descargar(url, destino)
    return destino


def _ruta_del_diseno_anterior(entorno: str, tabla: str, mes: str | None, destino: str) -> str:
    """Dónde lo guardaba el diseño anterior: <bronze>/<tabla>[/mes=AAAA-MM]/<mismo nombre>."""
    nombre = destino.rstrip("/").rsplit("/", 1)[-1]
    carpeta = ruta_lake(entorno, "bronze", tabla, mes)
    return archivos.unir(carpeta, nombre)


def _traer(entorno: str, tabla: str, mes: str | None, url: str) -> str:
    destino = ruta_del_crudo(entorno, tabla, mes)
    anterior = _ruta_del_diseno_anterior(entorno, tabla, mes, destino)
    return _asegurar_crudo(url, destino, anterior)


# --- las tres funciones que se enseñan --------------------------------------------------------


def traer_crudo_viajes(entorno: str, mes: str) -> str:
    """Deja el Parquet de viajes del mes en _crudo y devuelve su ruta s3://."""
    return _traer(entorno, TABLA_VIAJES, mes, url_viajes(mes))


def traer_crudo_taxi_zones(entorno: str) -> str:
    """Deja el CSV de zonas en _crudo (no tiene mes) y devuelve su ruta s3://."""
    return _traer(entorno, TABLA_ZONAS, None, url_zonas())


def traer_crudo_clima(entorno: str, mes: str) -> str:
    """Deja el JSON de clima del mes en _crudo y devuelve su ruta s3://."""
    return _traer(entorno, TABLA_CLIMA, mes, url_clima(mes))
