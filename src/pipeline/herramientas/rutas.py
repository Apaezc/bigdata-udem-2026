"""Rutas del lake, entornos, capas, tablas y utilidades de meses ('AAAA-MM').

Las rutas del lake se arman SOLO aquí (ruta_lake). Ningún otro archivo escribe a mano un
's3://...': las herramientas, los pasos, los DAGs y los scripts piden la ruta a esta función.

Regla del lake: un bucket, y dos entornos que no comparten ningún prefijo.

    s3://<lake>/<entorno>/<capa>/<tabla>/mes=AAAA-MM/...     entorno = dev | prod
                                                             capa = bronze | silver | gold

    dev/bronze/fhvhv/mes=2024-01/lote=<id>/     prod/bronze/fhvhv/mes=2024-01/lote=<id>/
    dev/silver/fhvhv/mes=2024-01/               prod/silver/fhvhv/mes=2024-01/
    dev/gold/tarifa_por_milla_barrio/mes=...    prod/gold/tarifa_por_milla_barrio/mes=...

Un job de dev solo toca dev/; uno de prod solo toca prod/. Los prefijos code/, dags/, logs/ y
tmp/ no son de ningún entorno: son del propio lake (código, DAGs, logs, temporales).

No existe un entorno «local» que escriba en disco. Lo que se corre desde el Code Editor es dev y
escribe en S3. Solo las pruebas pueden redirigir el lake a una carpeta del disco, con la variable
PIPELINE_RAIZ_LAKE=file:///tmp/...: entonces ruta_lake arma <raíz>/<entorno>/<capa>/... en lugar
de s3://<bucket>/... (no cambia el entorno; solo dónde caen los archivos).

Para ver la tabla completa de un entorno: donde_estoy("dev") (o describir_rutas("dev")).
"""

from __future__ import annotations

import os
import re
from datetime import date, timedelta
from importlib import resources

import yaml

ENTORNOS = ("dev", "prod")
CAPAS = ("bronze", "silver", "gold")
# Base de datos de Snowflake: BIGDATA.<ENTORNO>.<TABLA> y BIGDATA.CONTROL_<ENTORNO>.WATERMARK.
BASE_DATOS = "BIGDATA"

TABLA_VIAJES = "fhvhv"
TABLA_ZONAS = "taxi_zones"
TABLA_CLIMA = "clima"
# Valor de la columna MES de la tabla de control para las fuentes que no se parten por mes.
MES_SIN_MES = "sin_mes"
# Carpeta del archivo tal como se descargó, dentro de bronze.
CARPETA_CRUDO = "_crudo"

NOMBRE_ZONAS = "taxi_zone_lookup.csv"
VARIABLE_RAIZ_LAKE = "PIPELINE_RAIZ_LAKE"

# Prefijos del bucket que no son de ningún entorno.
PREFIJOS_DEL_LAKE = ("code", "dags", "logs", "tmp")

_RE_MES = re.compile(r"^\d{4}-(0[1-9]|1[0-2])$")
_RE_NOMBRE = re.compile(r"^[A-Za-z0-9_]+$")

# Cómo se parte cada tabla en carpetas (solo para explicarlo en describir_rutas).
_CARPETAS_DE_LA_CAPA = {
    "bronze": "<tabla>/mes=AAAA-MM/lote=<id>/   (taxi_zones: lote=<id>/)",
    "silver": "<tabla>/mes=AAAA-MM/   (taxi_zones: sin mes)",
    "gold": "<tabla>/mes=AAAA-MM/",
}

# Se muestra en describir_rutas cuando todavía no hay bucket.
BUCKET_SIN_DEFINIR = "<tu-bucket>"


class ConfigError(RuntimeError):
    """Configuración inválida o incompleta."""


# --- entorno -----------------------------------------------------------------------------------


def validar_entorno(entorno: str) -> str:
    """Devuelve el entorno si es dev o prod; si no, dice cuáles existen."""
    if entorno == "local":
        raise ConfigError(
            "El entorno 'local' ya no existe. Desde el Code Editor todo es dev y escribe en "
            "s3://<lake>/dev/…; lo que cambia es el cómputo (code_editor o glue_*), no el entorno."
        )
    if entorno not in ENTORNOS:
        raise ConfigError(f"Entorno desconocido '{entorno}'. Válidos: {', '.join(ENTORNOS)}")
    return entorno


