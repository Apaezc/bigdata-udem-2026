"""Traer cada fuente cruda a bronze/_crudo (PAQUETE P2: aquí solo está el contrato).

Regla: si el archivo ya está en _crudo no se descarga; si está en la ruta del diseño anterior se
mueve; si no, se descarga. Las funciones devuelven la ruta completa del archivo crudo.
"""

from __future__ import annotations

URL_VIAJES = "https://d37ci6vzurychx.cloudfront.net/trip-data/fhvhv_tripdata_{mes}.parquet"
URL_ZONAS = "https://d37ci6vzurychx.cloudfront.net/misc/taxi_zone_lookup.csv"
URL_CLIMA = (
    "https://archive-api.open-meteo.com/v1/archive"
    "?latitude=40.71&longitude=-74.01"
    "&start_date={inicio}&end_date={fin}"
    "&daily=precipitation_sum,temperature_2m_mean"
    "&timezone=America%2FNew_York"
)


def traer_crudo_viajes(entorno: str, mes: str) -> str:
    """Deja el Parquet de viajes del mes en <bronze>/_crudo/fhvhv/mes=<mes>/ y devuelve su ruta."""
    raise NotImplementedError("P2: traer_crudo_viajes")


def traer_crudo_taxi_zones(entorno: str) -> str:
    """Deja el CSV de zonas en <bronze>/_crudo/taxi_zones/ y devuelve su ruta."""
    raise NotImplementedError("P2: traer_crudo_taxi_zones")


def traer_crudo_clima(entorno: str, mes: str) -> str:
    """Deja el JSON de clima del mes en <bronze>/_crudo/clima/mes=<mes>/ y devuelve su ruta."""
    raise NotImplementedError("P2: traer_crudo_clima")


def url_viajes(mes: str) -> str:
    """URL de descarga de los viajes FHVHV del mes."""
    raise NotImplementedError("P2: url_viajes")


def url_zonas() -> str:
    """URL de descarga del lookup de zonas."""
    raise NotImplementedError("P2: url_zonas")


def url_clima(mes: str) -> str:
    """URL de la API de Open-Meteo para todos los días del mes."""
    raise NotImplementedError("P2: url_clima")


def descargar(url: str, destino: str) -> None:
    """Descarga la url a un temporal y la publica en destino (ruta file:// o s3://)."""
    raise NotImplementedError("P2: descargar")
