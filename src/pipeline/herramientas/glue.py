"""Lanzar un paso en Glue desde el Code Editor, el cuaderno o Airflow, y esperar su cierre.

Es el ÚNICO lanzador de Glue: sube tu código (en dev), arranca un job run por mes, espera con
get_job_run e imprime el cierre con lo que el job dejó en la tabla de control. Qué es una corrida,
su banner y su cierre viven en corrida.py; aquí solo está lo que habla con Glue.

Este archivo no importa pyspark ni boto3 al cargarse: la VM de Airflow no tiene pyspark.
"""

from __future__ import annotations

import os
import tempfile
import time
import zipfile
from dataclasses import replace
from datetime import UTC, datetime, timedelta
from pathlib import Path

import yaml

from pipeline.herramientas.corrida import COMPUTOS, Corrida, Resultado, cierre, tablas_del_paso
from pipeline.herramientas.rutas import ConfigError, bucket_del_lake

# Glue: workers y minutos de plazo de cada perfil. Manda airflow/framework/profiles.yaml si se
# encuentra; estos valores son el respaldo.
PERFILES_DE_GLUE = {"small": (2, 15), "medium": (4, 20), "large": (6, 30)}
ESTADOS_FINALES_DE_GLUE = ("SUCCEEDED", "FAILED", "ERROR", "TIMEOUT", "STOPPED")
SEGUNDOS_ENTRE_CONSULTAS = 15
# Margen para comparar el reloj de este equipo con el INICIO que quedó en la tabla de control.
MARGEN_DE_RELOJ = 10


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
