"""Muestra de desarrollo: pocas filas de todos los meses para validar la lógica en local.

- main (--step muestra, env dev/prod en Glue): lee el lote más reciente de bronze, toma una
  muestra aleatoria y reproducible (~objetivo_filas en total, repartida en todos los meses) y la
  escribe en muestra.destino con el mismo layout que bronze: <fuente>/mes=.../lote=<id>/, con
  el mismo id de lote y las columnas de metadatos (_hash_fila...) intactas. Zonas y clima se
  copian completos (son pequeños). La muestra no incluye _crudo/: no hace falta para leerla.
- sincronizar (env local): copia la muestra a rutas.bronze si todavía no está en el disco del
  Code Editor, o si es de la versión anterior (sin lotes). La busca primero en el bucket propio
  (s3://<lake>/<muestra.sincronizar_desde>) y, si ahí no hay lotes completos, en el bucket
  público del curso (muestra.publica), con acceso anónimo.
- aplicar_muestra: recorte adicional (--limite o muestra.max_rows) para pruebas rapidísimas.
  Toda fuente nueva debe pasar por aquí en lugar de usar un .limit() fijo en la transformación.
"""

from __future__ import annotations

import logging
import os
import shutil
from pathlib import Path
from typing import Any

from pyspark.sql import DataFrame

from pipeline import io

log = logging.getLogger(__name__)

SEMILLA = 42


class MuestraError(RuntimeError):
    """La muestra no está disponible."""


def limite_efectivo(cfg: dict, limite: int | None = None) -> int | None:
    """--limite manda sobre muestra.max_rows; None o 0 = sin recorte."""
    n = limite if limite is not None else (cfg.get("muestra") or {}).get("max_rows")
    return int(n) if n else None


def aplicar_muestra(df: DataFrame, cfg: dict, limite: int | None = None) -> DataFrame:
    n = limite_efectivo(cfg, limite)
    if n:
        log.info("Muestra: se usan como máximo %d filas", n)
        return df.limit(n)
    return df


def copiar_lote(spark: Any, base: str, destino: str, fuente: str, mes: str | None) -> None:
    """Copia completo el lote más reciente de una fuente pequeña (zonas o clima) a la muestra."""
    id_lote = io.lote_mas_reciente(base, fuente, mes)
    lote = spark.read.parquet(io.dir_lote(base, fuente, id_lote, mes))
    io.escribir_lote(lote, io.dir_lote(destino, fuente, id_lote, mes), archivos=1)


def muestrear_viajes(spark: Any, base: str, destino: str, mes: str, fraccion: float) -> None:
    """Escribe una fracción aleatoria (semilla fija) del lote más reciente de viajes del mes."""
    id_lote = io.lote_mas_reciente(base, io.VIAJES, mes)
    lote = spark.read.parquet(io.dir_lote(base, io.VIAJES, id_lote, mes))
    muestra = lote.sample(withReplacement=False, fraction=fraccion, seed=SEMILLA)
    io.escribir_lote(muestra, io.dir_lote(destino, io.VIAJES, id_lote, mes), archivos=1)


def main(spark: Any, cfg: dict, args: Any) -> None:
    destino = (cfg.get("muestra") or {}).get("destino")
    if not destino:
        raise MuestraError(f"El entorno '{cfg['entorno']}' no define muestra.destino")
    objetivo = int(cfg["muestra"].get("objetivo_filas") or 100_000)
    base = cfg["rutas"]["bronze"]

    total = io.leer_viajes(spark, base, args.meses).count()
    fraccion = min(1.0, objetivo / total) if total else 1.0
    log.info("Muestra: %d filas en bronze, fracción %.6f (~%d filas)", total, fraccion, objetivo)

    # Se borra lo anterior de estos meses para que la muestra no mezcle lotes viejos con el nuevo
    # (y para limpiar la muestra de la versión anterior, que no tenía carpetas lote=).
    io.borrar_particiones(io.dir_fuente(destino, io.VIAJES), [f"mes={m}/" for m in args.meses])
    io.borrar_particiones(io.dir_fuente(destino, io.CLIMA), [f"mes={m}/" for m in args.meses])
    io.borrar_particiones(destino, [f"{io.ZONAS}/"])

    for mes in args.meses:
        muestrear_viajes(spark, base, destino, mes, fraccion)
        copiar_lote(spark, base, destino, io.CLIMA, mes)
    copiar_lote(spark, base, destino, io.ZONAS, None)
    log.info("Muestra escrita en %s", destino)


def muestra_local_vigente(local: Path) -> bool:
    """True si la muestra del disco tiene al menos un lote de zonas (layout con metadatos)."""
    carpeta_zonas = local / io.ZONAS
    if not carpeta_zonas.is_dir():
        return False
    for hijo in carpeta_zonas.iterdir():
        if hijo.name.startswith(io.PREFIJO_LOTE):
            return True
    return False


