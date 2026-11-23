"""Cómo se configura y se ve una corrida: entorno, pipeline.yaml, Corrida, banner y cierre.

Reglas (las del autor del curso):

1. El entorno NO se elige. Todo lo que se corre desde el Code Editor (terminal, cuaderno, make,
   Airflow local) es dev. Prod solo lo fija el lado desplegado por el CI/CD: la VM de Airflow, con
   PIPELINE_ENTORNO=prod, y Glue con el argumento --env prod que pasa el DAG de esa VM.
   Son barandillas contra errores, no un control contra el dueño de la cuenta: el control real
   es Snowflake (el rol de dev no escribe en PROD) y el PR.
2. Lo demás se configura en pipeline.yaml (raíz del repo): cómputo, límite, mes y reprocesar.
   Precedencia: argumento del comando, de la función o del DAG > pipeline.yaml > valor por defecto.
3. Cada corrida imprime el mismo encabezado (banner) y el mismo cierre, en la consola, el
   cuaderno, Airflow, Glue y prod.

Este archivo no importa pyspark: la VM de Airflow no lo tiene.
"""

from __future__ import annotations

import os
import secrets
import sys
import tempfile
import time
import zipfile
from dataclasses import dataclass, replace
from datetime import UTC, datetime, timedelta
from pathlib import Path

import yaml

from pipeline.settings import (
    ENTORNOS,
    MES_SIN_MES,
    TABLA_CLIMA,
    TABLA_VIAJES,
    TABLA_ZONAS,
    ConfigError,
    bucket_del_lake,
    dir_del_crudo,
    meses_del_entorno,
    nombre_tabla_snowflake,
    raiz_de_prueba,
    ruta_lake,
    validar_mes,
)

COMPUTOS = ("code_editor", "glue_small", "glue_medium", "glue_large")
LIMITES = ("1000", "100000", "todos")  # siempre texto (yaml, make, función, DAG)
PASOS = ("bronze", "silver", "gold", "snowflake")
DEFECTOS = {"computo": "code_editor", "limite": "1000", "mes": "2024-01", "reprocesar": False}

# Valores de prod que no se discuten.
COMPUTO_DE_PROD = "glue_medium"
LIMITE_DE_PROD = "todos"

ANCHO_BANNER = 66
LINEA = "=" * ANCHO_BANNER
ANCHO_ETIQUETA = 11

# Gold y snowflake: la tabla de la casa. Si el equipo agrega la suya a gold.TABLAS_GOLD o a
# carga.TABLAS_A_CARGAR, el banner la muestra solo (ver _tablas_gold y _tablas_a_cargar).
TABLA_GOLD_DE_LA_CASA = "tarifa_por_milla_barrio"

# Glue: workers y minutos de plazo de cada perfil. Manda airflow/framework/profiles.yaml si se
# encuentra; estos valores son el respaldo.
PERFILES_DE_GLUE = {"small": (2, 15), "medium": (4, 20), "large": (6, 30)}
ESTADOS_FINALES_DE_GLUE = ("SUCCEEDED", "FAILED", "ERROR", "TIMEOUT", "STOPPED")
SEGUNDOS_ENTRE_CONSULTAS = 15
# Margen para comparar el reloj de este equipo con el INICIO que quedó en la tabla de control.
MARGEN_DE_RELOJ = 10


class EntornoNoPermitido(RuntimeError):
    """Se pidió algo que el entorno no permite (por ejemplo prod con code_editor)."""


class LimiteNoPermitido(ValueError):
    """El límite pedido no se puede usar con ese cómputo."""


# --- entorno -----------------------------------------------------------------------------------


