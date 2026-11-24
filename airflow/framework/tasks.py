"""Tareas de los DAGs `pipeline_taxi` y `resetear_entorno`.

El entorno no se elige (diseño de la clase 7, regla R1): cada Airflow lo fija con la variable
PIPELINE_ENTORNO. El del Code Editor es dev; la VM (que despliega el CI/CD) es prod. Lo que sí se
elige al lanzar `pipeline_taxi` son las cuatro perillas de `pipeline.yaml`: cómputo, límite, mes y
reprocesar. Los valores del formulario ganan sobre `pipeline.yaml`.

Las tareas de `pipeline_taxi` se llaman igual que las funciones de `pipeline/correr.py`
(correr_bronze, correr_silver, correr_gold, cargar_snowflake) y hay solo tres formas de lanzarlas:
- cómputo code_editor: el CLI (`python -m pipeline.run --paso ...`) con el Python del .venv del
  repo; el banner sale en el log de la tarea.
- cómputo glue_*: se llama directo a `correr_<paso>(...)` en el proceso de Airflow, que usa
  `lanzar_en_glue` (no hace falta Spark: en la VM `pipeline/` está montado pero sin pyspark).
- cargar_snowflake: se llama a `cargar_snowflake(..., conexion=...)` con la conexión
  `snowflake_default`, sin Spark ni Glue.

Este módulo no importa pyspark ni `pipeline` al cargarse (los DAGs se parsean aunque `pipeline`
no esté): `pipeline` se importa dentro de las funciones, después de `preparar_importaciones()`.
"""

from __future__ import annotations

import logging
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

from airflow.providers.standard.operators.python import PythonOperator
from airflow.sdk import Param

log = logging.getLogger(__name__)

# Raíz del repo (airflow/framework/tasks.py -> repo). En el Code Editor los DAGs se leen del repo;
# en la VM no hay repo: `pipeline/` está montado en /opt/airflow/pipeline (ya en PYTHONPATH).
REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON_DEL_REPO = REPO_ROOT / ".venv" / "bin" / "python"

SNOWFLAKE_CONN_ID = "snowflake_default"

ENTORNOS = ("dev", "prod")
# Las mismas listas que pipeline.herramientas.corrida (contrato 1.2); una prueba las compara.
COMPUTOS = ("code_editor", "glue_small", "glue_medium", "glue_large")
COMPUTOS_DE_GLUE = tuple(c for c in COMPUTOS if c.startswith("glue_"))
LIMITES = ("1000", "100000", "todos")
DEFECTOS = {"computo": "code_editor", "limite": "1000", "mes": "2024-01", "reprocesar": False}

# En prod el curso procesa un solo mes por defecto (sin mes se lanzarían los doce).
MES_DE_PROD = "2024-01"
COMPUTO_DE_PROD = "glue_medium"
LIMITE_DE_PROD = "todos"

PATRON_MES = r"^(\d{4}-(0[1-9]|1[0-2]))?$"
_RE_MES = re.compile(PATRON_MES)

# task_id -> (paso del CLI, nombre de la función de pipeline/correr.py). Son los mismos nombres.
TAREAS_DEL_PIPELINE = {
    "correr_bronze": "bronze",
    "correr_silver": "silver",
    "correr_gold": "gold",
    "cargar_snowflake": "snowflake",
}

PREFIJO_BORRAR = "borrar"


class ParametrosNoPermitidos(ValueError):
    """Los parámetros de la corrida no se pueden usar en este Airflow (mensaje en español)."""


# --- entorno e importaciones --------------------------------------------------------------------


def entorno_del_airflow() -> str:
    """'dev' o 'prod': lo fija PIPELINE_ENTORNO (por defecto dev). No se elige al lanzar."""
    entorno = os.environ.get("PIPELINE_ENTORNO") or "dev"
    if entorno not in ENTORNOS:
        raise ValueError(
            f"PIPELINE_ENTORNO inválido {entorno!r}: usa 'dev' (Code Editor) o 'prod' (VM)"
        )
    return entorno


def nombre_del_entorno(entorno: str) -> str:
    """Cómo se escribe el entorno en el doc_md y las descripciones."""
    return "PROD ⚠ (producción)" if entorno == "prod" else "DEV"


