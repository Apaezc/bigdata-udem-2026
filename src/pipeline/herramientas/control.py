"""La tabla de control: la puerta que decide si un mes se ingesta o se salta (PAQUETE P3: contrato).

Tablas: BIGDATA.CONTROL_DEV.WATERMARK y BIGDATA.CONTROL_PROD.WATERMARK. Columnas, en orden:
FUENTE, CAPA, TABLA, MES, FILAS, INICIO, REPROCESAR, COMPUTO, LIMITE, LEIDAS.

Regla de la puerta, clave (TABLA, CAPA, MES):
- no hay registro y reprocesar=false -> se ingesta;
- hay registro y reprocesar=false    -> se salta (sea cual sea el cómputo o el límite del registro);
- reprocesar=true                    -> siempre se ingesta.

Orden único de argumentos en toda la caja: (corrida, tabla, capa, mes, ...) y el entorno primero
cuando no hay corrida.
"""

from __future__ import annotations

from collections.abc import Callable
from datetime import datetime
from typing import Any

from pipeline.herramientas.corrida import Corrida, Resultado


def tabla_de_control(entorno: str) -> str:
    """'BIGDATA.CONTROL_DEV.WATERMARK' o 'BIGDATA.CONTROL_PROD.WATERMARK'."""
    raise NotImplementedError("P3: tabla_de_control")


def consultar_control(
    entorno: str, tabla: str, capa: str, mes: str, conexion: Any = None
) -> list[dict]:
    """Registros de esa tabla, capa y mes, del más antiguo al más reciente; claves en minúscula."""
    raise NotImplementedError("P3: consultar_control")


def mes_ya_procesado(
    corrida: Corrida, tabla: str, capa: str, mes: str, conexion: Any = None
) -> bool:
    """LA PUERTA: True = se salta (hay registro y reprocesar=false)."""
    raise NotImplementedError("P3: mes_ya_procesado")


def registrar_control(
    corrida: Corrida,
    tabla: str,
    capa: str,
    mes: str,
    filas: int,
    inicio: datetime,
    fuente: str,
    leidas: int | None = None,
    conexion: Any = None,
) -> None:
    """Inserta un registro (filas = escritas). Guarda también COMPUTO, LIMITE y LEIDAS."""
    raise NotImplementedError("P3: registrar_control")


def con_control(
    corrida: Corrida,
    tabla: str,
    capa: str,
    mes: str,
    fuente: str,
    trabajo: Callable[[], tuple[int, int]],
    conexion: Any = None,
) -> Resultado:
    """Puerta + registro, para silver, gold y snowflake.

    Si mes_ya_procesado -> Resultado('SE SALTÓ'); si no, trabajo() -> (leídas, escritas), registra
    y devuelve Resultado('REGISTRÓ'). No imprime.
    """
    raise NotImplementedError("P3: con_control")


def exigir_rol_del_entorno(entorno: str, conexion: Any = None) -> None:
    """BIGDATA_DEV en dev, BIGDATA_PROD en prod; ACCOUNTADMIN se rechaza."""
    raise NotImplementedError("P3: exigir_rol_del_entorno")


def vaciar_control(entorno: str, conexion: Any = None) -> int:
    """DELETE solo de CONTROL_<ENTORNO>.WATERMARK (lo usa el reseteo). Devuelve las borradas."""
    raise NotImplementedError("P3: vaciar_control")


class ControlEnMemoria:
    """Misma interfaz que la tabla de control real, pero en memoria: para pruebas."""

    def __init__(self) -> None:
        raise NotImplementedError("P3: ControlEnMemoria")


def instalar_backend(backend: Any) -> None:
    """Solo pruebas: las funciones de este módulo usan `backend` en lugar de Snowflake.

    instalar_backend(None) lo quita y vuelve a Snowflake.
    """
    raise NotImplementedError("P3: instalar_backend")