def entorno_actual(argumentos_de_glue: dict | None = None) -> str:
    """'dev' o 'prod' sin que nadie lo elija.

    Fuera de Glue lee PIPELINE_ENTORNO (por defecto dev). Dentro de Glue manda el --env que pasó
    el DAG de prod (run_glue lo entrega aquí o lo deja en PIPELINE_ENTORNO).
    """
    valor = None
    if argumentos_de_glue:
        valor = argumentos_de_glue.get("env")
    if not valor:
        valor = os.environ.get("PIPELINE_ENTORNO") or "dev"
    if valor not in ENTORNOS:
        raise EntornoNoPermitido(
            f"El entorno '{valor}' no existe: solo hay {' y '.join(ENTORNOS)}. "
            "No se elige: desde el Code Editor siempre es dev."
        )
    return valor


# --- pipeline.yaml -----------------------------------------------------------------------------


def _ruta_de_pipeline_yaml(ruta: str | None) -> Path:
    """El argumento, luego la variable PIPELINE_YAML y, si no, <raíz del repo>/pipeline.yaml."""
    if ruta:
        return Path(ruta)
    if os.environ.get("PIPELINE_YAML"):
        return Path(os.environ["PIPELINE_YAML"])
    # este archivo es <raíz>/src/pipeline/herramientas/corrida.py
    return Path(__file__).resolve().parents[3] / "pipeline.yaml"


def _limite_en_texto(valor) -> str | None:
    """'1000', 100000, 'Todos' -> el texto válido; cualquier otra cosa -> None."""
    if valor is None or isinstance(valor, bool):
        return None
    texto = str(valor).strip().lower()
    if texto in LIMITES:
        return texto
    return None


def _reprocesar_en_booleano(valor) -> bool | None:
    """true/false (o 'true'/'false' en texto) -> bool; cualquier otra cosa -> None."""
    if isinstance(valor, bool):
        return valor
    if isinstance(valor, str) and valor.strip().lower() in ("true", "false"):
        return valor.strip().lower() == "true"
    return None


def _mes_en_texto(valor) -> str | None:
    """'2024-01' -> '2024-01'; vacío -> ''; cualquier otra cosa -> None (inválido)."""
    if valor is None:
        return ""
    texto = str(valor).strip()
    if texto == "":
        return ""
    try:
        return validar_mes(texto)
    except ValueError:
        return None


def _computo_en_texto(valor) -> str | None:
    if isinstance(valor, str) and valor.strip() in COMPUTOS:
        return valor.strip()
    return None


_NORMALIZADORES = {
    "computo": _computo_en_texto,
    "limite": _limite_en_texto,
    "mes": _mes_en_texto,
    "reprocesar": _reprocesar_en_booleano,
}


def _leer_pipeline_yaml(ruta: str | None) -> tuple[dict, dict[str, str], list[str]]:
    """(valores ya normalizados, aviso por campo, avisos generales). Nunca lanza."""
    valores = dict(DEFECTOS)
    por_campo: dict[str, str] = {}
    generales: list[str] = []
    archivo = _ruta_de_pipeline_yaml(ruta)

    contenido = None
    try:
        with archivo.open("r", encoding="utf-8") as f:
            contenido = yaml.safe_load(f)
    except FileNotFoundError:
        generales.append(
            f"no encontré pipeline.yaml en {archivo}; se usaron los valores por defecto"
        )
        return valores, por_campo, generales
    except (OSError, yaml.YAMLError) as error:
        generales.append(
            f"pipeline.yaml no se pudo leer ({type(error).__name__}); se usaron los valores "
            "por defecto"
        )
        return valores, por_campo, generales
    if not isinstance(contenido, dict):
        generales.append(
            "pipeline.yaml está vacío o mal escrito; se usaron los valores por defecto"
        )
        return valores, por_campo, generales

    for campo, normalizar in _NORMALIZADORES.items():
        if campo not in contenido:
            por_campo[campo] = f"falta {campo} en pipeline.yaml; se usó {DEFECTOS[campo]}"
            continue
        normalizado = normalizar(contenido[campo])
        if normalizado is None:
            por_campo[campo] = f"{campo} inválido en pipeline.yaml; se usó {DEFECTOS[campo]}"
            continue
        valores[campo] = normalizado
    return valores, por_campo, generales


