"""Archivos y carpetas del lake: leer, escribir, mover, listar y borrar en s3:// o file://.

Cada función que escribe o borra dice en voz alta la ruta completa (`anunciar`): fíjate en la
salida para saber dónde estás. Las pruebas usan PIPELINE_RAIZ_LAKE=file://... y no tocan AWS:
por eso todas las funciones entienden las rutas file:// además de s3://.

Un lote de bronze es una carpeta `lote=<id>/` con los Parquet; se da por completo cuando tiene el
marcador `_LOTE_COMPLETO`, que `escribir_lote` publica solo si la escritura terminó bien.

Este archivo no importa pyspark al cargarse: la VM de Airflow no lo tiene.
"""

from __future__ import annotations

import logging
import shutil
import tempfile
from pathlib import Path
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from pyspark.sql import DataFrame

log = logging.getLogger(__name__)

PREFIJO_FILE = "file://"
PREFIJO_LOTE = "lote="
# Marcador propio: se publica cuando el lote ya se escribió completo. No se usa _SUCCESS porque
# Glue no siempre lo escribe en S3.
MARCA_LOTE_COMPLETO = "_LOTE_COMPLETO"
TOPE_POR_LLAMADA = 1000  # delete_objects acepta hasta 1000 claves


class LoteNoEncontrado(RuntimeError):
    """No hay ningún lote completo de bronze para la fuente (y el mes) pedidos."""


def anunciar(verbo: str, ruta: str, detalle: str = "") -> None:
    """Dice en voz alta qué ruta completa se lee, se escribe o se borra.

    Va al log. Si nadie configuró el logging (lo normal en un notebook), se imprime para que
    el estudiante lo vea en la salida de la celda.
    """
    mensaje = f"{verbo:<8} {ruta}"
    if detalle:
        mensaje += f"  ({detalle})"
    log.info(mensaje)
    if not log.hasHandlers():
        print(mensaje)


def unir(base: str, *partes: str) -> str:
    return "/".join([base.rstrip("/"), *partes])


def a_ruta_local(ruta: str) -> Path:
    """Ruta de disco de algo que no es s3://: quita el prefijo file:// si lo trae."""
    if ruta.startswith(PREFIJO_FILE):
        return Path(ruta[len(PREFIJO_FILE) :])
    return Path(ruta)


# --- listar y preguntar -----------------------------------------------------------------------


def listar_subcarpetas(ruta: str) -> list[str]:
    """Nombres de las carpetas que cuelgan directamente de `ruta` (local o s3://)."""
    nombres = []
    if ruta.startswith("s3://"):
        import boto3

        bucket, _, prefijo = ruta[len("s3://") :].partition("/")
        prefijo = prefijo.rstrip("/") + "/"
        paginas = (
            boto3.client("s3")
            .get_paginator("list_objects_v2")
            .paginate(Bucket=bucket, Prefix=prefijo, Delimiter="/")
        )
        for pagina in paginas:
            for carpeta in pagina.get("CommonPrefixes", []):
                nombres.append(carpeta["Prefix"][len(prefijo) :].rstrip("/"))
        return nombres
    raiz = a_ruta_local(ruta)
    if not raiz.is_dir():
        return nombres
    for hijo in raiz.iterdir():
        if hijo.is_dir():
            nombres.append(hijo.name)
    return nombres


def existe(ruta: str) -> bool:
    if ruta.startswith("s3://"):
        import boto3  # import perezoso: solo se necesita con S3
        from botocore.exceptions import ClientError

        bucket, _, key = ruta[len("s3://") :].partition("/")
        try:
            boto3.client("s3").head_object(Bucket=bucket, Key=key)
        except ClientError:
            return False
        return True
    return a_ruta_local(ruta).exists()


# --- escribir ---------------------------------------------------------------------------------


def publicar(local: Path, destino: str) -> None:
    """Copia un archivo local a destino (ruta local o s3://)."""
    anunciar("SUBE", destino, f"desde {local}")
    if destino.startswith("s3://"):
        import boto3

        bucket, _, key = destino[len("s3://") :].partition("/")
        boto3.client("s3").upload_file(str(local), bucket, key)
    else:
        destino_local = a_ruta_local(destino)
        destino_local.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(local, destino_local)


