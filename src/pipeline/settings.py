"""Configuración por entorno, rutas del lake y utilidades de meses ('YYYY-MM').

Las rutas del lake se arman SOLO aquí (ruta_lake / prefijo_lake). Ningún otro archivo escribe a
mano un 's3://...': io, bronze, muestra, los DAGs y los scripts piden la ruta a esta función.

Regla del lake: un bucket, y dos entornos que no comparten ningún prefijo.

    s3://<lake>/<entorno>/<capa>/<tabla>/mes=AAAA-MM/...     entorno = dev | prod
                                                             capa = bronze | silver | gold | muestra

    dev/bronze/fhvhv/...    dev/silver/fhvhv_trips/...    dev/gold/daily_zone_metrics/...
    prod/bronze/fhvhv/...   prod/silver/fhvhv_trips/...   prod/gold/daily_zone_metrics/...

Un job con --env dev solo toca dev/; uno con --env prod solo toca prod/. Los prefijos code/,
dags/, logs/ y tmp/ no son de ningún entorno: son del propio lake (código, DAGs, logs, temporales).
En local los datos viven en el disco, en ./lake/{muestra,silver,gold}.

Para ver la tabla completa de un entorno: donde_estoy("dev") (o describir_rutas("dev")).
"""

from __future__ import annotations

import os
import re
from datetime import date, timedelta
from importlib import resources
from typing import Any

import yaml

ENTORNOS = ("local", "dev", "prod")
# Entornos cuyos datos viven en S3: en cada uno, todo cuelga de s3://<lake>/<entorno>/.
ENTORNOS_S3 = ("dev", "prod")
PLACEHOLDER_BUCKET = "{lake_bucket}"
_RE_MES = re.compile(r"^\d{4}-(0[1-9]|1[0-2])$")
_RE_NOMBRE = re.compile(r"^[A-Za-z0-9_]+$")

# --- capas y tablas: nombres únicos (io.py los reexporta) --------------------------------------

CAPAS = ("bronze", "silver", "gold", "muestra")
CAPAS_DE_CONFIG = ("bronze", "silver", "gold")  # las que van en cfg["rutas"]

TABLA_VIAJES = "fhvhv"
TABLA_ZONAS = "taxi_zones"
TABLA_CLIMA = "clima"
TABLA_SILVER = "fhvhv_trips"
TABLA_GOLD = "daily_zone_metrics"

TABLAS_POR_CAPA = {
    "bronze": (TABLA_VIAJES, TABLA_CLIMA, TABLA_ZONAS),
    "silver": (TABLA_SILVER,),
    "gold": (TABLA_GOLD,),
    "muestra": (TABLA_VIAJES, TABLA_CLIMA, TABLA_ZONAS),
}

# Cómo se parte cada tabla en carpetas (solo para explicarlo en describir_rutas).
CARPETAS_DENTRO_DE_LA_TABLA = {
    TABLA_VIAJES: "mes=AAAA-MM/lote=<id>/",
    TABLA_CLIMA: "mes=AAAA-MM/lote=<id>/",
    TABLA_ZONAS: "lote=<id>/",
    TABLA_SILVER: "pickup_date=AAAA-MM-DD/",
    TABLA_GOLD: "mes=AAAA-MM/",
}

# Prefijos del bucket que no son de ningún entorno.
PREFIJOS_DEL_LAKE = ("code", "dags", "logs", "tmp")

# Local: carpeta del disco y nombre que toma cada capa. El "bronze" de local es la muestra.
CARPETA_LOCAL = "./lake"
CARPETA_LOCAL_DE_LA_CAPA = {
    "bronze": "muestra",
    "muestra": "muestra",
    "silver": "silver",
    "gold": "gold",
}

# La muestra que baja local la genera `make muestra` con --env prod, a partir del bronze del año
# completo (prod/bronze). Es la única lectura de local hacia S3 y no escribe nada.
ENTORNO_DE_LA_MUESTRA = "prod"

# Se muestra en describir_rutas cuando todavía no hay LAKE_BUCKET.
BUCKET_SIN_DEFINIR = "<tu-bucket>"


class ConfigError(RuntimeError):
    """Configuración inválida o incompleta."""


# --- rutas del lake ----------------------------------------------------------------------------


def validar_entorno(entorno: str) -> str:
    """Devuelve el entorno si es local, dev o prod; si no, dice cuáles existen."""
    if entorno not in ENTORNOS:
        raise ConfigError(f"Entorno desconocido '{entorno}'. Válidos: {', '.join(ENTORNOS)}")
    return entorno