def valores_de_pipeline_yaml(ruta: str | None = None) -> dict:
    """Lee y NORMALIZA pipeline.yaml: computo, limite, mes, reprocesar y avisos.

    NUNCA lanza: un valor inválido se reemplaza por su defecto (un limite inválido queda en
    '1000') y se agrega un texto a 'avisos'. Así el DAG puede parsearse siempre, aunque alguien
    deje el yaml roto. mes vacío ('') significa «todos los meses de config/dev.yaml».
    """
    valores, por_campo, generales = _leer_pipeline_yaml(ruta)
    valores["avisos"] = [*generales, *por_campo.values()]
    return valores


# --- la corrida --------------------------------------------------------------------------------


def _nuevo_id_lote(ahora: datetime) -> str:
    """Id de lote, igual que capas.nuevo_id_lote: fecha UTC y 6 hex (20260115T143005Z_a3f9c1)."""
    return f"{ahora.strftime('%Y%m%dT%H%M%SZ')}_{secrets.token_hex(3)}"


@dataclass(frozen=True)
class Corrida:
    """Todo lo que define una corrida; se calcula una vez y viaja por los pasos."""

    entorno: str  # 'dev' | 'prod'
    computo: str
    meses: tuple[str, ...]  # ('2024-01',); sin mes salen los de config/<entorno>.yaml
    limite: str  # uno de LIMITES
    reprocesar: bool
    id_lote: str  # un id por corrida
    fecha_ingesta: datetime  # UTC, sin microsegundos
    avisos: tuple[str, ...] = ()  # p. ej. «limite inválido en pipeline.yaml; se usó 1000»

    @property
    def limite_filas(self) -> int | None:
        """1000, 100000 o None (todos)."""
        if self.limite == "todos":
            return None
        return int(self.limite)


@dataclass(frozen=True)
class Resultado:
    """Lo que dejó un paso en una tabla de un mes."""

    tabla: str
    capa: str
    mes: str
    leidas: int
    escritas: int
    decision: str  # 'SE SALTÓ' | 'REGISTRÓ'


def _resolver_conexion(entorno: str) -> None:
    """Deja puestas WATERMARK_SECRET y LAKE_BUCKET si faltan, para que nadie las exporte a mano.

    Dev: el secreto es <PREFIX>/snowflake (rol BIGDATA_DEV) y el bucket sale de sts
    (bigdata-lake-<cuenta>-<región>). Prod: el secreto es <PREFIX>/snowflake_prod y el bucket
    nunca se adivina (lo pone la VM o Glue).
    """
    prefijo = os.environ.get("PREFIX") or "bigdata"
    if not os.environ.get("WATERMARK_SECRET"):
        sufijo = "snowflake" if entorno == "dev" else "snowflake_prod"
        os.environ["WATERMARK_SECRET"] = f"{prefijo}/{sufijo}"
    if entorno == "dev" and not os.environ.get("LAKE_BUCKET") and not raiz_de_prueba():
        try:
            os.environ["LAKE_BUCKET"] = bucket_del_lake()
        except ConfigError:
            # Sin credenciales de AWS no se puede calcular. El error claro sale cuando se arme
            # la primera ruta (bucket_del_lake lo explica); aquí no se interrumpe.
            pass


def _computo_de_argumento(valor) -> str:
    texto = _computo_en_texto(valor)
    if texto is None:
        raise ConfigError(f"computo inválido '{valor}'. Válidos: {', '.join(COMPUTOS)}")
    return texto


def _limite_de_argumento(valor) -> str:
    texto = _limite_en_texto(valor)
    if texto is None:
        raise ConfigError(f"limite inválido '{valor}'. Válidos: {', '.join(LIMITES)}")
    return texto


def _mes_de_argumento(valor) -> str:
    texto = _mes_en_texto(valor)
    if texto is None:
        raise ConfigError(f"mes inválido '{valor}': se espera AAAA-MM (o vacío para todos)")
    return texto


def _reprocesar_de_argumento(valor) -> bool:
    booleano = _reprocesar_en_booleano(valor)
    if booleano is None:
        raise ConfigError(f"reprocesar inválido '{valor}': usa true o false")
    return booleano


