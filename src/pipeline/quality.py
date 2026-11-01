"""Chequeos de calidad de datos: no vacío, llaves no nulas, rangos y clave única.

Todos los chequeos se resuelven en una sola pasada (un solo agg). Si algo falla se lanza
QualityError con un mensaje que indica capa, columna y cantidad de filas afectadas.
"""

from __future__ import annotations

import logging
import operator
from collections.abc import Iterable, Mapping
from functools import reduce

from pyspark.sql import DataFrame
from pyspark.sql import functions as F

log = logging.getLogger(__name__)


class QualityError(ValueError):
    """Un chequeo de calidad no se cumple."""


def validar(
    df: DataFrame,
    *,
    nombre: str,
    no_vacio: bool = True,
    llaves: Iterable[str] = (),
    rangos: Mapping[str, tuple[float | None, float | None]] | None = None,
    clave_unica: Iterable[str] = (),
) -> dict[str, int]:
    """Valida df. rangos: {columna: (minimo, maximo)} inclusivos; None = sin límite.

    Los nulos no cuentan como fuera de rango (para eso están las llaves).
    Devuelve el total de filas si todo pasa.
    """
    llaves = tuple(llaves)
    rangos = dict(rangos or {})
    clave_unica = tuple(clave_unica)

    aggs = [F.count(F.lit(1)).alias("total")]
    for c in llaves:
        aggs.append(F.count(F.when(F.col(c).isNull(), 1)).alias(f"nulos__{c}"))
    for c, (minimo, maximo) in rangos.items():
        fuera = F.lit(False)
        if minimo is not None:
            fuera = fuera | (F.col(c) < minimo)
        if maximo is not None:
            fuera = fuera | (F.col(c) > maximo)
        aggs.append(F.count(F.when(fuera, 1)).alias(f"fuera__{c}"))
    if clave_unica:
        con_clave = reduce(operator.and_, [F.col(c).isNotNull() for c in clave_unica])
        aggs.append(F.count(F.when(con_clave, 1)).alias("con_clave"))
        aggs.append(F.countDistinct(*clave_unica).alias("claves_distintas"))

    fila = df.agg(*aggs).first()
    total = fila["total"]

    if no_vacio and total == 0:
        raise QualityError(f"[{nombre}] el conjunto está vacío (0 filas)")
    for c in llaves:
        n = fila[f"nulos__{c}"]
        if n:
            raise QualityError(f"[{nombre}] la llave '{c}' tiene {n} nulos de {total} filas")
    for c, (minimo, maximo) in rangos.items():
        n = fila[f"fuera__{c}"]
        if n:
            raise QualityError(
                f"[{nombre}] '{c}' tiene {n} valores fuera de rango "
                f"[{minimo}, {maximo}] (None = sin límite)"
            )
    if clave_unica:
        duplicados = fila["con_clave"] - fila["claves_distintas"]
        if duplicados:
            raise QualityError(
                f"[{nombre}] la clave {list(clave_unica)} no es única: "
                f"{duplicados} filas duplicadas"
            )

    log.info("Calidad OK [%s]: %d filas", nombre, total)
    return {"total": total}
