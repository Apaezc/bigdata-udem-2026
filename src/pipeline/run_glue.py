"""Entrada de AWS Glue: mínima y estable. Toda la lógica viaja en el zip del código.

Glue ejecuta este archivo (code/run_glue.py) y el job trae pipeline.zip en --extra-py-files. El
script del job no se puede cambiar por corrida, por eso aquí no hay lógica: lee los argumentos,
deja el entorno y las conexiones en variables de entorno y llama a
pipeline.correr.correr_paso(..., en_glue=True).

Argumentos: --step (obligatorio); --env, --mes, --limite, --reprocesar, --computo, --lake-bucket y
--snowflake-secret (los pasa lanzar_en_glue). Glue no acepta valores vacíos: un mes vacío o
«todos» significa todos los meses de config/<entorno>.yaml.
Con awsglue se leen con getResolvedOptions; fuera de Glue se usa sys.argv directamente.
"""

from __future__ import annotations

import argparse
import os
import sys

REQUERIDOS = ("step",)
OPCIONALES = (
    "env",
    "mes",
    "limite",
    "reprocesar",
    "computo",
    "lake-bucket",
    "snowflake-secret",
)
# Para el mes, estos valores quieren decir «todos los meses».
MES_VACIO = (None, "", "todos", "0")


def resueltos_a_argv(resueltos: dict[str, str]) -> list[str]:
    """Convierte lo que devuelve getResolvedOptions (claves con '_') en argv de este script."""
    argv: list[str] = []
    permitidas = {o.replace("-", "_") for o in (*REQUERIDOS, *OPCIONALES)}
    for clave, valor in resueltos.items():
        # getResolvedOptions de Glue 5.0 devuelve también otras claves (algunas con valor None):
        # solo se pasan las del pipeline.
        if clave in permitidas and valor not in (None, ""):
            argv += [f"--{clave.replace('_', '-')}", valor]
    return argv


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Entrada de Glue del pipeline")
    p.add_argument("--step", required=True)
    for nombre in OPCIONALES:
        p.add_argument(f"--{nombre}", default=None)
    return p


def _argv_glue() -> list[str]:
    try:
        from awsglue.utils import getResolvedOptions
    except ImportError:
        return sys.argv[1:]
    presentes = [o for o in OPCIONALES if f"--{o}" in sys.argv]
    resueltos = getResolvedOptions(sys.argv, [*REQUERIDOS, *presentes])
    return resueltos_a_argv(resueltos)


def main(argv: list[str]) -> int:
    args = build_parser().parse_args(argv)

    # El entorno y las conexiones llegan como argumentos; el resto del código las lee de aquí.
    if args.env:
        os.environ["PIPELINE_ENTORNO"] = args.env
    if args.lake_bucket:
        os.environ["LAKE_BUCKET"] = args.lake_bucket
    if args.snowflake_secret:
        os.environ["WATERMARK_SECRET"] = args.snowflake_secret

    from pipeline.correr import correr_paso  # tardío: ya está el zip en el path

    # Un mes vacío es «todos los meses»: se pasa '' (y no None, que sería «lo que diga el yaml»).
    mes = "" if args.mes in MES_VACIO else args.mes
    reprocesar = None if args.reprocesar is None else args.reprocesar.lower() == "true"
    correr_paso(
        args.step,
        en_glue=True,
        mes=mes,
        computo=args.computo,
        limite=args.limite,
        reprocesar=reprocesar,
    )
    return 0


if __name__ == "__main__":
    # Glue marca el job como FAILED ("SystemExit: 0") si el script llama sys.exit(0):
    # solo se sale con código distinto de cero.
    codigo = main(_argv_glue())
    if codigo:
        sys.exit(codigo)
