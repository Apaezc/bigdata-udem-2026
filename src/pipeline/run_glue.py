"""Entrypoint de AWS Glue: delega en pipeline.run.main con el engine fijo `glue`.

Glue ejecuta este archivo (code/run_glue.py) con pipeline.zip en --extra-py-files.
Argumentos del job: --step y --env (obligatorios); --mes, --limite y --lake-bucket (opcionales).
Terraform deja --env y --lake-bucket como argumentos por defecto del job; Airflow pasa
--step, --env y --mes. El engine no se recibe: aquí siempre es `glue`.
Con awsglue se leen con getResolvedOptions; fuera de Glue se usa sys.argv directamente.
"""

from __future__ import annotations

import sys

from pipeline.run import main

REQUERIDOS = ("step", "env")
OPCIONALES = ("mes", "limite", "lake-bucket")


def resueltos_a_argv(resueltos: dict[str, str]) -> list[str]:
    """Convierte lo que devuelve getResolvedOptions (claves con '_') en argv de pipeline.run."""
    argv: list[str] = ["--engine", "glue"]
    permitidas = {o.replace("-", "_") for o in (*REQUERIDOS, *OPCIONALES)}
    for clave, valor in resueltos.items():
        # getResolvedOptions de Glue 5.0 devuelve tambien otras claves (algunas con valor None):
        # solo se pasan al parser las del pipeline.
        if clave in permitidas and valor is not None:
            argv += [f"--{clave.replace('_', '-')}", valor]
    return argv


def _argv_glue() -> list[str]:
    try:
        from awsglue.utils import getResolvedOptions
    except ImportError:
        return sys.argv[1:]
    presentes = [o for o in OPCIONALES if f"--{o}" in sys.argv]
    resueltos = getResolvedOptions(sys.argv, [*REQUERIDOS, *presentes])
    return resueltos_a_argv(resueltos)


if __name__ == "__main__":
    # Glue marca el job como FAILED ("SystemExit: 0") si el script llama sys.exit(0):
    # solo se sale con codigo distinto de cero.
    codigo = main(_argv_glue())
    if codigo:
        sys.exit(codigo)