def bucket_del_lake(bucket: str | None = None) -> str:
    """Nombre del bucket del lake: el argumento o, si no viene, la variable LAKE_BUCKET."""
    nombre = bucket or os.environ.get("LAKE_BUCKET")
    if not nombre:
        raise ConfigError(
            "Falta la variable de entorno LAKE_BUCKET (nombre del bucket del lake) "
            "para armar las rutas de S3"
        )
    return nombre


def _carpetas(
    capa: str | None,
    tabla: str | None,
    mes: str | None,
    nombre_de_la_capa: dict[str, str] | None = None,
) -> list[str]:
    """Valida capa, tabla y mes y los devuelve como carpetas: [capa, tabla, 'mes=AAAA-MM']."""
    if capa is None:
        if tabla is not None or mes is not None:
            raise ConfigError("Para pedir una tabla o un mes hay que indicar también la capa")
        return []
    if capa not in CAPAS:
        raise ConfigError(f"Capa desconocida '{capa}'. Válidas: {', '.join(CAPAS)}")
    carpetas = [nombre_de_la_capa[capa] if nombre_de_la_capa else capa]
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
    """Prefijo dentro del bucket, sin 's3://bucket/': 'dev/silver/fhvhv_trips', 'prod/muestra'.

    Solo existe para los entornos de S3 (dev y prod). Todo prefijo empieza por el entorno.
    """
    if validar_entorno(entorno) not in ENTORNOS_S3:
        raise ConfigError(
            f"El entorno '{entorno}' no tiene prefijo en S3: sus datos están en disco"
        )
    return "/".join([entorno, *_carpetas(capa, tabla, mes)])


def ruta_lake(
    entorno: str,
    capa: str | None = None,
    tabla: str | None = None,
    mes: str | None = None,
    bucket: str | None = None,
) -> str:
    """Ruta completa de un entorno, capa, tabla o mes del lake. Es la ÚNICA forma de armar rutas.

    dev o prod -> s3://<bucket>/<entorno>/<capa>/<tabla>/mes=AAAA-MM
    local      -> <carpeta actual>/lake/<capa>/<tabla>/mes=AAAA-MM  (la capa bronze es la muestra)

    Ejemplos:
        ruta_lake("dev", "silver", "fhvhv_trips")       -> s3://<bucket>/dev/silver/fhvhv_trips
        ruta_lake("prod", "bronze", "fhvhv", "2024-01") -> s3://<bucket>/prod/bronze/fhvhv/mes=2024-01
        ruta_lake("local", "gold")                      -> /.../lake/gold
    """
    if validar_entorno(entorno) == "local":
        carpetas = _carpetas(capa, tabla, mes, CARPETA_LOCAL_DE_LA_CAPA)
        return os.path.abspath("/".join([CARPETA_LOCAL, *carpetas]))
    return f"s3://{bucket_del_lake(bucket)}/{prefijo_lake(entorno, capa, tabla, mes)}"


def _filas_de_rutas(entorno: str, bucket: str | None) -> list[tuple[str, str, str, str, str]]:
    """Una fila por tabla: (capa, tabla, dónde, ruta completa, carpetas dentro de la tabla)."""
    filas = []
    for capa in CAPAS:
        if entorno == "local" and capa == "bronze":
            continue  # en local la capa de entrada es la muestra
        for tabla in TABLAS_POR_CAPA[capa]:
            ruta = ruta_lake(entorno, capa, tabla, bucket=bucket)
            donde = "disco" if entorno == "local" else "S3"
            nombre_capa = "muestra (entrada)" if entorno == "local" and capa == "muestra" else capa
            filas.append((nombre_capa, tabla, donde, ruta, CARPETAS_DENTRO_DE_LA_TABLA[tabla]))
        if capa == "bronze" and entorno != "local":
            # El archivo tal como se descargó, antes de convertirlo a Parquet con metadatos.
            ruta = ruta_lake(entorno, capa, bucket=bucket) + "/_crudo"
            filas.append((capa, "_crudo", "S3", ruta, "<fuente>/mes=AAAA-MM/<archivo>"))
    return filas