def validar_capa(capa: str) -> str:
    """Devuelve la capa si es bronze, silver o gold; si no, dice cuáles existen."""
    if capa not in CAPAS:
        raise ConfigError(f"Capa desconocida '{capa}'. Válidas: {', '.join(CAPAS)}")
    return capa


# --- el lake -----------------------------------------------------------------------------------


def raiz_de_prueba() -> str | None:
    """La raíz file:// de PIPELINE_RAIZ_LAKE si existe (solo pruebas); None en el uso normal.

    Solo se acepta un valor que empiece por file://: así la variable no puede redirigir el
    pipeline a otro bucket de S3.
    """
    valor = os.environ.get(VARIABLE_RAIZ_LAKE)
    if not valor:
        return None
    if not valor.startswith("file://"):
        raise ConfigError(
            f"{VARIABLE_RAIZ_LAKE} solo acepta rutas file:// (es una variable para pruebas); "
            f"llegó {valor!r}."
        )
    return valor.rstrip("/")


def _bucket_por_sts() -> str:
    """Arma 'bigdata-lake-<cuenta>-<región>' preguntándole a sts quién es la cuenta."""
    import boto3  # import tardío: fuera de AWS no hace falta

    region = os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION") or "us-east-2"
    cuenta = boto3.client("sts", region_name=region).get_caller_identity()["Account"]
    return f"bigdata-lake-{cuenta}-{region}"


def bucket_del_lake(bucket: str | None = None) -> str:
    """Nombre del bucket del lake.

    Orden: el argumento, luego la variable LAKE_BUCKET y, solo en dev, el nombre que arma el
    curso (bigdata-lake-<cuenta>-<región>) con la cuenta que dice sts. En prod nunca se adivina:
    sin LAKE_BUCKET falla.
    """
    nombre = bucket or os.environ.get("LAKE_BUCKET")
    if nombre:
        return nombre
    entorno = os.environ.get("PIPELINE_ENTORNO") or "dev"
    if entorno == "dev":
        try:
            return _bucket_por_sts()
        except Exception as error:
            raise ConfigError(
                "No encontré el bucket del lake: falta la variable LAKE_BUCKET y no pude "
                f"calcularlo con sts ({type(error).__name__}). Revisa tus credenciales de AWS."
            ) from error
    raise ConfigError("Falta la variable de entorno LAKE_BUCKET (nombre del bucket del lake)")


def _carpetas(capa: str | None, tabla: str | None, mes: str | None) -> list[str]:
    """Valida capa, tabla y mes y los devuelve como carpetas: [capa, tabla, 'mes=AAAA-MM']."""
    if capa is None:
        if tabla is not None or mes is not None:
            raise ConfigError("Para pedir una tabla o un mes hay que indicar también la capa")
        return []
    carpetas = [validar_capa(capa)]
    if tabla is None:
        if mes is not None:
            raise ConfigError("Para pedir un mes hay que indicar también la tabla")
        return carpetas
    # Solo letras, números y '_': un nombre de tabla no puede traer '/' ni '..' y salirse de la
    # carpeta del entorno.
    if not _RE_NOMBRE.match(tabla):
        raise ConfigError(f"Nombre de tabla inválido '{tabla}': usa letras, números y '_'")
    carpetas.append(tabla)
    if mes is not None:
        carpetas.append(f"mes={validar_mes(mes)}")
    return carpetas


def prefijo_lake(
    entorno: str, capa: str | None = None, tabla: str | None = None, mes: str | None = None
) -> str:
    """Prefijo dentro del bucket, sin 's3://bucket/': 'dev/silver/fhvhv', 'prod/bronze'.

    Todo prefijo empieza por el entorno.
    """
    return "/".join([validar_entorno(entorno), *_carpetas(capa, tabla, mes)])


