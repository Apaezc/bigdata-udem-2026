"""Laboratorio de motores (sesión 7): el MISMO código de silver y gold, ejecutado en Snowflake.

Snowpark Connect for Spark traduce el PySpark a SQL de Snowflake. Este script:
  1. carga una vez el mes de FHVHV (Parquet local) en la tabla BIGDATA.DEV.LAB_FHVHV_<MES>,
  2. ejecuta silver y gold con las funciones de src/pipeline (sin cambiar una línea),
  3. escribe BIGDATA.DEV.LAB_GOLD_SNOWPARK y mide los tiempos de cada fase.
Compara contra el DAG del Airflow de dev con computo=glue_small (mismo mes)
y llena la tabla del README.

Uso (desde la raíz del repo, en el Code Editor):
  python laboratorios/motores/snowpark_connect.py --datos ~/fhvhv --mes 2024-01 [--recargar]
Conexión: ~/.snowflake/connections.toml ([default]) + SNOWFLAKE_ROLE=BIGDATA_DEV y
SNOWFLAKE_WAREHOUSE=BIGDATA_WH (ver README del laboratorio).
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(RAIZ / "src"))

from pipeline import quality  # noqa: E402
from pipeline.engine import get_spark  # noqa: E402
from pipeline.gold import metricas_diarias_zona  # noqa: E402
from pipeline.silver import clima_diario, enriquecer, limpiar_viajes  # noqa: E402


def medir(nombre: str, inicio: float) -> float:
    segundos = time.time() - inicio
    print(f"MEDICION {nombre:<28} {segundos:8.1f} s")
    return segundos


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument(
        "--datos", required=True, help="carpeta con fhvhv_tripdata_<mes>.parquet, zonas y clima"
    )
    p.add_argument("--mes", default="2024-01")
    p.add_argument(
        "--recargar", action="store_true", help="vuelve a cargar el mes aunque la tabla exista"
    )
    args = p.parse_args()
    datos = Path(args.datos).expanduser()
    tabla_viajes = f"LAB_FHVHV_{args.mes.replace('-', '_')}"

    os.environ.setdefault("SNOWFLAKE_DATABASE", "BIGDATA")
    os.environ.setdefault("SNOWFLAKE_SCHEMA", "DEV")

    t = time.time()
    spark = get_spark("snowpark_connect")
    medir("sesion", t)

    # 1. Carga (una vez): el archivo crudo se sube y queda como tabla de Snowflake.
    existe = tabla_viajes in {r.tableName.upper() for r in spark.sql("SHOW TABLES").collect()}
    if args.recargar or not existe:
        t = time.time()
        spark.read.parquet(str(datos / f"fhvhv_tripdata_{args.mes}.parquet")).write.mode(
            "overwrite"
        ).saveAsTable(tabla_viajes)
        medir("carga_a_tabla", t)

    # 2. Silver y gold con las funciones del pipeline, leyendo la TABLA (no el archivo).
    t = time.time()
    viajes = spark.table(tabla_viajes)
    zonas = spark.read.option("header", True).csv(str(datos / "taxi_zone_lookup.csv"))
    clima = clima_diario(
        spark.read.option("multiLine", True).json(str(datos / f"open_meteo_{args.mes}.json"))
    )
    silver = enriquecer(limpiar_viajes(viajes, [args.mes]), zonas, clima)
    gold = metricas_diarias_zona(silver)
    gold.write.mode("overwrite").saveAsTable("LAB_GOLD_SNOWPARK")
    medir("silver_gold_y_escritura", t)

    t = time.time()
    total = quality.validar(
        spark.table("LAB_GOLD_SNOWPARK"),
        nombre="gold",
        llaves=("fecha", "zona", "empresa"),
        clave_unica=("fecha", "zona", "empresa"),
    )["total"]
    medir("chequeos_de_calidad", t)
    print(f"RESULTADO gold_filas {total}")
    print("Créditos: consulta WAREHOUSE_METERING_HISTORY (ver README) unos minutos después.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