def cargar_configuracion(mes=None, computo=None, limite=None, reprocesar=None) -> Corrida:
    """Arma la Corrida. Reglas, en este orden:

    - entorno = entorno_actual() (nunca un argumento).
    - dev: se resuelven los defectos de conexión (WATERMARK_SECRET y LAKE_BUCKET) si faltan.
    - argumento > pipeline.yaml > defecto. Un valor inválido que viene de pipeline.yaml se
      reemplaza por el defecto y deja un aviso; uno que viene de un argumento es ConfigError.
    - code_editor admite límite '1000' o '100000'; 'todos' con code_editor es LimiteNoPermitido.
    - prod: el cómputo debe ser glue_* (por defecto glue_medium) y el límite es SIEMPRE 'todos';
      pedir otra cosa es EntornoNoPermitido. pipeline.yaml se ignora.
    - mes vacío ('') o sin mes: se procesan los meses de config/<entorno>.yaml.
    """
    entorno = entorno_actual()
    _resolver_conexion(entorno)
    avisos: list[str] = []

    if entorno == "prod":
        elegido_computo = _computo_de_argumento(computo) if computo is not None else COMPUTO_DE_PROD
        if elegido_computo == "code_editor":
            raise EntornoNoPermitido(
                "Prod solo corre con Glue (glue_small, glue_medium o glue_large), no con "
                "code_editor. Prod se corre desde el DAG de la VM, después del PR y el CI/CD."
            )
        elegido_limite = LIMITE_DE_PROD
        if limite is not None and _limite_de_argumento(limite) != LIMITE_DE_PROD:
            raise EntornoNoPermitido(
                f"Prod siempre procesa todo: el límite es '{LIMITE_DE_PROD}', no '{limite}'."
            )
        elegido_mes = _mes_de_argumento(mes) if mes is not None else ""
        elegido_reprocesar = (
            _reprocesar_de_argumento(reprocesar) if reprocesar is not None else False
        )
    else:
        yaml_valores, yaml_avisos, yaml_generales = DEFECTOS, {}, []
        if None in (mes, computo, limite, reprocesar):
            yaml_valores, yaml_avisos, yaml_generales = _leer_pipeline_yaml(None)
            avisos.extend(yaml_generales)

        def decidir(campo, argumento, convertir):
            if argumento is not None:
                return convertir(argumento)
            if campo in yaml_avisos:
                avisos.append(yaml_avisos[campo])
            return yaml_valores[campo]

        elegido_computo = decidir("computo", computo, _computo_de_argumento)
        elegido_limite = decidir("limite", limite, _limite_de_argumento)
        elegido_mes = decidir("mes", mes, _mes_de_argumento)
        elegido_reprocesar = decidir("reprocesar", reprocesar, _reprocesar_de_argumento)
        if elegido_computo == "code_editor" and elegido_limite == "todos":
            raise LimiteNoPermitido(
                "Con el cómputo code_editor el límite es 1000 o 100000: 'todos' es para Glue. "
                "Usa un cómputo de Glue (glue_small, glue_medium o glue_large)."
            )

    if elegido_mes:
        meses = (elegido_mes,)
    else:
        meses = tuple(meses_del_entorno(entorno))

    ahora = datetime.now(UTC).replace(microsecond=0)
    return Corrida(
        entorno=entorno,
        computo=elegido_computo,
        meses=meses,
        limite=elegido_limite,
        reprocesar=elegido_reprocesar,
        id_lote=_nuevo_id_lote(ahora),
        fecha_ingesta=ahora,
        avisos=tuple(avisos),
    )


# --- qué tablas toca cada paso y dónde ---------------------------------------------------------


def _tablas_gold() -> list[str]:
    """Las tablas de gold.TABLAS_GOLD si el módulo ya está cargado; si no, la de la casa.

    Se mira sys.modules en lugar de importar gold: la caja no importa los pasos (y gold trae
    pyspark, que la VM no tiene).
    """
    gold = sys.modules.get("pipeline.gold")
    tablas = getattr(gold, "TABLAS_GOLD", None)
    if tablas:
        return list(tablas)
    return [TABLA_GOLD_DE_LA_CASA]