def ruta_lake(
    entorno: str,
    capa: str | None = None,
    tabla: str | None = None,
    mes: str | None = None,
    bucket: str | None = None,
) -> str:
    """Ruta completa de un entorno, capa, tabla o mes del lake. Es la ÚNICA forma de armar rutas.

        ruta_lake("dev", "silver", "fhvhv")             -> s3://<bucket>/dev/silver/fhvhv
        ruta_lake("prod", "bronze", "fhvhv", "2024-01") -> s3://<bucket>/prod/bronze/fhvhv/mes=2024-01

    Con PIPELINE_RAIZ_LAKE=file://<carpeta> (solo pruebas) la ruta es <carpeta>/<entorno>/...
    """
    prefijo = prefijo_lake(entorno, capa, tabla, mes)
    raiz = raiz_de_prueba()
    if raiz:
        return f"{raiz}/{prefijo}"
    return f"s3://{bucket_del_lake(bucket)}/{prefijo}"


def _validar_tabla_del_crudo(tabla: str, mes: str | None) -> None:
    """taxi_zones no lleva mes; las demás fuentes del crudo sí."""
    if tabla == TABLA_ZONAS and mes is not None:
        raise ConfigError("taxi_zones no se parte por mes: no pases mes")
    if tabla != TABLA_ZONAS and mes is None:
        raise ConfigError(f"La tabla {tabla} se parte por mes: falta el mes")


def dir_del_crudo(
    entorno: str, tabla: str, mes: str | None = None, bucket: str | None = None
) -> str:
    """Carpeta del archivo descargado tal cual: <bronze>/_crudo/<tabla>[/mes=AAAA-MM]."""
    _validar_tabla_del_crudo(tabla, mes)
    base = ruta_lake(entorno, "bronze", CARPETA_CRUDO, bucket=bucket)
    if not _RE_NOMBRE.match(tabla):
        raise ConfigError(f"Nombre de tabla inválido '{tabla}': usa letras, números y '_'")
    if mes is None:
        return f"{base}/{tabla}"
    return f"{base}/{tabla}/mes={validar_mes(mes)}"


def nombre_del_crudo(tabla: str, mes: str | None = None) -> str:
    """Nombre del archivo crudo de cada fuente (el mismo que usa la fuente al descargarse)."""
    if tabla == TABLA_VIAJES:
        return f"fhvhv_tripdata_{validar_mes(mes or '')}.parquet"
    if tabla == TABLA_CLIMA:
        return f"open_meteo_{validar_mes(mes or '')}.json"
    if tabla == TABLA_ZONAS:
        return NOMBRE_ZONAS
    raise ConfigError(f"No conozco el archivo crudo de la tabla '{tabla}'")


def ruta_del_crudo(
    entorno: str, tabla: str, mes: str | None = None, bucket: str | None = None
) -> str:
    """Ruta completa del archivo crudo: dir_del_crudo + el nombre del archivo."""
    return f"{dir_del_crudo(entorno, tabla, mes, bucket)}/{nombre_del_crudo(tabla, mes)}"


def dir_del_lote(
    entorno: str, tabla: str, id_lote: str, mes: str | None = None, bucket: str | None = None
) -> str:
    """Carpeta de un lote de bronze: bronze/<tabla>/mes=AAAA-MM/lote=<id>/ (zonas: sin mes)."""
    if not _RE_NOMBRE.match(id_lote or ""):
        raise ConfigError(f"Id de lote inválido '{id_lote}': usa letras, números y '_'")
    base = ruta_lake(entorno, "bronze", tabla, mes, bucket)
    return f"{base}/lote={id_lote}"


def nombre_tabla_snowflake(entorno: str, tabla_gold: str) -> str:
    """'BIGDATA.DEV.TARIFA_POR_MILLA_BARRIO': la tabla de Snowflake de una tabla de gold."""
    if not _RE_NOMBRE.match(tabla_gold or ""):
        raise ConfigError(f"Nombre de tabla inválido '{tabla_gold}': usa letras, números y '_'")
    return f"{BASE_DATOS}.{validar_entorno(entorno).upper()}.{tabla_gold.upper()}"


