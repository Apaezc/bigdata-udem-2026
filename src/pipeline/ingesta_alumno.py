"""Tu ingesta a bronze: aquí pegas las cuatro funciones que escribiste en el lab de la clase 5.

QUÉ HACER (una sola vez, antes de la clase 6)
---------------------------------------------
Abre tu notebook `curso/clase05/03_lab.ipynb` (el que resolviste, no la solución) y copia estas
cuatro funciones, completas (desde `def` hasta su `return`), en lugar de las funciones vacías
de este archivo:

    Celda 9   calcular_hash_fila(columnas)
    Celda 16  ingestar_clima(mes, reprocesar, base_bronze, tabla, obtener)
    Celda 18  ingestar_zonas(reprocesar, base_bronze, tabla, obtener)
    Celda 20  ingestar_viajes(mes, reprocesar, base_bronze, tabla, obtener, limite_filas)

Pasos:
  1. Borra la función vacía (la que dice `...  # PEGA AQUÍ TU FUNCIÓN DEL LAB`).
  2. Pega en su lugar la función completa de tu notebook, sin cambiar su nombre ni sus
     parámetros.
  3. Guarda y corre `make test`. Mientras falte alguna función, su prueba dice PENDIENTE
     y se omite; cuando la pegas, la prueba corre de verdad (sin red y sin tocar Snowflake).

No copies las celdas de pruebas (`prueba_e1`, `verificar`...), ni `agregar_metadatos`,
`ruta_crudo_lote` o `url_viajes`: esas ya están resueltas más abajo, igual que en el lab.

QUÉ YA VIENE RESUELTO (lo que el lab te daba hecho)
---------------------------------------------------
Tus funciones usan estos nombres, y todos existen en este archivo, con el mismo significado
que en el lab: `spark`, `BRONZE_ALUMNO`, `bronze_pipeline`, `pio`, `watermark`,
`consultar_watermark`, `registrar_watermark`, `MES_SIN_MES`, `MARCADOR_NULO`, `SEPARADOR_HASH`,
`COLUMNAS_METADATOS`, `F`, `Column`, `json`, `datetime`, `timezone`, `url_viajes`,
`ruta_crudo_lote` y `agregar_metadatos` (esta última llama a TU `calcular_hash_fila`).

Quién usa este archivo: el DAG `ingesta_mensual` (airflow/dags/ingesta_mensual.py) llama a tus
tres funciones de ingesta con `mes` y `reprocesar`. Por eso conviene probarlas aquí primero.
"""

from __future__ import annotations

import contextlib
import hashlib
import inspect
import json
import os
import re
import shutil
import tempfile
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

from pyspark.sql import Column, DataFrame, Window
from pyspark.sql import functions as F

from pipeline import (
    bronze as bronze_pipeline,
)  # URLs de las fuentes y piezas de ingesta del pipeline
from pipeline import io as pio  # rutas del lake: crudo, lotes y marcador de lote completo
from pipeline import watermark  # la tabla de control, ya hecha
from pipeline.bronze import COLUMNAS_METADATOS, MARCADOR_NULO, SEPARADOR_HASH
from pipeline.watermark import (
    MES_SIN_MES,
    borrar_registros_de_prueba,
    consultar_watermark,
    registrar_watermark,
)

__all__ = [
    "BRONZE_ALUMNO",
    "COLUMNAS_METADATOS",
    "MARCADOR_NULO",
    "MES_SIN_MES",
    "SEPARADOR_HASH",
    "Column",
    "DataFrame",
    "F",
    "Path",
    "Window",
    "agregar_metadatos",
    "borrar_registros_de_prueba",
    "bronze_pipeline",
    "calcular_hash_fila",
    "consultar_watermark",
    "contextlib",
    "datetime",
    "esta_pendiente",
    "hashlib",
    "ingestar_clima",
    "ingestar_viajes",
    "ingestar_zonas",
    "json",
    "os",
    "pio",
    "re",
    "registrar_watermark",
    "ruta_crudo_lote",
    "shutil",
    "spark",
    "tempfile",
    "time",
    "timezone",
    "url_viajes",
    "urllib",
    "watermark",
]

# --- infraestructura que el lab daba resuelta -------------------------------------------------

# Carpeta de datos de la clase 5 y tu bronze de práctica (la misma del lab).
DATOS = Path(os.environ.get("CLASE05_DATOS", Path.home() / "datos_clase05"))
BRONZE_ALUMNO = str(DATOS / "bronze_alumno")

