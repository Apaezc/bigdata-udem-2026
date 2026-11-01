"""CLI del pipeline.

    python -m pipeline.run --step {bronze,muestra,silver,gold,all} --env {local,dev,prod} \
        --engine {local,glue} [--mes YYYY-MM] [--limite N] [--lake-bucket NOMBRE]

- Sin --mes se procesan todos los meses de config/<env>.yaml, en UNA pasada de Spark por paso.
- all = bronze + silver + gold (en local: silver + gold sobre la muestra; no hay bronze).
- muestra solo en dev/prod (lee bronze en la nube); --limite recorta aún más los viajes.
Requiere PYTHONPATH=src (o ejecutar desde el paquete instalado).
"""

from __future__ import annotations

import argparse
import logging
import os
import sys

from pipeline import bronze, engine, gold, muestra, silver
from pipeline.settings import ENTORNOS, cargar, validar_mes

PASOS = {"bronze": bronze, "muestra": muestra, "silver": silver, "gold": gold}
MOTORES = ("local", "glue")
SOLO_NUBE = ("bronze", "muestra")
log = logging.getLogger("pipeline")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Pipeline bronze/silver/gold (FHVHV)")
    p.add_argument("--step", required=True, choices=[*PASOS, "all"])
    p.add_argument("--env", required=True, choices=ENTORNOS)
    p.add_argument("--engine", required=True, choices=MOTORES)
    p.add_argument("--mes", type=validar_mes, default=None, help="YYYY-MM (un solo mes)")
    p.add_argument(
        "--limite",
        type=int,
        default=None,
        help="máximo de viajes a procesar (reemplaza muestra.max_rows del entorno)",
    )
    p.add_argument(
        "--lake-bucket",
        default=None,
        help="nombre del bucket del lake (equivale a LAKE_BUCKET)",
    )
    return p


def pasos_de(step: str, env: str) -> list[str]:
    if step == "all":
        return ["silver", "gold"] if env == "local" else ["bronze", "silver", "gold"]
    if env == "local" and step in SOLO_NUBE:
        raise SystemExit(f"--step {step} no aplica en local: se ejecuta en dev/prod (Glue).")
    return [step]


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    if args.lake_bucket:
        os.environ["LAKE_BUCKET"] = args.lake_bucket

    cfg = cargar(args.env)
    meses = [args.mes] if args.mes else list(cfg["meses"])
    pasos = pasos_de(args.step, args.env)

    if args.env == "local":
        muestra.sincronizar(cfg)

    spark = engine.get_spark(args.engine) if any(p != "bronze" for p in pasos) else None
    ns = argparse.Namespace(env=args.env, engine=args.engine, meses=meses, limite=args.limite)
    for paso in pasos:
        log.info("Paso=%s env=%s engine=%s meses=%s", paso, args.env, args.engine, ",".join(meses))
        PASOS[paso].main(spark, cfg, ns)
    return 0


if __name__ == "__main__":
    sys.exit(main())