def _tablas_a_cargar() -> list[str]:
    """Las tablas de carga.TABLAS_A_CARGAR si el módulo ya está cargado; si no, la de la casa."""
    carga = sys.modules.get("pipeline.carga")
    entradas = getattr(carga, "TABLAS_A_CARGAR", None)
    if entradas:
        return [entrada["gold"] for entrada in entradas]
    return [TABLA_GOLD_DE_LA_CASA]


def tablas_del_paso(paso: str, mes: str) -> list[tuple[str, str]]:
    """[(tabla, mes que lleva en la tabla de control)] de un paso, en el orden del banner."""
    if paso not in PASOS:
        raise ConfigError(f"Paso desconocido '{paso}'. Válidos: {', '.join(PASOS)}")
    if paso in ("bronze", "silver"):
        return [(TABLA_VIAJES, mes), (TABLA_ZONAS, MES_SIN_MES), (TABLA_CLIMA, mes)]
    if paso == "gold":
        return [(tabla, mes) for tabla in _tablas_gold()]
    return [(tabla, mes) for tabla in _tablas_a_cargar()]


def _carpeta(entorno: str, capa: str, tabla: str, mes: str) -> str:
    """Carpeta de una tabla de una capa; taxi_zones no lleva mes. Termina en '/'."""
    if tabla == TABLA_ZONAS:
        return ruta_lake(entorno, capa, tabla) + "/"
    return ruta_lake(entorno, capa, tabla, mes) + "/"


def _carpeta_del_crudo(entorno: str, tabla: str, mes: str) -> str:
    if tabla == TABLA_ZONAS:
        return dir_del_crudo(entorno, tabla) + "/"
    return dir_del_crudo(entorno, tabla, mes) + "/"


def tabla_de_control_del_entorno(entorno: str) -> str:
    """'BIGDATA.CONTROL_DEV.WATERMARK' (como control.tabla_de_control, sin importar Snowflake)."""
    return f"BIGDATA.CONTROL_{entorno.upper()}.WATERMARK"


def rutas_del_paso(corrida: Corrida, paso: str, mes: str) -> tuple[list[str], list[str], str]:
    """(rutas completas que lee, rutas completas que escribe, tabla de control).

    Todo sale de ruta_lake: el banner no escribe rutas a mano.
    """
    entorno = corrida.entorno
    control = tabla_de_control_del_entorno(entorno)
    tablas = [tabla for tabla, _ in tablas_del_paso(paso, mes)]
    if paso == "bronze":
        lee = [_carpeta_del_crudo(entorno, tabla, mes) for tabla in tablas]
        escribe = [_carpeta(entorno, "bronze", tabla, mes) for tabla in tablas]
    elif paso == "silver":
        lee = [_carpeta(entorno, "bronze", tabla, mes) for tabla in tablas]
        escribe = [_carpeta(entorno, "silver", tabla, mes) for tabla in tablas]
    elif paso == "gold":
        # gold junta las tres tablas de silver y escribe una tabla de gold por pregunta.
        lee = [
            _carpeta(entorno, "silver", tabla, mes)
            for tabla in (TABLA_VIAJES, TABLA_ZONAS, TABLA_CLIMA)
        ]
        escribe = [_carpeta(entorno, "gold", tabla, mes) for tabla in tablas]
    else:
        lee = [_carpeta(entorno, "gold", tabla, mes) for tabla in tablas]
        escribe = [nombre_tabla_snowflake(entorno, tabla) for tabla in tablas]
    return lee, escribe, control


# --- banner y cierre ---------------------------------------------------------------------------


def _linea(etiqueta: str, valor: str) -> str:
    """' Etiqueta    : valor' (etiqueta de 11 caracteres)."""
    return f" {etiqueta.ljust(ANCHO_ETIQUETA)}: {valor}"


