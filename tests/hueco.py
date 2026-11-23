"""Ayudas de las pruebas del equipo: saber si una función sigue pendiente y armar una corrida.

Las funciones del equipo (agregar_metadatos, deduplicar...) vienen en bronze.py y silver.py con la
marca `# PENDIENTE(equipo)` en el cuerpo. Mientras la marca siga ahí, su prueba sale OMITIDA con el
motivo «PENDIENTE: ...» (con `pytest -rs` se ve el motivo). Cuando escribes la función y borras la
marca, la misma prueba pasa a correr de verdad: OK si está bien, FALLA si no.

También sirve con las funciones del cuaderno: `probar_mis_funciones(...)` las pone en
pipeline.bronze / pipeline.silver antes de correr estas pruebas, así que aquí siempre se busca la
función en el módulo.
"""

from __future__ import annotations

import inspect
from datetime import UTC, datetime

import pytest

from pipeline.herramientas.corrida import Corrida

MARCADOR = "# PENDIENTE(equipo)"
MES = "2024-01"
ENTORNO = "dev"


def esta_pendiente(funcion) -> bool:
    """True si el cuerpo de la función todavía trae la marca # PENDIENTE(equipo).

    Si no se puede leer el código fuente (una función creada al vuelo), se supone que ya está hecha.
    """
    try:
        codigo = inspect.getsource(funcion)
    except (OSError, TypeError):
        return False
    return MARCADOR in codigo


def saltar_si_pendiente(funcion, que_falta: str) -> None:
    """Omite la prueba con «PENDIENTE: <que_falta>» si la función todavía está pendiente."""
    if esta_pendiente(funcion):
        pytest.skip(f"PENDIENTE: {que_falta}")


def corrida_a_mano(reprocesar: bool = False, mes: str = MES) -> Corrida:
    """Una Corrida de dev armada con la mano, sin leer pipeline.yaml ni el entorno."""
    ahora = datetime(2026, 11, 23, 15, 0, 0, tzinfo=UTC)
    return Corrida(
        entorno=ENTORNO,
        computo="code_editor",
        meses=(mes,),
        limite="1000",
        reprocesar=reprocesar,
        id_lote="20261123T150000Z_abc123",
        fecha_ingesta=ahora,
    )
