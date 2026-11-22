"""Athena, solo el catálogo de Glue (PAQUETE P3: aquí solo está el contrato). No escanea S3."""

from __future__ import annotations

from typing import Any


def nombre_tabla_athena(entorno: str, capa: str, tabla: str) -> str:
    """'<entorno>_<capa>_<tabla>', por ejemplo 'dev_silver_fhvhv' (base bigdata_lake)."""
    raise NotImplementedError("P3: nombre_tabla_athena")


def esquema_de_athena(tabla: str, base: str = "bigdata_lake") -> dict[str, str] | None:
    """{columna: tipo} de la tabla en el catálogo; None si no existe o no hay permiso (avisa)."""
    raise NotImplementedError("P3: esquema_de_athena")


def verificar_esquema_con_athena(
    tabla_athena: str, tabla_snowflake: str, conexion: Any = None
) -> None:
    """Compara el esquema de S3 (Athena) con el de la tabla de Snowflake.

    Lanza ColumnasDistintas si no coinciden. Si Athena no responde, avisa y sigue.
    """
    raise NotImplementedError("P3: verificar_esquema_con_athena")
