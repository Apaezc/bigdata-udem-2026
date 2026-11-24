"""Borrar un entorno completo: capas de S3, tabla de control y esquema de Snowflake.

Lo usa el DAG `resetear_entorno` (uno en el Airflow del Code Editor, que borra dev, y otro en la
VM, que borra prod). Cada función toca UN solo entorno y todas arrancan en modo `solo_listar`:
cuentan y listan, y no borran nada hasta que se pide.

Qué borra (y qué no):
- S3: todo lo que hay bajo s3://<lake>/<entorno>/ (bronze con _crudo, silver, gold y los
  marcadores *_$folder$). Con `conservar_crudo=True` deja bronze/_crudo/. No toca el otro
  entorno ni code/, dags/, logs/, tmp/.
- Tabla de control: todos los registros de BIGDATA.CONTROL_<ENTORNO>.WATERMARK (se cuenta con
  `contar_control`, aquí, y se borra con `vaciar_control`, de control.py). No toca
  CONTROL_<otro> ni la tabla CONTROL de la clase 5.
- Snowflake: las tablas y vistas de BIGDATA.<ENTORNO>. No toca el stage LAKE_GOLD ni el formato
  PARQUET_FF (los gestiona Terraform) ni el otro esquema.
- Athena: nada. Las tablas externas quedan apuntando a carpetas vacías.

Barandillas del código (son contra errores, no contra el dueño de la cuenta):
- El prefijo de S3 sale de `ruta_lake` y cada clave se verifica contra `<entorno>/`.
- El esquema es BIGDATA.DEV o BIGDATA.PROD y se valida con una expresión regular.
- Antes de tocar Snowflake se exige el rol del entorno (BIGDATA_DEV o BIGDATA_PROD).
- Si lo borrado no cuadra con lo listado, se detiene con un error.

Este archivo no importa pyspark.
"""

from __future__ import annotations

import re
from typing import Any

from pipeline.herramientas import archivos, bodega
from pipeline.herramientas.control import exigir_rol_del_entorno, tabla_de_control
from pipeline.herramientas.rutas import (
    BASE_DATOS,
    CAPAS,
    ConfigError,
    bucket_del_lake,
    prefijo_lake,
    raiz_de_prueba,
    validar_entorno,
)

# El esquema de un entorno es BIGDATA.DEV o BIGDATA.PROD y nada más.
_RE_ESQUEMA = re.compile(r"^BIGDATA\.(DEV|PROD)$")


# --- S3 -----------------------------------------------------------------------------------------


def _cliente_s3() -> Any:
    """Cliente de boto3 para S3 (import tardío; las pruebas lo reemplazan)."""
    import boto3

    return boto3.client("s3")


def _prefijo_del_entorno(entorno: str) -> str:
    """'dev/' o 'prod/': el prefijo se arma con la misma función que arma todas las rutas."""
    prefijo = prefijo_lake(validar_entorno(entorno)) + "/"
    if prefijo != f"{entorno}/":
        raise RuntimeError(f"Prefijo inesperado '{prefijo}' para el entorno {entorno}: me detengo.")
    return prefijo


def _capa_de(clave: str, prefijo: str) -> str:
    """bronze, silver, gold u 'otros' según la primera carpeta después de <entorno>/."""
    primera = clave[len(prefijo) :].split("/", 1)[0]
    return primera if primera in CAPAS else "otros"


def _es_crudo(clave: str, prefijo: str) -> bool:
    return clave.startswith(f"{prefijo}bronze/_crudo/")


def _listar_objetos(s3: Any, bucket: str, prefijo: str) -> list[tuple[str, int]]:
    """Todas las claves bajo el prefijo con su tamaño."""
    objetos: list[tuple[str, int]] = []
    paginas = s3.get_paginator("list_objects_v2").paginate(Bucket=bucket, Prefix=prefijo)
    for pagina in paginas:
        for objeto in pagina.get("Contents", []):
            objetos.append((objeto["Key"], int(objeto.get("Size", 0))))
    return objetos


