"""Leer y escribir las capas del lake (PAQUETE P2: aquí solo está el contrato).

Este módulo trae pyspark: la fachada pipeline.herramientas lo importa solo cuando alguien pide
una de estas funciones.
"""

from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from pyspark.sql import Column, DataFrame, SparkSession

# Columnas que bronze agrega a las originales, en este orden.
COLUMNAS_METADATOS = ["_fecha_ingesta", "_id_lote", "_hash_fila", "_fuente", "_archivo_origen"]
# Texto con el que el hash representa un valor nulo, y separador entre columnas.
MARCADOR_NULO = "<nulo>"
SEPARADOR_HASH = "||"


def leer_crudo(
    spark: SparkSession, entorno: str, tabla: str, mes: str | None = None, limite: int | None = None
) -> DataFrame:
    """Lee el archivo crudo de la tabla.

    fhvhv: Parquet; taxi_zones: CSV todo texto; clima: JSON ya en una fila por día. `limite` es
    int|None (Corrida.limite_filas) y se aplica DETERMINISTA: df.coalesce(1).limit(n) (las mismas
    n primeras filas del archivo en cada corrida).
    """
    raise NotImplementedError("P2: leer_crudo")


def escribir_bronze(df: DataFrame, entorno: str, tabla: str, mes: str, id_lote: str) -> int:
    """Escribe un lote nuevo en bronze (+ _LOTE_COMPLETO). Devuelve las filas escritas.

    Bronze solo agrega: cada ingesta es un lote nuevo. Cuenta leyendo de vuelta (por el pie de
    los Parquet), sin recalcular el DataFrame.
    """
    raise NotImplementedError("P2: escribir_bronze")


def leer_capa(
    spark: SparkSession,
    entorno: str,
    capa: str,
    tabla: str,
    mes: str | None = None,
    lotes: str = "todos",
) -> DataFrame:
    """Lee una tabla de una capa.

    bronze: 'todos' los lotes completos o 'ultimo'; silver y gold: el mes.
    """
    raise NotImplementedError("P2: leer_capa")


def escribir_capa(
    df: DataFrame, entorno: str, capa: str, tabla: str, mes: str | None = None
) -> int:
    """Reemplaza mes=<mes>/ de la capa (borra y escribe). Devuelve las filas escritas."""
    raise NotImplementedError("P2: escribir_capa")


def mover_entre_capas(
    spark: SparkSession,
    entorno: str,
    mes: str | None,
    tabla: str,
    de: str,
    a: str,
    transformar=None,
) -> tuple[int, int]:
    """Lee la tabla de la capa `de`, aplica `transformar(df)` (si hay) y la escribe en `a`.

    Devuelve (leídas, escritas).
    """
    raise NotImplementedError("P2: mover_entre_capas")


def nuevo_id_lote(ahora: datetime) -> str:
    """Id de un lote: fecha UTC y 6 hex al azar (20260115T143005Z_a3f9c1)."""
    raise NotImplementedError("P2: nuevo_id_lote")


def hash_fila(columnas: list[str]) -> Column:
    """SHA-256 (hex) de la fila: columnas a texto, nulo = MARCADOR_NULO, unidas con '||'."""
    raise NotImplementedError("P2: hash_fila")
