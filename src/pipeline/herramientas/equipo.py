"""Ayudas del cuaderno de la clase 7 (PAQUETE P4: aquí solo está el contrato)."""

from __future__ import annotations


def usar_mis_funciones(**funciones) -> None:
    """Registra en pipeline.bronze y pipeline.silver, solo en este proceso, tus funciones.

    Nombres válidos: agregar_metadatos, debe_ingestar, registrar_ingesta, deduplicar. Otro nombre
    es un error. Con cómputo glue_* falla: tus funciones del cuaderno no viajan a Glue, cópialas
    a bronze.py.
    """
    raise NotImplementedError("P4: usar_mis_funciones")


def probar_mis_funciones(**funciones) -> int:
    """Corre en este proceso las MISMAS pruebas de make test con tus funciones.

    Usa tests/test_equipo_bronze.py y tests/test_equipo_silver.py, imprime PENDIENTE/OK como
    make test y devuelve el código de pytest.
    """
    raise NotImplementedError("P4: probar_mis_funciones")