def describir_rutas(entorno: str, bucket: str | None = None) -> str:
    """Texto con el bucket y las carpetas donde el entorno lee y escribe cada capa."""
    validar_entorno(entorno)
    nombre_bucket = bucket or os.environ.get("LAKE_BUCKET")
    raiz = raiz_de_prueba()
    otro = "prod" if entorno == "dev" else "dev"
    lineas = []
    if raiz:
        lineas.append(f"DÓNDE ESTOY | entorno: {entorno} | [RAÍZ DE PRUEBA] {raiz}")
    else:
        lineas.append(f"DÓNDE ESTOY | entorno: {entorno} | los datos están en S3")
        lineas.append(f"Bucket del lake  : {nombre_bucket or BUCKET_SIN_DEFINIR}")
        if not nombre_bucket:
            lineas.append("                   (define LAKE_BUCKET para ver el nombre real)")
    carpeta = ruta_lake(entorno, bucket=nombre_bucket or BUCKET_SIN_DEFINIR)
    lineas.append(f"Carpeta de {entorno:<4}  : {carpeta}")
    lineas.append(f"Este entorno solo lee y escribe bajo {entorno}/. No toca {otro}/.")
    lineas.append("")

    filas = [("CAPA", "RUTA COMPLETA", "CARPETAS DENTRO DE LA CAPA")]
    for capa in CAPAS:
        ruta = ruta_lake(entorno, capa, bucket=nombre_bucket or BUCKET_SIN_DEFINIR)
        filas.append((capa, ruta, _CARPETAS_DE_LA_CAPA[capa]))
        if capa == "bronze":
            crudo = ruta + "/" + CARPETA_CRUDO
            filas.append(("bronze", crudo, "<fuente>/mes=AAAA-MM/<archivo>   (el archivo crudo)"))
    anchos = [max(len(fila[i]) for fila in filas) for i in range(2)]
    for fila in filas:
        lineas.append(f"{fila[0].ljust(anchos[0])}  {fila[1].ljust(anchos[1])}  {fila[2]}")
    lineas.append("")
    lineas.append("Del lake, no de un entorno: " + ", ".join(f"{p}/" for p in PREFIJOS_DEL_LAKE))
    return "\n".join(lineas)


def donde_estoy(entorno: str = "dev", bucket: str | None = None) -> None:
    """Imprime en qué bucket y carpetas lee y escribe cada capa del entorno.

    Úsala al empezar un cuaderno o una práctica: donde_estoy("dev").
    """
    print(describir_rutas(entorno, bucket))


# --- configuración por entorno (solo la lista de meses) ----------------------------------------


def meses_del_entorno(entorno: str) -> list[str]:
    """Los meses de config/<entorno>.yaml: los que se procesan si no se pide un mes."""
    validar_entorno(entorno)
    ruta = resources.files("pipeline") / "config" / f"{entorno}.yaml"
    with ruta.open("r", encoding="utf-8") as archivo:
        contenido = yaml.safe_load(archivo)
    return [validar_mes(str(mes)) for mes in contenido["meses"]]


# --- meses -------------------------------------------------------------------------------------


def validar_mes(mes: str) -> str:
    """Valida el formato 'AAAA-MM' y lo devuelve."""
    if not _RE_MES.match(mes or ""):
        raise ValueError(f"Mes inválido '{mes}': se espera formato AAAA-MM")
    return mes


def inicio_fin_mes(mes: str) -> tuple[date, date]:
    """Devuelve (primer día del mes, primer día del mes siguiente). El fin es exclusivo."""
    anio, num = (int(x) for x in validar_mes(mes).split("-"))
    inicio = date(anio, num, 1)
    fin = date(anio + 1, 1, 1) if num == 12 else date(anio, num + 1, 1)
    return inicio, fin


def rango_meses(meses: list[str]) -> tuple[date, date]:
    """(primer día del primer mes, primer día del mes siguiente al último). El fin es exclusivo."""
    if not meses:
        raise ValueError("Se necesita al menos un mes")
    ordenados = sorted(validar_mes(m) for m in meses)
    return inicio_fin_mes(ordenados[0])[0], inicio_fin_mes(ordenados[-1])[1]


def ultimo_dia_mes(mes: str) -> date:
    """Último día calendario del mes."""
    _, fin = inicio_fin_mes(mes)
    return fin - timedelta(days=1)