def preparar_importaciones() -> None:
    """Pone <repo>/src en el camino de importación si existe (Code Editor).

    En la VM no hay repo: `pipeline` ya se importa desde /opt/airflow/pipeline.
    """
    src = REPO_ROOT / "src"
    if src.is_dir() and str(src) not in sys.path:
        sys.path.insert(0, str(src))


# --- formulario de pipeline_taxi ----------------------------------------------------------------


def opciones_del_formulario(entorno: str) -> dict[str, list[str]]:
    """Lo que ofrece cada lista del formulario según el entorno."""
    if entorno == "prod":
        return {"computo": list(COMPUTOS_DE_GLUE), "limite": [LIMITE_DE_PROD]}
    return {"computo": list(COMPUTOS), "limite": list(LIMITES)}


def _valores_del_yaml() -> tuple[dict[str, Any], list[str]]:
    """Valores normalizados de pipeline.yaml y avisos. NUNCA lanza (el DAG se parsea siempre)."""
    try:
        preparar_importaciones()
        from pipeline.herramientas.corrida import valores_de_pipeline_yaml

        valores = dict(valores_de_pipeline_yaml())
    except Exception as error:  # noqa: BLE001 - cualquier fallo se vuelve defecto + aviso
        aviso = (
            f"no pude leer pipeline.yaml ({type(error).__name__}: {error}); "
            "se usaron los valores por defecto"
        )
        log.warning("pipeline_taxi: %s", aviso)
        return dict(DEFECTOS), [aviso]

    avisos = [str(a) for a in valores.pop("avisos", [])]
    for aviso in avisos:
        log.warning("pipeline_taxi: %s", aviso)
    for campo, defecto in DEFECTOS.items():
        valores.setdefault(campo, defecto)
    return valores, avisos


def defectos_del_formulario(entorno: str) -> tuple[dict[str, Any], list[str]]:
    """(valores iniciales del formulario, avisos). Nunca lanza.

    dev: salen de pipeline.yaml (con defecto y aviso si algo está mal). prod: no lee el yaml.
    """
    if entorno == "prod":
        return (
            {
                "computo": COMPUTO_DE_PROD,
                "limite": LIMITE_DE_PROD,
                "mes": MES_DE_PROD,
                "reprocesar": False,
            },
            [],
        )
    valores, avisos = _valores_del_yaml()
    # Con code_editor 'todos' no se puede: el formulario arranca con 1000 y lo avisa.
    if valores["computo"] == "code_editor" and valores["limite"] == "todos":
        aviso = "pipeline.yaml pide limite todos con code_editor; el formulario arranca con 1000"
        log.warning("pipeline_taxi: %s", aviso)
        valores["limite"] = DEFECTOS["limite"]
        avisos.append(aviso)
    return valores, avisos


def parametros_del_formulario(entorno: str) -> tuple[dict[str, Param], list[str]]:
    """Los Params de Airflow 3 de `pipeline_taxi` (aparecen en «Trigger DAG») y los avisos.

    Son cuatro: computo, limite, mes y reprocesar. El entorno NO es un parámetro.
    """
    defectos, avisos = defectos_del_formulario(entorno)
    opciones = opciones_del_formulario(entorno)
    en_prod = entorno == "prod"
    params = {
        "computo": Param(
            defectos["computo"],
            type="string",
            enum=opciones["computo"],
            title="Cómputo",
            description=(
                "Dónde se calcula: glue_small | glue_medium | glue_large."
                if en_prod
                else "Dónde se calcula: code_editor (Spark en el Code Editor) | glue_small | "
                "glue_medium | glue_large. Pasar de uno a otro cambia solo esto."
            ),
        ),
        "limite": Param(
            defectos["limite"],
            type="string",
            enum=opciones["limite"],
            title="Límite de filas",
            description=(
                "Prod siempre procesa todo: todos."
                if en_prod
                else "Filas por fuente: 1000 | 100000 | todos. Con code_editor solo 1000 o 100000."
            ),
        ),
        "mes": Param(
            defectos["mes"],
            type="string",
            pattern=PATRON_MES,
            title="Mes",
            description=(
                "AAAA-MM. Durante el curso el defecto de prod es 2024-01; vacío lanzaría "
                "los doce meses de config/prod.yaml."
                if en_prod
                else "AAAA-MM. Vacío = los meses de config/dev.yaml."
            ),
        ),
        "reprocesar": Param(
            bool(defectos["reprocesar"]),
            type="boolean",
            title="Reprocesar",
            description="Marcada: ignora la tabla de control y procesa el mes otra vez.",
        ),
    }
    return params, avisos