def _lineas_con_etiqueta(etiqueta: str, valores: list[str]) -> list[str]:
    """La primera con la etiqueta y las siguientes sin ella, alineadas debajo del primer valor."""
    sangria = " " * (1 + ANCHO_ETIQUETA + 2)  # lo que ocupan « Etiqueta    : »
    lineas = []
    for posicion, valor in enumerate(valores):
        if posicion == 0:
            lineas.append(_linea(etiqueta, valor))
        else:
            lineas.append(sangria + valor)
    return lineas


def banner(corrida: Corrida, paso: str, mes: str) -> str:
    """Texto del banner que abre cada paso y mes (idéntico en consola, cuaderno, Airflow y Glue)."""
    lee, escribe, control = rutas_del_paso(corrida, paso, mes)

    if corrida.entorno == "prod":
        entorno = "PROD ⚠  (producción)"
    else:
        entorno = "DEV"
    if raiz_de_prueba():
        entorno += " [RAÍZ DE PRUEBA]"
    computo = corrida.computo
    if paso == "snowflake":
        computo += " (este paso no usa Spark)"

    lineas = [
        LINEA,
        _linea("Entorno", entorno),
        _linea("Cómputo", computo),
        _linea("Paso", paso),
        _linea("Mes", mes),
        _linea("Límite", corrida.limite),
        _linea("Reprocesar", "true" if corrida.reprocesar else "false"),
        *_lineas_con_etiqueta("Lee", lee),
        *_lineas_con_etiqueta("Escribe", escribe),
        _linea("Control", control),
    ]
    if corrida.avisos:
        lineas.extend(_lineas_con_etiqueta("Aviso", list(corrida.avisos)))
    lineas.append(LINEA)
    return "\n".join(lineas)


def _texto_de_la_decision(resultado: Resultado, nota_de_salto: str | None) -> str:
    if resultado.decision == "REGISTRÓ":
        return "REGISTRÓ en la tabla de control"
    nota = nota_de_salto or "(ya registrado y reprocesar=false)"
    return f"{resultado.decision} {nota}"


def cierre(
    corrida: Corrida,
    paso: str,
    mes: str,
    resultados: list[Resultado],
    nota_de_salto: str | None = None,
) -> str:
    """Texto del cierre: por tabla, cuántas filas leyó, cuántas escribió y si se saltó o registró.

    nota_de_salto cambia el texto entre paréntesis de «SE SALTÓ» (Glue no dice el motivo).
    """
    lineas = [_linea("Cierre", f"paso={paso} mes={mes}")]
    for r in resultados:
        leyo = f"leyó={r.leidas}".ljust(16)
        escribio = f"escribió={r.escritas}".ljust(20)
        lineas.append(
            f"   {r.tabla.ljust(12)} {leyo}{escribio}{_texto_de_la_decision(r, nota_de_salto)}"
        )
    lineas.append(LINEA)
    return "\n".join(lineas)


# --- Glue: el único lanzador -------------------------------------------------------------------


def _region() -> str:
    return os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION") or "us-east-2"


def _cliente(servicio: str):
    """Cliente de boto3 (import tardío: la VM y las pruebas no lo necesitan hasta aquí)."""
    import boto3

    return boto3.client(servicio, region_name=_region())


def _prefijo_de_nombres() -> str:
    return os.environ.get("PREFIX") or "bigdata"


def _perfil_de_glue(computo: str) -> tuple[str, int, int]:
    """(nombre del job, workers, minutos de plazo) del cómputo glue_small|medium|large."""
    perfil = computo.removeprefix("glue_")
    workers, plazo = PERFILES_DE_GLUE[perfil]
    archivo = Path(__file__).resolve().parents[3] / "airflow" / "framework" / "profiles.yaml"
    if archivo.is_file():
        try:
            with archivo.open("r", encoding="utf-8") as f:
                datos = yaml.safe_load(f)["profiles"][perfil]
            workers, plazo = int(datos["number_of_workers"]), int(datos["timeout"])
        except (OSError, yaml.YAMLError, KeyError, TypeError, ValueError):
            pass  # sin profiles.yaml legible se usan los valores de respaldo
    return f"{_prefijo_de_nombres()}-{perfil}", workers, plazo