def borrar_capas_s3(entorno: str, solo_listar: bool = True, conservar_crudo: bool = False) -> dict:
    """Borra (o solo lista) todo lo que hay bajo s3://<lake>/<entorno>/. Devuelve el recuento.

    El diccionario trae: entorno, bucket, prefijo (s3://…/<entorno>/), objetos y bytes (lo que se
    borra o se borraría), por_capa ({'bronze': n, 'silver': n, 'gold': n, 'otros': n}),
    conservados (objetos que se dejan por conservar_crudo), borrados (0 si solo_listar),
    solo_listar y muestra (hasta 10 claves de ejemplo).
    """
    validar_entorno(entorno)
    if raiz_de_prueba():
        raise ConfigError(
            "El reseteo trabaja sobre S3, no sobre una raíz de prueba file://. "
            "Quita PIPELINE_RAIZ_LAKE para resetear."
        )
    prefijo = _prefijo_del_entorno(entorno)
    bucket = bucket_del_lake()
    ruta = f"s3://{bucket}/{prefijo}"
    s3 = _cliente_s3()

    archivos.anunciar("LISTA", ruta, "todo lo que hay en el entorno")
    objetos = _listar_objetos(s3, bucket, prefijo)
    # Defensa en profundidad: ninguna clave puede quedar fuera del entorno.
    ajenas = [clave for clave, _ in objetos if not clave.startswith(prefijo)]
    if ajenas:
        raise RuntimeError(
            f"S3 devolvió claves fuera de {prefijo} (p. ej. {ajenas[0]}): me detengo."
        )

    a_borrar = [(c, t) for c, t in objetos if not (conservar_crudo and _es_crudo(c, prefijo))]
    conservados = len(objetos) - len(a_borrar)
    por_capa = dict.fromkeys((*CAPAS, "otros"), 0)
    for clave, _ in a_borrar:
        por_capa[_capa_de(clave, prefijo)] += 1

    resumen = {
        "entorno": entorno,
        "bucket": bucket,
        "prefijo": ruta,
        "objetos": len(a_borrar),
        "bytes": sum(tamano for _, tamano in a_borrar),
        "por_capa": por_capa,
        "conservados": conservados,
        "borrados": 0,
        "solo_listar": solo_listar,
        "muestra": [clave for clave, _ in a_borrar[:10]],
    }
    if solo_listar or not a_borrar:
        return resumen

    archivos.anunciar("BORRA", ruta, f"{len(a_borrar)} objetos (conservar_crudo={conservar_crudo})")
    resumen["borrados"] = archivos.borrar_claves(s3, bucket, [clave for clave, _ in a_borrar])
    if resumen["borrados"] != resumen["objetos"]:
        raise RuntimeError(
            f"Lo borrado ({resumen['borrados']}) no cuadra con lo listado ({resumen['objetos']})."
        )
    return resumen


# --- Snowflake ----------------------------------------------------------------------------------


def esquema_del_entorno(entorno: str) -> str:
    """'BIGDATA.DEV' o 'BIGDATA.PROD'. Cualquier otra cosa no pasa."""
    esquema = f"{BASE_DATOS}.{validar_entorno(entorno).upper()}"
    if not _RE_ESQUEMA.match(esquema):
        raise RuntimeError(f"Esquema inesperado '{esquema}': me detengo.")
    return esquema


def _entre_comillas(nombre: str) -> str:
    """Identificador entre comillas dobles (Snowflake duplica las comillas internas)."""
    return '"' + nombre.replace('"', '""') + '"'


def _nombres(cursor: Any, sql: str) -> list[str]:
    """Nombres de lo que devuelve un SHOW (la segunda columna es el nombre)."""
    cursor.execute(sql)
    return [str(fila[1]) for fila in cursor.fetchall()]


def borrar_tablas_snowflake(
    entorno: str, solo_listar: bool = True, conexion: Any = None
) -> list[str]:
    """Borra (o solo lista) las tablas y vistas de BIGDATA.<ENTORNO>. Devuelve sus nombres.

    Los nombres vienen completos ('BIGDATA.DEV.TARIFA_POR_MILLA_BARRIO'). No toca el stage
    LAKE_GOLD ni el formato PARQUET_FF: ni siquiera los lista.
    """
    esquema = esquema_del_entorno(entorno)
    cerrar = conexion is None
    if conexion is None:
        conexion = bodega.abrir_conexion_de_entorno(entorno)
    try:
        exigir_rol_del_entorno(entorno, conexion)
        cursor = conexion.cursor()
        archivos.anunciar("LISTA", esquema, "tablas y vistas")
        tablas = _nombres(cursor, f"SHOW TABLES IN SCHEMA {esquema}")
        vistas = _nombres(cursor, f"SHOW VIEWS IN SCHEMA {esquema}")
        objetos = [("TABLE", nombre) for nombre in tablas] + [("VIEW", nombre) for nombre in vistas]
        if not solo_listar:
            for tipo, nombre in objetos:
                completo = f"{esquema}.{_entre_comillas(nombre)}"
                archivos.anunciar("BORRA", completo, tipo.lower())
                cursor.execute(f"DROP {tipo} IF EXISTS {completo}")
        return [f"{esquema}.{nombre}" for _, nombre in objetos]
    finally:
        if cerrar:
            conexion.close()


# --- tabla de control ---------------------------------------------------------------------------


def contar_control(entorno: str, conexion: Any = None) -> int:
    """Cuántos registros tiene BIGDATA.CONTROL_<ENTORNO>.WATERMARK (para el recuento previo)."""
    tabla = tabla_de_control(validar_entorno(entorno))
    cerrar = conexion is None
    if conexion is None:
        conexion = bodega.abrir_conexion_de_entorno(entorno)
    try:
        exigir_rol_del_entorno(entorno, conexion)
        cursor = conexion.cursor()
        archivos.anunciar("CUENTA", tabla, "registros")
        try:
            cursor.execute(f"SELECT COUNT(*) FROM {tabla}")
        except Exception as error:
            # 002003: el esquema o la tabla no existen. Pasa cuando la cuenta no se migró.
            if "002003" in str(error) or "does not exist" in str(error):
                raise RuntimeError(
                    f"No existe {tabla} en tu Snowflake: tu cuenta todavía no tiene la "
                    "infraestructura de la clase 7. Corre en la terminal: "
                    "cd ~/bigdata && git pull && make migrar-clase07 (escribe yes cuando el plan "
                    "diga 0 to destroy) y vuelve a lanzar resetear_entorno."
                ) from error
            raise
        return int(cursor.fetchone()[0])
    finally:
        if cerrar:
            conexion.close()
