"""Borrar un entorno completo (PAQUETE P5: aquí solo está el contrato)."""

from __future__ import annotations

from typing import Any


def borrar_capas_s3(entorno: str, solo_listar: bool = True, conservar_crudo: bool = False) -> dict:
    """Borra (o solo lista) todo lo que hay bajo s3://<lake>/<entorno>/. Devuelve el recuento."""
    raise NotImplementedError("P5: borrar_capas_s3")


def borrar_tablas_snowflake(
    entorno: str, solo_listar: bool = True, conexion: Any = None
) -> list[str]:
    """Borra (o solo lista) las tablas y vistas de BIGDATA.<ENTORNO>. Devuelve sus nombres."""
    raise NotImplementedError("P5: borrar_tablas_snowflake")