def _armar_zip_del_codigo(destino: Path) -> int:
    """Empaca src/pipeline (lo que hay en tu árbol) en un zip; devuelve cuántos archivos."""
    carpeta_pipeline = Path(__file__).resolve().parents[1]
    cuantos = 0
    with zipfile.ZipFile(destino, "w", zipfile.ZIP_DEFLATED) as zip_:
        for archivo in sorted(carpeta_pipeline.rglob("*")):
            if not archivo.is_file() or "__pycache__" in archivo.parts or archivo.suffix == ".pyc":
                continue
            zip_.write(archivo, Path("pipeline") / archivo.relative_to(carpeta_pipeline))
            cuantos += 1
    return cuantos


def _subir_codigo_de_dev(bucket: str) -> str:
    """Sube el código de dev a s3://<lake>/code/dev/pipeline.zip. NUNCA toca code/pipeline.zip.

    Ese es el zip de prod y solo lo escribe el CI/CD. Así un job de Glue lanzado desde dev
    ejecuta TU código, no el de main.
    """
    clave = "code/dev/pipeline.zip"
    with tempfile.TemporaryDirectory(prefix="codigo-dev-") as tmp:
        zip_local = Path(tmp) / "pipeline.zip"
        cuantos = _armar_zip_del_codigo(zip_local)
        print(f"SUBE     s3://{bucket}/{clave}  ({cuantos} archivos de tu src/pipeline)")
        _cliente("s3").upload_file(str(zip_local), bucket, clave)
    return f"s3://{bucket}/{clave}"


def _argumentos_del_job(paso: str, corrida: Corrida, mes: str, bucket: str) -> dict[str, str]:
    """Argumentos del job run (Glue pide texto en todos). Prod no lleva --extra-py-files."""
    if corrida.entorno == "prod":
        secreto = f"{_prefijo_de_nombres()}/snowflake_prod"
    else:
        secreto = f"{_prefijo_de_nombres()}/snowflake"
    return {
        "--step": paso,
        "--env": corrida.entorno,
        "--mes": mes,
        "--limite": corrida.limite,
        "--reprocesar": "true" if corrida.reprocesar else "false",
        "--computo": corrida.computo,
        "--lake-bucket": bucket,
        "--snowflake-secret": secreto,
    }


def _inicio_en_utc(valor) -> datetime | None:
    """El INICIO de un registro de control (texto ISO o datetime) como datetime sin zona, en UTC."""
    if isinstance(valor, str):
        try:
            valor = datetime.fromisoformat(valor)
        except ValueError:
            return None
    if not isinstance(valor, datetime):
        return None
    if valor.tzinfo is not None:
        valor = valor.astimezone(UTC).replace(tzinfo=None)
    return valor


def _resultados_desde_control(
    corrida: Corrida, paso: str, mes: str, desde: datetime
) -> list[Resultado]:
    """Lo que Glue dejó en la tabla de control desde `desde`: el último registro de cada tabla."""
    from pipeline.herramientas.control import consultar_control  # tardío: trae Snowflake

    resultados = []
    for tabla, mes_de_la_tabla in tablas_del_paso(paso, mes):
        registros = consultar_control(corrida.entorno, tabla, paso, mes_de_la_tabla)
        ultimo = registros[-1] if registros else None
        inicio = _inicio_en_utc(ultimo.get("inicio")) if ultimo else None
        if ultimo and inicio and inicio >= desde:
            leidas = ultimo.get("leidas")
            resultados.append(
                Resultado(
                    tabla,
                    paso,
                    mes_de_la_tabla,
                    int(leidas) if leidas is not None else 0,
                    int(ultimo["filas"]),
                    "REGISTRÓ",
                )
            )
        else:
            resultados.append(Resultado(tabla, paso, mes_de_la_tabla, 0, 0, "SE SALTÓ"))
    return resultados