def copiar(origen: str, destino: str) -> None:
    """Copia un archivo entre rutas (s3:// -> s3:// del lado del servidor, o locales)."""
    anunciar("COPIA", destino, f"desde {origen}")
    if origen.startswith("s3://") and destino.startswith("s3://"):
        import boto3

        ob, _, ok = origen[len("s3://") :].partition("/")
        db, _, dk = destino[len("s3://") :].partition("/")
        boto3.client("s3").copy({"Bucket": ob, "Key": ok}, db, dk)
    else:
        destino_local = a_ruta_local(destino)
        destino_local.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(a_ruta_local(origen), destino_local)


def mover(origen: str, destino: str) -> None:
    """Mueve un archivo: lo copia y solo borra el original si la copia terminó bien."""
    copiar(origen, destino)
    borrar(origen)


def marcar_lote_completo(carpeta_lote: str) -> None:
    """Publica el marcador que dice que el lote se escribió completo (local o s3://)."""
    with tempfile.TemporaryDirectory(prefix="marca-") as tmp:
        marca = Path(tmp) / MARCA_LOTE_COMPLETO
        marca.write_text("lote completo\n", encoding="utf-8")
        publicar(marca, unir(carpeta_lote, MARCA_LOTE_COMPLETO))


def escribir_lote(df: DataFrame, carpeta_lote: str, archivos: int | None = None) -> None:
    """Escribe un lote en Parquet y, solo si la escritura terminó bien, publica el marcador.

    Con `archivos` el lote se junta en esa cantidad de archivos (fuentes pequeñas).
    """
    salida = df
    if archivos:
        salida = df.coalesce(archivos)
    anunciar("ESCRIBE", carpeta_lote, "lote en Parquet")
    salida.write.mode("overwrite").parquet(carpeta_lote)
    marcar_lote_completo(carpeta_lote)


# --- borrar -----------------------------------------------------------------------------------


def borrar(ruta: str) -> None:
    """Borra un archivo (local o s3://)."""
    anunciar("BORRA", ruta)
    if ruta.startswith("s3://"):
        import boto3

        bucket, _, key = ruta[len("s3://") :].partition("/")
        boto3.client("s3").delete_object(Bucket=bucket, Key=key)
    else:
        a_ruta_local(ruta).unlink()


def borrar_claves(s3: Any, bucket: str, claves: list[str]) -> int:
    """Borra las claves de S3 por lotes de 1000 y devuelve cuántas borró.

    Es el único bucle de borrado del repo. Si S3 reporta un error, se detiene.
    """
    borradas = 0
    for inicio in range(0, len(claves), TOPE_POR_LLAMADA):
        lote = claves[inicio : inicio + TOPE_POR_LLAMADA]
        respuesta = s3.delete_objects(
            Bucket=bucket,
            Delete={"Objects": [{"Key": clave} for clave in lote], "Quiet": True},
        )
        errores = respuesta.get("Errors") or []
        if errores:
            primero = errores[0]
            raise RuntimeError(
                f"S3 no pudo borrar {len(errores)} objeto(s); el primero: "
                f"{primero.get('Key')} ({primero.get('Code')}: {primero.get('Message')}). "
                "Me detengo: revisa los permisos del rol y vuelve a lanzar."
            )
        borradas += len(lote)
    return borradas


def borrar_carpeta(ruta: str) -> None:
    """Borra una carpeta completa y todo lo que tiene adentro (s3:// o file://).

    Es lo que usa escribir_capa para reemplazar un mes: primero se borra la carpeta del mes y
    luego se escribe, así no quedan archivos viejos mezclados con los nuevos.
    """
    anunciar("BORRA", unir(ruta, "*"), "carpeta completa")
    if ruta.startswith("s3://"):
        import boto3

        bucket, _, prefijo = ruta[len("s3://") :].partition("/")
        s3 = boto3.client("s3")
        claves = []
        paginas = s3.get_paginator("list_objects_v2").paginate(
            Bucket=bucket, Prefix=prefijo.rstrip("/") + "/"
        )
        for pagina in paginas:
            for objeto in pagina.get("Contents", []):
                claves.append(objeto["Key"])
        borrar_claves(s3, bucket, claves)
        return
    carpeta = a_ruta_local(ruta)
    if carpeta.is_dir():
        shutil.rmtree(carpeta)