def _como_booleano(valor: Any) -> bool:
    if isinstance(valor, bool):
        return valor
    if isinstance(valor, str) and valor.strip().lower() in ("true", "false"):
        return valor.strip().lower() == "true"
    raise ParametrosNoPermitidos(f"reprocesar inválido {valor!r}: usa true o false.")


def validar_corrida(entorno: str, params: dict[str, Any]) -> dict[str, Any]:
    """Valida lo que llegó del formulario (o de `dags trigger --conf`) y lo deja normalizado.

    Falla con un mensaje claro ANTES de tocar nada. Devuelve {computo, limite, mes, reprocesar}
    con limite en texto, mes en texto (vacío = todos los meses del entorno) y reprocesar en bool.
    """
    computo = str(params.get("computo") or "").strip()
    limite = str(params.get("limite") if params.get("limite") is not None else "").strip().lower()
    mes = str(params.get("mes") or "").strip()
    reprocesar = _como_booleano(params.get("reprocesar", False))

    if computo not in COMPUTOS:
        raise ParametrosNoPermitidos(
            f"computo inválido {computo!r}. Válidos: {', '.join(COMPUTOS)}"
        )
    if limite not in LIMITES:
        raise ParametrosNoPermitidos(f"limite inválido {limite!r}. Válidos: {', '.join(LIMITES)}")
    if not _RE_MES.match(mes):
        raise ParametrosNoPermitidos(f"mes inválido {mes!r}: se espera AAAA-MM (o vacío).")

    if entorno == "prod":
        if computo not in COMPUTOS_DE_GLUE:
            raise ParametrosNoPermitidos(
                f"Prod solo corre con Glue ({', '.join(COMPUTOS_DE_GLUE)}), no con {computo}. "
                "No se corrió nada."
            )
        if limite != LIMITE_DE_PROD:
            raise ParametrosNoPermitidos(
                f"Prod siempre procesa todo: el límite es '{LIMITE_DE_PROD}', no '{limite}'. "
                "No se corrió nada."
            )
    elif computo == "code_editor" and limite == "todos":
        raise ParametrosNoPermitidos(
            "Con code_editor el límite es 1000 o 100000: 'todos' es para Glue. "
            "Elige glue_small, glue_medium o glue_large."
        )
    return {"computo": computo, "limite": limite, "mes": mes, "reprocesar": reprocesar}


def documentacion_del_dag(entorno: str, avisos: list[str], defectos: dict[str, Any]) -> str:
    """El doc_md de pipeline_taxi: dice el entorno, qué se puede cambiar y los avisos del yaml."""
    en_prod = entorno == "prod"
    opciones = opciones_del_formulario(entorno)
    texto = [
        f"# pipeline_taxi · entorno {nombre_del_entorno(entorno)}",
        "",
        f"**Entorno: {nombre_del_entorno(entorno)}.** El entorno no se elige al lanzar: lo fija "
        "este Airflow (el del Code Editor es dev; la VM, que despliega el CI/CD, es prod). "
        + (
            "Aquí todo queda en `s3://<lake>/prod/`, `BIGDATA.PROD` y `BIGDATA.CONTROL_PROD`."
            if en_prod
            else "Aquí todo queda en `s3://<lake>/dev/`, `BIGDATA.DEV` y `BIGDATA.CONTROL_DEV`."
        ),
        "",
        "Cuatro tareas, en orden, con el mismo nombre que las funciones de `pipeline/correr.py`: "
        "`correr_bronze` → `correr_silver` → `correr_gold` → `cargar_snowflake`.",
        "",
        "| Perilla | Qué ofrece el formulario | Valor inicial |",
        "|---|---|---|",
        f"| `computo` | {' · '.join(opciones['computo'])} | `{defectos['computo']}` |",
        f"| `limite` | {' · '.join(opciones['limite'])} | `{defectos['limite']}` |",
        f"| `mes` | AAAA-MM (vacío = todos los del entorno) | `{defectos['mes'] or '(vacío)'}` |",
        f"| `reprocesar` | casilla | {'marcada' if defectos['reprocesar'] else 'sin marcar'} |",
        "",
    ]
    if en_prod:
        texto += [
            "En prod solo hay Glue y el límite es siempre `todos`; no se lee `pipeline.yaml`. "
            "Durante el curso el mes viene en `2024-01` (vacío lanzaría los doce meses). "
            "Un cómputo o un límite ajenos (por `--conf`) hacen fallar la primera tarea antes "
            "de tocar nada.",
        ]
    else:
        texto += [
            "Los valores iniciales salen de `pipeline.yaml`; lo que pones en el formulario gana. "
            "Con `code_editor` el límite es 1000 o 100000 (otra combinación falla en la primera "
            "tarea con un mensaje claro). Un cambio en `pipeline.yaml` tarda unos 30 segundos "
            "en llegar al formulario.",
        ]
    if avisos:
        texto += ["", "**Avisos al leer `pipeline.yaml`:**", ""] + [f"- {a}" for a in avisos]
    texto += [
        "",
        "Cada tarea imprime el mismo banner que `make correr` (con el entorno) y su cierre.",
    ]
    return "\n".join(texto)


