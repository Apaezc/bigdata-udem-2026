"""CLI del pipeline: una capa fina sobre pipeline.correr.correr_paso.

    python -m pipeline.run [--paso {bronze,silver,gold,snowflake}] [--computo C] [--mes AAAA-MM]
                           [--limite {1000,100000,todos}] [--reprocesar [true|false]]

- Sin --paso se corren los cuatro, en orden: bronze, silver, gold y snowflake.
- Lo que no pidas sale de pipeline.yaml (raíz del repo): argumento > pipeline.yaml > defecto.
- El entorno NO se elige: desde el Code Editor siempre es dev (por eso no existe --env).
- El cómputo sí: code_editor, glue_small, glue_medium o glue_large (por eso no existe --engine).
- --step sigue valiendo como otro nombre de --paso.
Requiere PYTHONPATH=src (o ejecutar desde el paquete instalado).
"""

from __future__ import annotations

import argparse
import sys

from pipeline.herramientas.corrida import (
    COMPUTOS,
    LIMITES,
    PASOS,
    EntornoNoPermitido,
    LimiteNoPermitido,
)
from pipeline.herramientas.rutas import ConfigError, validar_mes

MENSAJE_SIN_ENTORNO = (
    "--env ya no existe: el entorno no se elige. Lo que corres desde el Code Editor es siempre "
    "dev; prod solo lo corre el DAG de la VM después del PR y el CI/CD."
)
MENSAJE_SIN_MOTOR = (
    "--engine ya no existe: lo que eliges ahora es el cómputo, con --computo "
    f"({' | '.join(COMPUTOS)}). Lo normal es dejarlo en pipeline.yaml."
)


def _verdadero_o_falso(texto: str) -> bool:
    if texto.lower() in ("true", "si", "sí", "1"):
        return True
    if texto.lower() in ("false", "no", "0"):
        return False
    raise argparse.ArgumentTypeError("usa true o false")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="python -m pipeline.run", description="Pipeline bronze/silver/gold/snowflake (FHVHV)"
    )
    p.add_argument(
        "--paso",
        "--step",
        dest="paso",
        choices=PASOS,
        default=None,
        help="un paso; sin él se corren los cuatro, en orden",
    )
    p.add_argument("--computo", choices=COMPUTOS, default=None, help="dónde se calcula")
    p.add_argument("--mes", type=validar_mes, default=None, help="AAAA-MM")
    p.add_argument("--limite", choices=LIMITES, default=None, help="filas por fuente")
    p.add_argument(
        "--reprocesar",
        nargs="?",
        const=True,
        default=None,
        type=_verdadero_o_falso,
        help="ignora la tabla de control (true) o la respeta (false)",
    )
    # Se aceptan solo para decir por qué ya no existen (en lugar de «unrecognized arguments»).
    p.add_argument("--env", default=None, help=argparse.SUPPRESS)
    p.add_argument("--engine", default=None, help=argparse.SUPPRESS)
    return p


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.env is not None:
        parser.error(MENSAJE_SIN_ENTORNO)
    if args.engine is not None:
        parser.error(MENSAJE_SIN_MOTOR)

    from pipeline.correr import correr_paso  # tardío: así `--help` no carga el pipeline

    pasos = [args.paso] if args.paso else list(PASOS)
    try:
        for paso in pasos:
            correr_paso(
                paso,
                mes=args.mes,
                computo=args.computo,
                limite=args.limite,
                reprocesar=args.reprocesar,
            )
    except (ConfigError, EntornoNoPermitido, LimiteNoPermitido) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