def describir_rutas(entorno: str, bucket: str | None = None) -> str:
    """Texto con el bucket y las carpetas donde el entorno lee y escribe cada capa."""
    validar_entorno(entorno)
    nombre_bucket = bucket or os.environ.get("LAKE_BUCKET")
    bucket_a_mostrar = nombre_bucket or BUCKET_SIN_DEFINIR
    lineas = []

    if entorno == "local":
        lineas.append("DÓNDE ESTOY | entorno: local | los datos están en el DISCO de esta máquina")
        lineas.append(f"Carpeta de datos : {ruta_lake('local')}")
        lineas.append(
            "Local no escribe en S3. Lo único que lee de S3 es la muestra, la primera vez."
        )
    else:
        otro = "prod" if entorno == "dev" else "dev"
        lineas.append(f"DÓNDE ESTOY | entorno: {entorno} | los datos están en S3")
        lineas.append(f"Bucket del lake  : {bucket_a_mostrar}")
        if not nombre_bucket:
            lineas.append("                   (define LAKE_BUCKET para ver el nombre real)")
        lineas.append(f"Carpeta de {entorno:<4}  : {ruta_lake(entorno, bucket=bucket_a_mostrar)}")
        lineas.append(f"Este entorno solo lee y escribe bajo {entorno}/. No toca {otro}/.")
    lineas.append("")

    filas = [("CAPA", "TABLA", "DÓNDE", "RUTA COMPLETA", "CARPETAS DENTRO DE LA TABLA")]
    filas += _filas_de_rutas(entorno, bucket_a_mostrar)
    anchos = [max(len(fila[i]) for fila in filas) for i in range(4)]
    for fila in filas:
        celdas = [fila[i].ljust(anchos[i]) for i in range(4)]
        lineas.append("  ".join(celdas) + "  " + fila[4])
    lineas.append("")

    if entorno == "local":
        origen = ruta_lake(ENTORNO_DE_LA_MUESTRA, "muestra", bucket=bucket_a_mostrar)
        lineas.append(f"La muestra se baja de {origen}/ (la genera make muestra)")
        lineas.append("o, si ahí no hay, del bucket público del curso.")
    else:
        lineas.append(
            "Del lake, no de un entorno: " + ", ".join(f"{p}/" for p in PREFIJOS_DEL_LAKE)
        )
    return "\n".join(lineas)


def donde_estoy(entorno: str = "dev", bucket: str | None = None) -> None:
    """Imprime en qué bucket y carpetas lee y escribe cada capa del entorno.

    Úsala al empezar un notebook o una práctica: pio.donde_estoy("dev").
    """
    print(describir_rutas(entorno, bucket))


# --- configuración por entorno -----------------------------------------------------------------


def cargar(env: str) -> dict[str, Any]:
    """Lee src/pipeline/config/<env>.yaml y le agrega las rutas del entorno (ver ruta_lake).

    cfg["rutas"] trae bronze, silver y gold. En dev y prod, cfg["muestra"]["destino"] es donde se
    escribe la muestra; en local, cfg["muestra"]["sincronizar_desde"] es el prefijo del bucket
    del que se baja la muestra.
    """
    validar_entorno(env)
    ruta = resources.files("pipeline") / "config" / f"{env}.yaml"
    with ruta.open("r", encoding="utf-8") as f:
        cfg = yaml.safe_load(f)
    cfg = _resolver(cfg)

    cfg["rutas"] = {capa: ruta_lake(env, capa) for capa in CAPAS_DE_CONFIG}
    if env in ENTORNOS_S3:
        cfg["muestra"]["destino"] = ruta_lake(env, "muestra")
        _verificar_aislamiento(env, cfg)
    else:
        cfg["muestra"]["sincronizar_desde"] = prefijo_lake(ENTORNO_DE_LA_MUESTRA, "muestra")
    return cfg


def _verificar_aislamiento(env: str, cfg: dict[str, Any]) -> None:
    """Falla si alguna ruta de S3 del entorno queda fuera de s3://<lake>/<env>/."""
    raiz = ruta_lake(env) + "/"
    rutas = [*cfg["rutas"].values(), cfg["muestra"]["destino"]]
    for ruta in rutas:
        if not ruta.startswith(raiz):
            raise ConfigError(f"La ruta {ruta} no está dentro de {raiz}: dev y prod no se mezclan")


def _resolver(obj: Any) -> Any:
    if isinstance(obj, dict):
        return {k: _resolver(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_resolver(v) for v in obj]
    if isinstance(obj, str) and PLACEHOLDER_BUCKET in obj:
        return obj.replace(PLACEHOLDER_BUCKET, bucket_del_lake())
    return obj


# --- meses -------------------------------------------------------------------------------------


def validar_mes(mes: str) -> str:
    """Valida el formato 'YYYY-MM' y lo devuelve."""
    if not _RE_MES.match(mes or ""):
        raise ValueError(f"Mes inválido '{mes}': se espera formato YYYY-MM")
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