def crear_cliente_s3(anonimo: bool, region: str | None = None) -> Any:
    """Cliente de S3. Anónimo = sin firmar las peticiones (sirve para el bucket público)."""
    import boto3  # imports perezosos: solo se necesitan al sincronizar
    from botocore import UNSIGNED
    from botocore.config import Config

    if anonimo:
        return boto3.client("s3", region_name=region, config=Config(signature_version=UNSIGNED))
    return boto3.client("s3")


def listar_claves(s3: Any, bucket: str, prefijo: str) -> list[str]:
    """Claves de todos los archivos bajo s3://bucket/prefijo/ (sin las 'carpetas' vacías)."""
    claves = []
    paginas = s3.get_paginator("list_objects_v2").paginate(Bucket=bucket, Prefix=f"{prefijo}/")
    for pagina in paginas:
        for objeto in pagina.get("Contents", []):
            if not objeto["Key"].endswith("/"):
                claves.append(objeto["Key"])
    return claves


def tiene_lote_completo(claves: list[str]) -> bool:
    """True si alguna clave es un marcador _LOTE_COMPLETO: es lo que distingue el formato nuevo."""
    for clave in claves:
        if clave.endswith(f"/{io.MARCA_LOTE_COMPLETO}"):
            return True
    return False


def buscar_muestra(origenes: list[dict]) -> dict | None:
    """Devuelve el primer origen que tiene una muestra con el formato nuevo, o None.

    Cada origen es un dict con: nombre (para el log), bucket, prefijo y cliente (de S3).
    Si un origen falla (sin permisos, sin red, bucket inexistente) se registra y se sigue
    con el siguiente: el bucket público es el plan B.
    """
    from botocore.exceptions import BotoCoreError, ClientError

    for origen in origenes:
        destino_s3 = f"s3://{origen['bucket']}/{origen['prefijo']}"
        try:
            claves = listar_claves(origen["cliente"], origen["bucket"], origen["prefijo"])
        except (BotoCoreError, ClientError) as error:
            log.warning(
                "No se pudo leer la muestra de %s (%s): %s", origen["nombre"], destino_s3, error
            )
            continue
        if tiene_lote_completo(claves):
            origen["claves"] = claves
            return origen
        log.info(
            "En %s (%s) no hay lotes completos; se prueba con el siguiente",
            origen["nombre"],
            destino_s3,
        )
    return None


def descargar_muestra(origen: dict, local: Path) -> None:
    """Descarga la muestra a una carpeta temporal y recién al final reemplaza la de `local`.

    Así, si la descarga se corta a la mitad, no queda en el disco una muestra incompleta que
    después parezca vigente.
    """
    prefijo = origen["prefijo"]
    temporal = local.with_name(local.name + ".descarga")
    if temporal.exists():
        shutil.rmtree(temporal)
    for clave in origen["claves"]:
        destino = temporal / clave[len(prefijo) + 1 :]
        destino.parent.mkdir(parents=True, exist_ok=True)
        origen["cliente"].download_file(origen["bucket"], clave, str(destino))
    if local.exists():
        # Muestra de la versión anterior (sin lotes): se borra justo antes de dejar la nueva.
        log.info("La muestra de %s es de la versión anterior; se reemplaza", local)
        shutil.rmtree(local)
    temporal.rename(local)


def armar_origenes(cfg: dict) -> list[dict]:
    """Orden de búsqueda: primero el bucket propio (si hay LAKE_BUCKET) y luego el público."""
    config_muestra = cfg.get("muestra") or {}
    origenes = []

    bucket_propio = os.environ.get("LAKE_BUCKET")
    prefijo_propio = config_muestra.get("sincronizar_desde")
    if bucket_propio and prefijo_propio:
        origenes.append(
            {
                "nombre": "tu bucket",
                "bucket": bucket_propio,
                "prefijo": prefijo_propio,
                "cliente": crear_cliente_s3(anonimo=False),
            }
        )
    else:
        log.info("No hay LAKE_BUCKET: se salta tu bucket y se va al público del curso")

    publica = config_muestra.get("publica")
    if publica:
        origenes.append(
            {
                "nombre": "el bucket público del curso",
                "bucket": publica["bucket"],
                "prefijo": publica["prefijo"],
                "cliente": crear_cliente_s3(anonimo=True, region=publica.get("region")),
            }
        )
    return origenes


def sincronizar(cfg: dict) -> None:
    """Deja la muestra en rutas.bronze (local): del bucket propio o, si no, del público."""
    local = Path(cfg["rutas"]["bronze"])
    if not (cfg.get("muestra") or {}).get("sincronizar_desde") or muestra_local_vigente(local):
        return

    origen = buscar_muestra(armar_origenes(cfg))
    if origen is None:
        raise MuestraError(
            f"No hay muestra en {local} y no se encontró una con el formato nuevo ni en tu "
            "bucket ni en el bucket público del curso. Revisa tu conexión a internet y "
            "vuelve a correr; si sigue igual, avisa al instructor."
        )

    descargar_muestra(origen, local)
    log.info(
        "Muestra descargada (origen: %s, s3://%s/%s) a %s (%d archivos)",
        origen["nombre"],
        origen["bucket"],
        origen["prefijo"],
        local,
        len(origen["claves"]),
    )
