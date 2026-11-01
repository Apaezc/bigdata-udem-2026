"""Constructores de tareas reutilizables para los DAGs del template.

Convenciones (CONTRATO.md):
- Jobs Glue `${prefix}-<perfil>` creados por Terraform; perfiles en profiles.yaml.
- Conexión de Snowflake `snowflake_default`.
- `prefix` se lee de la Variable de Airflow `prefix` (default "bigdata") al renderizar la
  tarea, mediante Jinja (`var.value.get`). No se consulta la base de datos al parsear el DAG.

Entorno y cómputo:
- El entorno (dev o prod: dónde quedan los datos) lo fija cada Airflow con PIPELINE_ENTORNO.
- params.computo elige los recursos: spark_local (solo en dev; `pipeline_local_task` corre
  `pipeline.run --env local --engine local` con el Python del repo, en la misma máquina que
  Airflow, sobre la muestra) o glue_small|glue_medium|glue_large (`glue_task` con profile=None).
- mes vacío = todos los meses del entorno; limite vacío = sin recorte. A Glue se le pasa
  "todos" / "0" porque StartJobRun no acepta argumentos vacíos (run_glue.py los ignora).
"""

from __future__ import annotations

import logging
import os
from pathlib import Path
from typing import Any

import yaml
from airflow.providers.amazon.aws.operators.glue import GlueJobOperator
from airflow.providers.common.sql.operators.sql import SQLExecuteQueryOperator
from airflow.providers.standard.operators.bash import BashOperator
from airflow.providers.standard.operators.python import PythonOperator

PROFILES_FILE = Path(__file__).with_name("profiles.yaml")

# Región: la VM exporta AWS_DEFAULT_REGION (compose); por defecto la del contrato (aws_region).
AWS_REGION = os.environ.get("AWS_DEFAULT_REGION", "us-east-2")
SNOWFLAKE_CONN_ID = "snowflake_default"

# Plantilla Jinja: se resuelve en tiempo de ejecución.
PREFIX_TEMPLATE = "{{ var.value.get('prefix', 'bigdata') }}"

VALID_STEPS = ("bronze", "silver", "gold", "all")

# Raíz del repo (airflow/framework/tasks.py -> repo). En el Code Editor los DAGs se leen del repo.
REPO_ROOT = Path(__file__).resolve().parents[2]
MES_ARG = "{{ params.mes or 'todos' }}"
# El límite efectivo lo decide la tarea preparar_entorno (ver limite_efectivo).
LIMITE_XCOM = "ti.xcom_pull(task_ids='preparar_entorno')"
LIMITE_ARG = "{{ " + LIMITE_XCOM + " or 0 }}"

# Spark local: tope de filas por fuente para validar la lógica sin traer todos los datos.
LIMITE_SPARK_LOCAL = 10_000


def load_profiles() -> dict[str, dict[str, Any]]:
    """Devuelve el diccionario de perfiles definido en profiles.yaml."""
    with PROFILES_FILE.open(encoding="utf-8") as fh:
        return yaml.safe_load(fh)["profiles"]


def glue_run_console_url(region: str, job_name: str, run_id: str) -> str:
    """Enlace a la página del job run en la consola de Glue [formato no verificado]."""
    return (
        f"https://{region}.console.aws.amazon.com/gluestudio/home?region={region}"
        f"#/job/{job_name}/run/{run_id}"
    )


def glue_spark_ui_url(region: str, job_name: str, run_id: str) -> str:
    """Enlace al Spark UI del job run en la consola de Glue [formato no verificado]."""
    return glue_run_console_url(region, job_name, run_id) + "/sparkui"


class GlueJobWithLinks(GlueJobOperator):
    """GlueJobOperator que escribe en el log los enlaces a la consola y al Spark UI.

    Si el perfil sale de params.computo, NumberOfWorkers y Timeout llegan como texto (las
    plantillas de Airflow renderizan strings) y StartJobRun exige enteros: se convierten aquí.
    """

    def execute(self, context):  # type: ignore[override]
        for clave in ("NumberOfWorkers", "Timeout"):
            if clave in self.run_job_kwargs:
                self.run_job_kwargs[clave] = int(self.run_job_kwargs[clave])
        return super().execute(context)

    def submit_job(self, context):  # type: ignore[override]
        run_id = super().submit_job(context)
        region = self.region_name or AWS_REGION
        self.log.info(
            "Glue job run (consola): %s",
            glue_run_console_url(region, self.job_name, run_id),
        )
        self.log.info("Spark UI: %s", glue_spark_ui_url(region, self.job_name, run_id))
        return run_id


def _segun_computo(valores: dict[str, Any]) -> str:
    """Plantilla Jinja que elige un valor por perfil a partir de params.computo (glue_<perfil>)."""
    return "{{ " + repr(valores) + "[params.computo.replace('glue_', '')] }}"