# --- las tareas de pipeline_taxi ----------------------------------------------------------------


def comando_del_cli(paso: str, valores: dict[str, Any], mes: str) -> list[str]:
    """El comando del CLI para un paso con cómputo code_editor y un mes concreto."""
    return [
        str(PYTHON_DEL_REPO),
        "-m",
        "pipeline.run",
        "--paso",
        paso,
        "--computo",
        valores["computo"],
        "--limite",
        valores["limite"],
        "--mes",
        mes,
        "--reprocesar",
        "true" if valores["reprocesar"] else "false",
    ]


def entorno_del_cli() -> dict[str, str]:
    """Variables del CLI: todo lo de Airflow, con PIPELINE_ENTORNO=dev y <repo>/src en el camino."""
    env = dict(os.environ)
    env["PIPELINE_ENTORNO"] = "dev"
    src = str(REPO_ROOT / "src")
    env["PYTHONPATH"] = os.pathsep.join(p for p in (src, env.get("PYTHONPATH", "")) if p)
    return env


def _correr_comando(comando: list[str], env: dict[str, str], cwd: Path) -> int:
    """Corre el comando y copia su salida (el banner y el cierre) al log de la tarea."""
    proceso = subprocess.Popen(
        comando,
        cwd=cwd,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    assert proceso.stdout is not None
    for linea in proceso.stdout:
        print(linea.rstrip("\n"), flush=True)
    return proceso.wait()


def _meses_para_el_cli(valores: dict[str, Any], entorno: str) -> list[str]:
    """Un mes, o los de config/<entorno>.yaml si el formulario quedó vacío (el CLI no lo admite)."""
    if valores["mes"]:
        return [valores["mes"]]
    preparar_importaciones()
    from pipeline.herramientas.rutas import meses_del_entorno

    return meses_del_entorno(entorno)


def conexion_snowflake() -> Any:
    """Conexión `snowflake_default`: rol BIGDATA_DEV en el Code Editor, BIGDATA_PROD en la VM."""
    from airflow.providers.snowflake.hooks.snowflake import SnowflakeHook

    return SnowflakeHook(snowflake_conn_id=SNOWFLAKE_CONN_ID).get_conn()


def _banner_de_la_tarea(task_id: str, entorno: str, valores: dict[str, Any]) -> None:
    print(
        f"[{task_id}] entorno={nombre_del_entorno(entorno)} computo={valores['computo']} "
        f"limite={valores['limite']} mes={valores['mes'] or '(todos)'} "
        f"reprocesar={str(valores['reprocesar']).lower()}",
        flush=True,
    )


def ejecutar_paso(task_id: str, entorno: str, params: dict[str, Any]) -> None:
    """El cuerpo de las cuatro tareas de pipeline_taxi (ver la forma de lanzar en el docstring)."""
    paso = TAREAS_DEL_PIPELINE[task_id]
    valores = validar_corrida(entorno, params)
    _banner_de_la_tarea(task_id, entorno, valores)
    preparar_importaciones()

    if paso == "snowflake":
        from pipeline.correr import cargar_snowflake
        from pipeline.herramientas.control import exigir_rol_del_entorno

        conexion = conexion_snowflake()
        try:
            exigir_rol_del_entorno(entorno, conexion)
            cargar_snowflake(conexion=conexion, **valores)
        finally:
            conexion.close()
        return

    if valores["computo"] == "code_editor":
        # Solo dev llega aquí (validar_corrida rechaza code_editor en prod).
        if not PYTHON_DEL_REPO.is_file():
            raise RuntimeError(
                f"No encuentro el Python del repo ({PYTHON_DEL_REPO}). Corre `make setup` "
                "para crear el .venv y vuelve a lanzar."
            )
        for mes in _meses_para_el_cli(valores, entorno):
            codigo = _correr_comando(
                comando_del_cli(paso, valores, mes), entorno_del_cli(), REPO_ROOT
            )
            if codigo != 0:
                raise RuntimeError(
                    f"El paso {paso} (mes {mes}) terminó con código {codigo}. "
                    "El motivo está en las líneas de arriba."
                )
        return

    from pipeline import correr

    getattr(correr, task_id)(**valores)


def tarea_del_pipeline(task_id: str, entorno: str) -> PythonOperator:
    """Tarea de `pipeline_taxi`: se llama como la función de pipeline/correr.py que ejecuta."""
    if task_id not in TAREAS_DEL_PIPELINE:
        raise ValueError(f"tarea desconocida {task_id!r}; válidas: {sorted(TAREAS_DEL_PIPELINE)}")
    if entorno not in ENTORNOS:
        raise ValueError(f"entorno inválido {entorno!r}; válidos: {', '.join(ENTORNOS)}")
    return PythonOperator(
        task_id=task_id,
        python_callable=_cuerpo_de_la_tarea,
        op_kwargs={"task_id": task_id, "entorno": entorno},
        retries=0,
    )


def _cuerpo_de_la_tarea(task_id: str, entorno: str, params: dict[str, Any]) -> None:
    ejecutar_paso(task_id, entorno, dict(params))


# --- resetear_entorno ---------------------------------------------------------------------------

TAREAS_DEL_RESETEO = (
    "validar",
    "contar",
    "vaciar_control",
    "borrar_snowflake",
    "borrar_s3",
    "resumen",
)


def confirmacion_esperada(entorno: str, cuenta: str | None = None) -> str:
    """Lo que hay que escribir para borrar: 'borrar dev' o 'borrar prod <ID de la cuenta AWS>'."""
    if entorno == "prod":
        if not cuenta:
            raise ValueError("Para prod la confirmación lleva el ID de la cuenta AWS")
        return f"{PREFIJO_BORRAR} prod {cuenta}"
    return f"{PREFIJO_BORRAR} {entorno}"


def cuenta_aws() -> str:
    """ID de la cuenta AWS según sts (el que se escribe en la confirmación de prod)."""
    import boto3

    return str(boto3.client("sts").get_caller_identity()["Account"])


def _normalizar(texto: Any) -> str:
    # Se aceptan mayúsculas, espacios de más y comillas alrededor: «Borrar  DEV» vale igual.
    limpio = str(texto or "").strip().strip("\"'«»“”").lower()
    return " ".join(limpio.split())


def validar_reseteo(entorno: str, params: dict[str, Any], cuenta: str | None = None) -> dict:
    """Valida el formulario de resetear_entorno antes de tocar nada.

    Devuelve {entorno, solo_listar, conservar_crudo}. El entorno del formulario solo puede ser el
    de este Airflow. Para borrar (solo_listar=false) la confirmación escrita debe ser exacta; en
    prod incluye el ID de la cuenta AWS (`cuenta` se pide a sts si no llega).
    """
    pedido = params.get("entorno", entorno)
    if pedido != entorno:
        raise ParametrosNoPermitidos(
            f"Este Airflow solo resetea su propio entorno ({entorno}); pediste {pedido!r}. "
            "No se borró nada."
        )
    del_proceso = os.environ.get("PIPELINE_ENTORNO") or "dev"
    if del_proceso != entorno:
        raise ParametrosNoPermitidos(
            f"El DAG es de {entorno} pero PIPELINE_ENTORNO dice {del_proceso!r}. No se borró nada."
        )
    solo_listar = _como_booleano(params.get("solo_listar", True))
    conservar_crudo = _como_booleano(params.get("conservar_crudo", False))
    if not solo_listar:
        if entorno == "prod" and cuenta is None:
            cuenta = cuenta_aws()
        esperado = confirmacion_esperada(entorno, cuenta)
        if _normalizar(params.get("confirmacion")) != esperado:
            raise ParametrosNoPermitidos(
                "La confirmación no coincide: no se borró nada. Para borrar "
                + (
                    f"escribe exactamente «{esperado}»."
                    if entorno == "dev"
                    else f"escribe «{PREFIJO_BORRAR} prod» seguido del ID de la cuenta AWS "
                    "(el que muestra `aws sts get-caller-identity`)."
                )
            )
    return {"entorno": entorno, "solo_listar": solo_listar, "conservar_crudo": conservar_crudo}


def _reseteo():
    """El módulo de reseteo (import tardío: trae boto3 y Snowflake solo cuando se usa)."""
    preparar_importaciones()
    from pipeline.herramientas import reseteo

    return reseteo


def _tarea_validar(entorno: str, params: dict[str, Any]) -> dict:
    valores = validar_reseteo(entorno, params)
    modo = "SOLO LISTAR (no se borra nada)" if valores["solo_listar"] else "BORRAR DE VERDAD"
    print(
        f"[validar] entorno={nombre_del_entorno(entorno)} · {modo} · "
        f"conservar_crudo={valores['conservar_crudo']}",
        flush=True,
    )
    return valores


def _tarea_contar(entorno: str, params: dict[str, Any]) -> dict:
    valores = validar_reseteo(entorno, params)
    reseteo = _reseteo()
    conexion = conexion_snowflake()
    try:
        registros = reseteo.contar_control(entorno, conexion)
        tablas = reseteo.borrar_tablas_snowflake(entorno, solo_listar=True, conexion=conexion)
    finally:
        conexion.close()
    capas = reseteo.borrar_capas_s3(
        entorno, solo_listar=True, conservar_crudo=valores["conservar_crudo"]
    )
    cuenta = {
        "control": registros,
        "tablas": tablas,
        "s3_objetos": capas["objetos"],
        "s3_bytes": capas["bytes"],
        "s3_por_capa": capas["por_capa"],
        "s3_conservados": capas["conservados"],
        "s3_prefijo": capas["prefijo"],
    }
    print(
        f"[contar] {nombre_del_entorno(entorno)}\n"
        f"  tabla de control: {registros} registro(s)\n"
        f"  Snowflake {reseteo.esquema_del_entorno(entorno)}: {len(tablas)} tabla(s) o vista(s) "
        f"{tablas}\n"
        f"  S3 {capas['prefijo']}: {capas['objetos']} objeto(s), {capas['bytes']} bytes, "
        f"por capa {capas['por_capa']}, conservados {capas['conservados']}",
        flush=True,
    )
    return cuenta


def _previo(ti: Any, tarea: str) -> dict:
    valor = ti.xcom_pull(task_ids=tarea)
    if not isinstance(valor, dict):
        raise RuntimeError(f"No encontré el resultado de la tarea {tarea}: me detengo.")
    return valor


def _tarea_vaciar_control(entorno: str, params: dict[str, Any], ti: Any) -> dict:
    valores = validar_reseteo(entorno, params)
    previo = _previo(ti, "contar")
    if valores["solo_listar"]:
        print("[vaciar_control] solo_listar: no se borra la tabla de control.", flush=True)
        return {"borrados": 0}
    from pipeline.herramientas.control import exigir_rol_del_entorno, vaciar_control

    reseteo = _reseteo()
    conexion = conexion_snowflake()
    try:
        exigir_rol_del_entorno(entorno, conexion)
        ahora = reseteo.contar_control(entorno, conexion)
        if ahora != previo["control"]:
            raise RuntimeError(
                f"La tabla de control tenía {previo['control']} registro(s) al contar y tiene "
                f"{ahora} ahora: me detengo. Vuelve a lanzar con solo_listar=true."
            )
        borrados = vaciar_control(entorno, conexion)
    finally:
        conexion.close()
    if borrados != ahora:
        raise RuntimeError(f"Se borraron {borrados} registros de control y se esperaban {ahora}.")
    print(f"[vaciar_control] borré {borrados} registro(s) de la tabla de control.", flush=True)
    return {"borrados": borrados}


def _tarea_borrar_snowflake(entorno: str, params: dict[str, Any], ti: Any) -> dict:
    valores = validar_reseteo(entorno, params)
    previo = _previo(ti, "contar")
    if valores["solo_listar"]:
        print("[borrar_snowflake] solo_listar: no se borra ninguna tabla.", flush=True)
        return {"borradas": []}
    reseteo = _reseteo()
    conexion = conexion_snowflake()
    try:
        ahora = reseteo.borrar_tablas_snowflake(entorno, solo_listar=True, conexion=conexion)
        if sorted(ahora) != sorted(previo["tablas"]):
            raise RuntimeError(
                f"Las tablas cambiaron entre contar y borrar (antes {previo['tablas']}, "
                f"ahora {ahora}): me detengo. Vuelve a lanzar con solo_listar=true."
            )
        borradas = reseteo.borrar_tablas_snowflake(entorno, solo_listar=False, conexion=conexion)
    finally:
        conexion.close()
    print(f"[borrar_snowflake] borré {len(borradas)} objeto(s): {borradas}", flush=True)
    return {"borradas": borradas}


def _tarea_borrar_s3(entorno: str, params: dict[str, Any], ti: Any) -> dict:
    valores = validar_reseteo(entorno, params)
    previo = _previo(ti, "contar")
    if valores["solo_listar"]:
        print("[borrar_s3] solo_listar: no se borra ningún objeto de S3.", flush=True)
        return {"borrados": 0}
    reseteo = _reseteo()
    conservar = valores["conservar_crudo"]
    ahora = reseteo.borrar_capas_s3(entorno, solo_listar=True, conservar_crudo=conservar)
    if ahora["objetos"] != previo["s3_objetos"]:
        raise RuntimeError(
            f"S3 tenía {previo['s3_objetos']} objeto(s) al contar y tiene {ahora['objetos']} "
            "ahora: me detengo. Vuelve a lanzar con solo_listar=true."
        )
    hecho = reseteo.borrar_capas_s3(entorno, solo_listar=False, conservar_crudo=conservar)
    print(
        f"[borrar_s3] borré {hecho['borrados']} objeto(s) de {hecho['prefijo']} "
        f"(conservados: {hecho['conservados']}).",
        flush=True,
    )
    return {"borrados": hecho["borrados"], "conservados": hecho["conservados"]}


def _tarea_resumen(entorno: str, params: dict[str, Any], ti: Any) -> dict:
    valores = validar_reseteo(entorno, params)
    cuenta = _previo(ti, "contar")
    nombre = nombre_del_entorno(entorno)
    if valores["solo_listar"]:
        print(
            f"[resumen] {nombre}: NO se borró nada (solo_listar=true). Esto es lo que se borraría: "
            f"{cuenta['control']} registro(s) de control, {len(cuenta['tablas'])} tabla(s) de "
            f"Snowflake y {cuenta['s3_objetos']} objeto(s) de S3. Para borrar, lanza de nuevo con "
            "solo_listar=false y la confirmación escrita.",
            flush=True,
        )
        return {"borro": False}
    control = _previo(ti, "vaciar_control")
    snowflake = _previo(ti, "borrar_snowflake")
    s3 = _previo(ti, "borrar_s3")
    print(
        f"[resumen] {nombre}: BORRADO. {control['borrados']} registro(s) de control, "
        f"{len(snowflake['borradas'])} tabla(s) o vista(s) de Snowflake, "
        f"{s3['borrados']} objeto(s) de S3 (conservados: {s3['conservados']}). "
        "Athena no se tocó: sus tablas externas apuntan ahora a carpetas vacías.",
        flush=True,
    )
    return {"borro": True}


_CUERPOS_DEL_RESETEO = {
    "validar": _tarea_validar,
    "contar": _tarea_contar,
    "vaciar_control": _tarea_vaciar_control,
    "borrar_snowflake": _tarea_borrar_snowflake,
    "borrar_s3": _tarea_borrar_s3,
    "resumen": _tarea_resumen,
}


def _cuerpo_del_reseteo(task_id: str, entorno: str, params: dict[str, Any], ti: Any = None) -> Any:
    cuerpo = _CUERPOS_DEL_RESETEO[task_id]
    # Cada tarea corre en un proceso nuevo de Airflow: hay que volver a poner <repo>/src en el
    # camino de importación antes de que cualquier tarea importe `pipeline`.
    preparar_importaciones()
    if task_id in ("validar", "contar"):
        return cuerpo(entorno, dict(params))
    return cuerpo(entorno, dict(params), ti)


def parametros_del_reseteo(entorno: str) -> dict[str, Param]:
    """Los Params de `resetear_entorno`. `entorno` solo admite el de este Airflow."""
    en_prod = entorno == "prod"
    return {
        "entorno": Param(
            entorno,
            type="string",
            enum=[entorno],
            title="Entorno",
            description=f"Solo el de este Airflow ({entorno}). No hay otra opción.",
        ),
        "solo_listar": Param(
            True,
            type="boolean",
            title="Solo listar",
            description="Marcada: cuenta y lista lo que se borraría y termina. "
            "Desmárcala para borrar de verdad.",
        ),
        "confirmacion": Param(
            "",
            type="string",
            title="Confirmación",
            description=(
                "Solo para borrar. Escribe «borrar prod» seguido del ID de la cuenta AWS."
                if en_prod
                else "Solo para borrar. Escribe exactamente: borrar dev"
            ),
        ),
        "conservar_crudo": Param(
            False,
            type="boolean",
            title="Conservar el crudo",
            description="Marcada: deja bronze/_crudo/ en S3 (así no se vuelve a descargar).",
        ),
    }


def documentacion_del_reseteo(entorno: str) -> str:
    """El doc_md de resetear_entorno."""
    otro = "prod" if entorno == "dev" else "dev"
    esquema = entorno.upper()
    texto = [
        f"# resetear_entorno · {nombre_del_entorno(entorno)}",
        "",
        f"**Borra el entorno {entorno} completo y solo ese:** el del Airflow donde lo lanzas. "
        f"No toca {otro}.",
        "",
        "| Qué | Cómo |",
        "|---|---|",
        f"| Capas de S3 | todo lo que hay bajo `s3://<lake>/{entorno}/` (bronze con `_crudo`, "
        "silver, "
        "gold). Con «Conservar el crudo» deja `bronze/_crudo/` |",
        f"| Tabla de control | `DELETE FROM BIGDATA.CONTROL_{esquema}.WATERMARK` |",
        f"| Snowflake | `DROP` de cada tabla y vista de `BIGDATA.{esquema}` (el stage "
        "`LAKE_GOLD` y "
        "el formato `PARQUET_FF` no se tocan) |",
        "| Athena | nada: las tablas externas quedan apuntando a carpetas vacías |",
        "",
        "Orden: validar → contar → vaciar_control → borrar_snowflake → borrar_s3 → resumen. "
        "La tabla de control va primero: si algo falla a medias queda «no procesado», nunca "
        "«procesado sin datos».",
        "",
        "**Salvaguardas.** El DAG nace pausado. `solo_listar` viene marcada: la primera corrida "
        "cuenta y lista y termina. Para borrar, lánzalo de nuevo con `solo_listar` desmarcada "
        + (
            "y la confirmación `borrar dev`."
            if entorno == "dev"
            else "y la confirmación `borrar prod <ID de la cuenta AWS>` (las dos cosas juntas: "
            "no hay valor por defecto que borre)."
        ),
        "",
        "Resetear prod cuesta en AWS (volver a procesar todo), en Snowflake y en reputación.",
    ]
    return "\n".join(texto)


def tarea_del_reseteo(task_id: str, entorno: str) -> PythonOperator:
    """Tarea de `resetear_entorno`."""
    if task_id not in _CUERPOS_DEL_RESETEO:
        raise ValueError(f"tarea desconocida {task_id!r}; válidas: {TAREAS_DEL_RESETEO}")
    if entorno not in ENTORNOS:
        raise ValueError(f"entorno inválido {entorno!r}; válidos: {', '.join(ENTORNOS)}")
    return PythonOperator(
        task_id=task_id,
        python_callable=_cuerpo_del_reseteo,
        op_kwargs={"task_id": task_id, "entorno": entorno},
        retries=0,
    )