# Conexión de Snowflake (~/.snowflake/connections.toml) que usa la tabla de control. Es la misma
# del lab: «default» salvo que ya hayas fijado WATERMARK_CONNECTION.
os.environ.setdefault("WATERMARK_CONNECTION", "default")


class _SparkPerezoso:
    """Hace de `spark`: la sesión de Spark se enciende la primera vez que alguien la usa.

    En el lab, `spark` era una variable que ya estaba encendida. Aquí se enciende sola con la
    misma configuración del pipeline (`get_spark("local")`), y solo si hace falta: importar este
    módulo, o correr una prueba que se omite, no arranca Java.
    """

    def __init__(self) -> None:
        self._sesion = None

    def __getattr__(self, nombre: str):
        if self._sesion is None:
            from pipeline.engine import get_spark  # import tardío: arrancar Spark es lo caro

            self._sesion = get_spark("local")
        return getattr(self._sesion, nombre)


spark = _SparkPerezoso()


def url_viajes(mes):
    """Ya resuelta: URL del archivo Parquet de viajes del mes (AAAA-MM)."""
    return bronze_pipeline.URL_VIAJES.format(mes=mes)


def ruta_crudo_lote(base, tabla, id_lote, nombre, mes=None):
    """Ya resuelta: ruta del crudo de un lote, <base>/_crudo/<tabla>/.../lote=<id>/<nombre>."""
    carpeta_de_la_tabla = pio.dir_crudo(base, tabla, mes)
    return pio.unir(carpeta_de_la_tabla, f"lote={id_lote}", nombre)


def agregar_metadatos(df, fuente, archivo_origen, id_lote, fecha_ingesta):
    """Ya resuelta: agrega _hash_fila (tu función) y los otros cuatro metadatos."""
    originales = df.columns
    con_huella = df.withColumn("_hash_fila", calcular_hash_fila(originales))
    con_metadatos = (
        con_huella.withColumn("_fecha_ingesta", F.lit(fecha_ingesta).cast("timestamp"))
        .withColumn("_id_lote", F.lit(id_lote))
        .withColumn("_fuente", F.lit(fuente))
        .withColumn("_archivo_origen", F.lit(archivo_origen))
    )
    # Primero las columnas originales y después los metadatos, siempre en el mismo orden.
    return con_metadatos.select(*originales, *COLUMNAS_METADATOS)


# --- las cuatro funciones que pegas tú ---------------------------------------------------------

MARCA_PENDIENTE = "PEGA AQUÍ TU FUNCIÓN DEL LAB"


def esta_pendiente(funcion) -> bool:
    """Verdadero si la función sigue siendo la vacía de este archivo (todavía no la pegaste)."""
    try:
        fuente = inspect.getsource(funcion)
    except (OSError, TypeError):
        return False
    return MARCA_PENDIENTE in fuente


def calcular_hash_fila(columnas: list[str]) -> Column:
    """SHA-256 de la fila: textos, nulo como MARCADOR_NULO, unidos con SEPARADOR_HASH."""
    ...  # PEGA AQUÍ TU FUNCIÓN DEL LAB (Celda 9 del notebook 03_lab)


def ingestar_clima(
    mes,
    reprocesar=False,
    base_bronze=BRONZE_ALUMNO,
    tabla=pio.CLIMA,
    obtener=bronze_pipeline.descargar,
):
    """Ingesta el clima de `mes` a bronze. Devuelve la carpeta del lote, o None si no hizo nada."""
    ...  # PEGA AQUÍ TU FUNCIÓN DEL LAB (Celda 16 del notebook 03_lab)


def ingestar_zonas(
    reprocesar=False,
    base_bronze=BRONZE_ALUMNO,
    tabla=pio.ZONAS,
    obtener=bronze_pipeline.descargar,
):
    """Ingesta las zonas de taxi (sin mes). Devuelve la carpeta del lote, o None si no hizo nada."""
    ...  # PEGA AQUÍ TU FUNCIÓN DEL LAB (Celda 18 del notebook 03_lab)


def ingestar_viajes(
    mes,
    reprocesar=False,
    base_bronze=BRONZE_ALUMNO,
    tabla=pio.VIAJES,
    obtener=bronze_pipeline.descargar,
    limite_filas=None,
):
    """Ingesta los viajes de `mes`. Devuelve la carpeta del lote, o None si no hizo nada."""
    ...  # PEGA AQUÍ TU FUNCIÓN DEL LAB (Celda 20 del notebook 03_lab)