def glue_task(
    task_id: str,
    step: str,
    env: str,
    profile: str | None = None,
    mes: str = MES_ARG,
    limite: str = LIMITE_ARG,
) -> GlueJobWithLinks:
    """Tarea que ejecuta un step del pipeline en un job Glue `${prefix}-<perfil>`.

    profile fijo ("small"...) o None para tomarlo de params.computo (glue_small|medium|large).
    El job ejecuta run_glue.py, que fija el engine glue. env: "dev" o "prod".
    """
    if step not in VALID_STEPS:
        raise ValueError(f"step inválido {step!r}; válidos: {VALID_STEPS}")
    if env not in ("dev", "prod"):
        raise ValueError(f"env inválido {env!r}; glue_task admite 'dev' o 'prod'")

    profiles = load_profiles()
    if profile is None:
        job_name = f"{PREFIX_TEMPLATE}-" + "{{ params.computo.replace('glue_', '') }}"
        workers = _segun_computo({p: c["number_of_workers"] for p, c in profiles.items()})
        timeout = _segun_computo({p: c["timeout"] for p, c in profiles.items()})
    elif profile in profiles:
        job_name = profiles[profile]["job"].replace("${prefix}", PREFIX_TEMPLATE)
        workers = profiles[profile]["number_of_workers"]
        timeout = profiles[profile]["timeout"]
    else:
        raise ValueError(f"perfil desconocido {profile!r}; válidos: {sorted(profiles)}")

    return GlueJobWithLinks(
        task_id=task_id,
        job_name=job_name,
        script_args={"--step": step, "--env": env, "--mes": mes, "--limite": limite},
        run_job_kwargs={
            # StartJobRun exige WorkerType junto con NumberOfWorkers (los jobs son G.1X).
            "WorkerType": "G.1X",
            "NumberOfWorkers": workers,
            "Timeout": timeout,
        },
        region_name=AWS_REGION,
        wait_for_completion=True,
        # Copia al log de la tarea los logs del job (CloudWatch /aws-glue/jobs/...): errores de
        # Spark visibles en Airflow. El rol que ejecuta Airflow necesita leer esos logs.
        verbose=True,
        # Sin durable se mantienen exactamente los script_args del contrato
        # (durable añade --airflow_task_uuid).
        durable=False,
    )


def snowflake_task(
    task_id: str, sql_file: str, params: dict[str, Any] | None = None
) -> SQLExecuteQueryOperator:
    """Tarea que ejecuta un archivo SQL (relativo a la carpeta dags/) en Snowflake."""
    return SQLExecuteQueryOperator(
        task_id=task_id,
        conn_id=SNOWFLAKE_CONN_ID,
        sql=sql_file,
        split_statements=True,
        params=params or {},
    )


def limite_efectivo(entorno: str, computo: str, limite: int | None) -> int | None:
    """Máximo de filas por fuente para esta corrida.

    - spark_local (solo dev): como mucho LIMITE_SPARK_LOCAL; menos si el desarrollador pide menos.
    - Glue en dev: el límite pedido, o ninguno (dev en Glue sirve para probar a escala real).
    - prod: nunca hay límite (se ignora el parámetro).
    """
    if entorno == "prod":
        return None
    if computo == "spark_local":
        return min(limite, LIMITE_SPARK_LOCAL) if limite else LIMITE_SPARK_LOCAL
    return limite or None


def _preparar_entorno(entorno: str, **context) -> int | None:
    params = context["params"]
    limite = limite_efectivo(entorno, params["computo"], params.get("limite"))
    log = logging.getLogger("airflow.task")
    log.info(
        "Entorno: %s | cómputo: %s | meses: %s",
        entorno,
        params["computo"],
        params.get("mes") or "todos",
    )
    if params["computo"] == "spark_local":
        log.info(
            "Spark local: cada fuente se lee con máximo %d filas. No pruebes con todos los "
            "datos en local (la memoria del Code Editor es limitada y no aprendes nada nuevo): "
            "valida aquí la lógica y usa glue_small o mayor para probar a escala.",
            limite,
        )
    elif entorno == "prod" and params.get("limite"):
        log.warning("En prod no se aplican límites: se ignora limite=%s.", params["limite"])
    else:
        log.info("Límite de filas: %s", limite or "ninguno")
    return limite


def preparar_entorno_task(entorno: str) -> PythonOperator:
    """Primer paso del DAG: decide el límite de filas de la corrida y lo explica en el log."""
    return PythonOperator(
        task_id="preparar_entorno",
        python_callable=_preparar_entorno,
        op_kwargs={"entorno": entorno},
    )


def pipeline_local_task(task_id: str, step: str) -> BashOperator:
    """Ejecuta un step del pipeline con Spark local (env local) en la máquina de Airflow."""
    if step not in VALID_STEPS:
        raise ValueError(f"step inválido {step!r}; válidos: {VALID_STEPS}")
    python = REPO_ROOT / ".venv" / "bin" / "python"
    comando = (
        f'cd "{REPO_ROOT}" && PYTHONPATH="{REPO_ROOT}/src" "{python}" -m pipeline.run '
        f"--step {step} --env local --engine local"
        "{% if params.mes %} --mes {{ params.mes }}{% endif %}"
        "{% set lim = " + LIMITE_XCOM + " %}{% if lim %} --limite {{ lim }}{% endif %}"
    )
    return BashOperator(task_id=task_id, bash_command=comando)
