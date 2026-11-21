"""CLI del pipeline.

    python -m pipeline.run --step {bronze,muestra,silver,gold,all} --env {local,dev,prod} \
        --engine {local,glue} [--mes YYYY-MM] [--limite N] [--lake-bucket NOMBRE] \
        [--snowflake-secret NOMBRE]

- Sin --mes se procesan todos los meses de config/<env>.yaml, en UNA pasada de Spark por paso.
- all = bronze + silver + gold (en local: silver + gold sobre la muestra; no hay bronze).
- bronze y muestra solo en dev/prod (en la nube). bronze descarga el crudo y crea un lote nuevo
  con metadatos; no usa --limite. muestra lee bronze; --limite recorta aún más los viajes.
- En Glue, al terminar bien bronze, silver o gold se registra una fila por mes en la tabla de
  control BIGDATA.CONTROL.WATERMARK (pipeline.watermark). La conexión sale del secreto de
  Secrets Manager que indica --snowflake-secret. En local no se registra nada.
- Cada corrida empieza imprimiendo en qué bucket y carpetas lee y escribe (ver
  settings.describir_rutas). dev solo toca s3://<lake>/dev/; prod solo s3://<lake>/prod/.
Requiere PYTHONPATH=src (o ejecutar desde el paquete instalado).
"""

from __future__ import annotations

import argparse
import logging
import os
import sys
from datetime import UTC, datetime
from typing import Any

from pyspark.sql import functions as F

from pipeline import bronze, engine, gold, io, muestra, silver, watermark
from pipeline.settings import ENTORNOS, cargar, describir_rutas, validar_mes

PASOS = {"bronze": bronze, "muestra": muestra, "silver": silver, "gold": gold}
MOTORES = ("local", "glue")
SOLO_NUBE = ("bronze", "muestra")
CAPAS_CON_CONTROL = ("bronze", "silver", "gold")
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
    p.add_argument(
        "--snowflake-secret",
        default=None,
        help="secreto de Secrets Manager con la conexión de Snowflake (WATERMARK_SECRET)",
    )
    return p


def pasos_de(step: str, env: str) -> list[str]:
    if step == "all":
        return ["silver", "gold"] if env == "local" else ["bronze", "silver", "gold"]
    if env == "local" and step in SOLO_NUBE:
        raise SystemExit(f"--step {step} no aplica en local: se ejecuta en dev/prod (Glue).")
    return [step]


def registrar_paso(spark: Any, cfg: dict, paso: str, meses: list[str], inicio: datetime) -> None:
    """Registra en la tabla de control una fila por mes del paso que acaba de terminar bien.

    Las filas se cuentan leyendo lo que el paso dejó escrito. La TABLA lleva el entorno como
    prefijo (dev/fhvhv, dev/fhvhv_trips) para que dev y prod no se confundan: cada entorno tiene
    su propia carpeta en el lake, también para bronze. reprocesar queda en falso: el pipeline de
    Glue no consulta la tabla antes de correr, cada corrida de bronze crea un lote nuevo.
    """
    entorno = cfg["entorno"]
    for mes in meses:
        if paso == "bronze":
            fuente = bronze.URL_VIAJES.format(mes=mes)
            tabla = watermark.nombre_de_tabla(entorno, io.VIAJES)
            filas = io.leer_viajes(spark, cfg["rutas"]["bronze"], [mes]).count()
        elif paso == "silver":
            fuente = cfg["rutas"]["bronze"]
            tabla = watermark.nombre_de_tabla(entorno, io.CARPETA_CAPA["silver"])
            filas = io.leer_silver(spark, cfg, [mes]).count()
        else:
            fuente = cfg["rutas"]["silver"]
            tabla = watermark.nombre_de_tabla(entorno, io.CARPETA_CAPA["gold"])
            ruta_gold = io.unir(cfg["rutas"]["gold"], io.CARPETA_CAPA["gold"])
            filas = spark.read.parquet(ruta_gold).where(F.col("mes") == mes).count()
        watermark.registrar_watermark(fuente, paso, tabla, mes, filas, inicio, False)
        log.info("Watermark: %s %s %s mes=%s filas=%d", entorno, paso, tabla, mes, filas)


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    if args.lake_bucket:
        os.environ["LAKE_BUCKET"] = args.lake_bucket
    if args.snowflake_secret:
        os.environ[watermark.VARIABLE_SECRETO] = args.snowflake_secret

    cfg = cargar(args.env)
    log.info("Rutas de esta corrida:\n%s", describir_rutas(args.env))
    meses = [args.mes] if args.mes else list(cfg["meses"])
    pasos = pasos_de(args.step, args.env)

    if args.env == "local":
        muestra.sincronizar(cfg)

    # Todos los pasos usan Spark, también bronze (convierte lo descargado a Parquet con metadatos).
    spark = engine.get_spark(args.engine)
    ns = argparse.Namespace(env=args.env, engine=args.engine, meses=meses, limite=args.limite)
    for paso in pasos:
        log.info("Paso=%s env=%s engine=%s meses=%s", paso, args.env, args.engine, ",".join(meses))
        inicio = datetime.now(UTC)
        PASOS[paso].main(spark, cfg, ns)
        # Solo en Glue y solo para las capas de datos; si el paso falló, no se llega hasta aquí.
        if args.engine == "glue" and paso in CAPAS_CON_CONTROL:
            registrar_paso(spark, cfg, paso, meses, inicio)
    return 0


if __name__ == "__main__":
    sys.exit(main())
