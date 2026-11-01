"""Capa bronze: descarga de fuentes SIN transformar (solo env dev/prod).

Fuentes:
- NYC TLC High Volume For-Hire Vehicles (FHVHV: Uber, Lyft...), Parquet mensual (~450 MB).
- NYC taxi zone lookup (CSV).
- Open-Meteo archive API (JSON diario, NYC).

Se descarga con urllib en el driver y se publica en la ruta de config (s3:// con boto3).
Si el archivo ya existe en bronze no se vuelve a descargar: bronze es compartido por dev y prod.
En local no hay bronze: se trabaja sobre la muestra (ver pipeline/muestra.py).
"""

from __future__ import annotations

import logging
import shutil
import tempfile
import urllib.request
from pathlib import Path
from typing import Any

from pipeline import io
from pipeline.settings import ultimo_dia_mes

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


def url_clima(mes: str) -> str:
    inicio = f"{mes}-01"
    fin = ultimo_dia_mes(mes).isoformat()
    return URL_CLIMA.format(inicio=inicio, fin=fin)


def descargar(url: str, destino: str, *, forzar: bool = False) -> str:
    """Descarga url y la publica en destino (ruta local o s3://), salvo que ya exista."""
    if not forzar and io.existe(destino):
        log.info("Ya existe en bronze, se omite: %s", destino)
        return destino
    with tempfile.TemporaryDirectory(prefix="bronze-") as tmp:
        local = Path(tmp) / "archivo"
        log.info("Descargando %s", url)
        with urllib.request.urlopen(url, timeout=TIMEOUT_S) as resp, local.open("wb") as f:
            shutil.copyfileobj(resp, f)
        io.publicar(local, destino)
    log.info("Bronze escrito en %s", destino)
    return destino


def main(spark: Any, cfg: dict, args: Any) -> None:
    base = cfg["rutas"]["bronze"]
    descargar(URL_ZONAS, io.ruta_zonas(base))
    for mes in args.meses:
        descargar(URL_VIAJES.format(mes=mes), io.ruta_bronze_viajes(cfg, mes))
        descargar(url_clima(mes), io.ruta_clima(base, mes))