def _esperar_el_job(glue, job: str, run_id: str) -> tuple[str, str]:
    """Consulta get_job_run hasta que el job termine. Devuelve (estado final, mensaje de error)."""
    ultimo_estado = ""
    while True:
        datos = glue.get_job_run(JobName=job, RunId=run_id)["JobRun"]
        estado = datos["JobRunState"]
        if estado != ultimo_estado:
            print(f"GLUE     {job} {run_id}: {estado}")
            ultimo_estado = estado
        if estado in ESTADOS_FINALES_DE_GLUE:
            return estado, datos.get("ErrorMessage", "")
        time.sleep(SEGUNDOS_ENTRE_CONSULTAS)


def lanzar_en_glue(paso: str, corrida: Corrida) -> None:
    """ÚNICO lanzador de Glue (lo usan make, el cuaderno y el DAG). Un job run por mes.

    - dev: empaca TU src/pipeline, lo sube a s3://<lake>/code/dev/pipeline.zip y lanza el job con
      ese zip (los argumentos del run reemplazan los del job). Nunca toca code/pipeline.zip.
    - prod: no sube nada; el job usa code/pipeline.zip (el que dejó el CI/CD) y recibe --env prod.
    Espera con get_job_run, imprime la consola de Glue y cierra con lo que quedó en la tabla de
    control (o «SE SALTÓ (ver log de Glue)»). Falla si el job falla.
    """
    if paso not in ("bronze", "silver", "gold"):
        raise ConfigError(
            f"Glue corre bronze, silver o gold (no '{paso}'): snowflake no usa Spark."
        )
    if corrida.computo not in COMPUTOS or corrida.computo == "code_editor":
        raise ConfigError(f"lanzar_en_glue necesita un cómputo glue_*, no '{corrida.computo}'.")

    bucket = bucket_del_lake()
    job, workers, plazo = _perfil_de_glue(corrida.computo)
    codigo = None
    if corrida.entorno == "dev":
        codigo = _subir_codigo_de_dev(bucket)
    glue = _cliente("glue")
    region = _region()

    for mes in corrida.meses:
        argumentos = _argumentos_del_job(paso, corrida, mes, bucket)
        if codigo:
            argumentos["--extra-py-files"] = codigo
        desde = datetime.now(UTC).replace(tzinfo=None, microsecond=0)
        respuesta = glue.start_job_run(
            JobName=job,
            Arguments=argumentos,
            # Glue exige el tipo de worker cuando se cambia el número de workers en la corrida.
            WorkerType="G.1X",
            NumberOfWorkers=workers,
            Timeout=plazo,
        )
        run_id = respuesta["JobRunId"]
        consola = (
            f"https://{region}.console.aws.amazon.com/gluestudio/home?region={region}"
            f"#/job/{job}/run/{run_id}"
        )
        print(f"GLUE     job {job}, run {run_id}, mes {mes}")
        print(f"CONSOLA  {consola}")
        print(f"SPARK UI {consola}/sparkui")

        estado, mensaje = _esperar_el_job(glue, job, run_id)
        if estado != "SUCCEEDED":
            raise RuntimeError(
                f"El job de Glue {job} (run {run_id}) terminó en {estado}: "
                f"{mensaje or 'sin mensaje'}. "
                f"Revisa los logs en {consola}"
            )
        try:
            resultados = _resultados_desde_control(
                corrida, paso, mes, desde - timedelta(seconds=MARGEN_DE_RELOJ)
            )
        except Exception as error:  # sin tabla de control no hay cierre; el job sí terminó bien
            print(
                f"AVISO    el job terminó bien, pero no pude leer la tabla de control "
                f"({type(error).__name__}: {error}). Mira el log de Glue."
            )
            continue
        cierre_del_mes = cierre(
            replace(corrida, meses=(mes,)), paso, mes, resultados, nota_de_salto="(ver log de Glue)"
        )
        print(cierre_del_mes)
