"""CLI del pipeline: una capa fina sobre pipeline.correr.correr_paso.

    python -m pipeline.run [--paso {bronze,silver,gold,snowflake}] [--computo C] [--mes AAAA-MM]
                           [--limite {1000,100000,todos}] [--reprocesar [true|false]]

- Sin --paso se corren los cuatro, en orden: bronze, silver, gold y snowflake.
- Lo que no pidas sale de pipeline.yaml (raíz del repo): argumento > pipeline.yaml > defecto.
- El entorno NO se elige: desde el Code Editor siempre es dev.
- El cómputo sí: code_editor, glue_small, glue_medium o glue_large.
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
    return p


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

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
