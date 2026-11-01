"""Carga de configuración por entorno y utilidades de meses ('YYYY-MM')."""

from __future__ import annotations

import os
import re
from datetime import date, timedelta
from importlib import resources
from typing import Any

import yaml

ENTORNOS = ("local", "dev", "prod")
PLACEHOLDER_BUCKET = "{lake_bucket}"
_RE_MES = re.compile(r"^\d{4}-(0[1-9]|1[0-2])$")


class ConfigError(RuntimeError):
    """Configuración inválida o incompleta."""


def cargar(env: str) -> dict[str, Any]:
    """Lee src/pipeline/config/<env>.yaml y resuelve placeholders y rutas locales."""
    if env not in ENTORNOS:
        raise ConfigError(f"Entorno desconocido '{env}'. Válidos: {', '.join(ENTORNOS)}")
    ruta = resources.files("pipeline") / "config" / f"{env}.yaml"
    with ruta.open("r", encoding="utf-8") as f:
        cfg = yaml.safe_load(f)
    cfg = _resolver(cfg)
    cfg["rutas"] = {capa: _ruta_absoluta(r) for capa, r in cfg["rutas"].items()}
    return cfg


def _resolver(obj: Any) -> Any:
    if isinstance(obj, dict):
        return {k: _resolver(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_resolver(v) for v in obj]
    if isinstance(obj, str) and PLACEHOLDER_BUCKET in obj:
        bucket = os.environ.get("LAKE_BUCKET")
        if not bucket:
            raise ConfigError(
                f"Falta la variable de entorno LAKE_BUCKET (nombre del bucket del lake) "
                f"para resolver '{obj}'"
            )
        return obj.replace(PLACEHOLDER_BUCKET, bucket)
    return obj


def _ruta_absoluta(ruta: str) -> str:
    """Convierte rutas locales relativas (./lake/...) en absolutas; S3 se deja igual."""
    if "://" in ruta:
        return ruta
    return os.path.abspath(ruta)


def validar_mes(mes: str) -> str:
    """Valida el formato 'YYYY-MM' y lo devuelve."""
    if not _RE_MES.match(mes or ""):
        raise ValueError(f"Mes inválido '{mes}': se espera formato YYYY-MM")
    return mes


def inicio_fin_mes(mes: str) -> tuple[date, date]:
    """Devuelve (primer día del mes, primer día del mes siguiente). El fin es exclusivo."""
    anio, num = (int(x) for x in validar_mes(mes).split("-"))
    inicio = date(anio, num, 1)
    fin = date(anio + 1, 1, 1) if num == 12 else date(anio, num + 1, 1)
    return inicio, fin


def rango_meses(meses: list[str]) -> tuple[date, date]:
    """(primer día del primer mes, primer día del mes siguiente al último). El fin es exclusivo."""
    if not meses:
        raise ValueError("Se necesita al menos un mes")
    ordenados = sorted(validar_mes(m) for m in meses)
    return inicio_fin_mes(ordenados[0])[0], inicio_fin_mes(ordenados[-1])[1]


def ultimo_dia_mes(mes: str) -> date:
    """Último día calendario del mes."""
    _, fin = inicio_fin_mes(mes)
    return fin - timedelta(days=1)
