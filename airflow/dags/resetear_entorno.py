"""DAG resetear_entorno: vacía el entorno de ESTE Airflow para repetir el pipeline desde cero.

    validar >> contar >> vaciar_control >> borrar_snowflake >> borrar_s3 >> resumen

El mismo archivo llega a los dos Airflow y cada uno resetea solo su propio entorno (el que fija
PIPELINE_ENTORNO): el del Code Editor resetea dev; la VM, con el rol de prod, resetea prod. El de
dev no puede tocar PROD ni CONTROL_PROD (Snowflake se lo impide) y el de prod no tiene acceso a
dev/.

Qué borra: los objetos de S3 bajo s3://<lake>/<entorno>/, los registros de
BIGDATA.CONTROL_<ENTORNO>.WATERMARK y las tablas y vistas de BIGDATA.<ENTORNO>. No toca el stage
LAKE_GOLD ni el formato PARQUET_FF (los gestiona Terraform), ni el otro entorno, ni Athena.

Salvaguardas: el DAG nace pausado y sin calendario; `solo_listar` viene marcada (la primera
corrida cuenta, lista y termina); para borrar hay que desmarcarla y escribir la confirmación
(`borrar dev`; en prod, `borrar prod <ID de la cuenta AWS>`); antes de borrar se exige el rol del
entorno y se detiene si el recuento cambió.
"""

from __future__ import annotations

import sys
from datetime import datetime
from pathlib import Path

from airflow.sdk import DAG

# airflow/ es la raíz del paquete `framework`.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from framework.tasks import (
    documentacion_del_reseteo,
    entorno_del_airflow,
    nombre_del_entorno,
    parametros_del_reseteo,
    tarea_del_reseteo,
)

ENTORNO = entorno_del_airflow()

with DAG(
    dag_id="resetear_entorno",
    schedule=None,
    start_date=datetime(2024, 1, 1),
    catchup=False,
    is_paused_upon_creation=True,
    max_active_runs=1,
    max_active_tasks=1,
    tags=["bigdata", "reseteo", ENTORNO],
    description=f"Borra el entorno {nombre_del_entorno(ENTORNO)} (solo ese) para repetir todo",
    doc_md=documentacion_del_reseteo(ENTORNO),
    params=parametros_del_reseteo(ENTORNO),
) as dag:
    validar = tarea_del_reseteo("validar", ENTORNO)
    contar = tarea_del_reseteo("contar", ENTORNO)
    vaciar_control = tarea_del_reseteo("vaciar_control", ENTORNO)
    borrar_snowflake = tarea_del_reseteo("borrar_snowflake", ENTORNO)
    borrar_s3 = tarea_del_reseteo("borrar_s3", ENTORNO)
    resumen = tarea_del_reseteo("resumen", ENTORNO)

    validar >> contar >> vaciar_control >> borrar_snowflake >> borrar_s3 >> resumen
