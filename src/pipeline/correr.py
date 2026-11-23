"""Los cuatro pasos del pipeline como funciones que se llaman solas.

    correr_bronze()        correr_silver()        correr_gold()        cargar_snowflake()

Son las mismas en una celda del cuaderno, en `make correr PASO=...` y como tareas del DAG
`pipeline_taxi` (con el mismo nombre). Pasar de Spark en el Code Editor a Glue cambia solo
`computo`. Cada una devuelve una lista de Resultado.

Este es el ÚNICO archivo que imprime el banner y el cierre; los `main` de los pasos solo
devuelven sus Resultado. Aquí tampoco se importa pyspark al cargarse: la VM de Airflow llama a
estas funciones para lanzar Glue y no tiene Spark.
"""

from __future__ import annotations

from dataclasses import replace
from importlib import import_module

from pipeline.herramientas.corrida import (
    PASOS,
    Resultado,
    banner,
    cargar_configuracion,
    cierre,
)
from pipeline.herramientas.glue import lanzar_en_glue
from pipeline.herramientas.rutas import ConfigError, raiz_de_prueba

PERILLAS = ("mes", "computo", "limite", "reprocesar")


def _modulo_del_paso(paso: str):
    """pipeline.bronze, pipeline.silver, pipeline.gold o pipeline.carga (el paso snowflake)."""
    nombre = "carga" if paso == "snowflake" else paso
    return import_module(f"pipeline.{nombre}")


def _conocer_las_tablas_del_paso(paso: str) -> None:
    """Carga gold o carga antes del banner: así muestra también las tablas que agregó el equipo."""
    if paso in ("gold", "snowflake"):
        try:
            _modulo_del_paso(paso)
        except ImportError:
            pass  # en la VM gold no se importa (trae pyspark): el banner muestra la de la casa


def correr_paso(paso: str, *, en_glue: bool = False, **perillas) -> list[Resultado]:
    """Corre un paso: configuración -> por cada mes, banner -> el trabajo -> cierre.

    Es el motor interno del CLI (run.py), de run_glue.py y de las cuatro funciones públicas; no
    se enseña. `perillas` son mes, computo, limite, reprocesar y, para snowflake, conexion.
    """
    if paso not in PASOS:
        raise ConfigError(f"Paso desconocido '{paso}'. Válidos: {', '.join(PASOS)}")
    conexion = perillas.pop("conexion", None)
    desconocidas = [nombre for nombre in perillas if nombre not in PERILLAS]
    if desconocidas:
        raise TypeError(f"Perilla desconocida: {', '.join(desconocidas)}. Válidas: {PERILLAS}")

    corrida = cargar_configuracion(**perillas)
    _conocer_las_tablas_del_paso(paso)

    todos: list[Resultado] = []
    for mes in corrida.meses:
        corrida_del_mes = replace(corrida, meses=(mes,))
        print(banner(corrida_del_mes, paso, mes))

        if paso == "snowflake":
            # Sin Spark y con cualquier cómputo: carga gold a Snowflake desde este proceso.
            resultados = _modulo_del_paso(paso).main(corrida_del_mes, conexion)
        elif corrida.computo == "code_editor" or en_glue:
            from pipeline import engine  # tardío: trae pyspark

            toca_s3 = raiz_de_prueba() is None
            spark = engine.get_spark(corrida.computo, toca_s3=toca_s3 and not en_glue)
            resultados = _modulo_del_paso(paso).main(spark, corrida_del_mes)
        else:
            # Glue: el lanzador espera al job y escribe el cierre con lo que quedó en la tabla.
            lanzar_en_glue(paso, corrida_del_mes)
            continue

        print(cierre(corrida_del_mes, paso, mes, resultados))
        todos.extend(resultados)
    return todos


def correr_bronze(mes=None, computo=None, limite=None, reprocesar=None) -> list[Resultado]:
    """Paso bronze: trae el crudo, le agrega los metadatos y escribe un lote nuevo por tabla."""
    return correr_paso("bronze", mes=mes, computo=computo, limite=limite, reprocesar=reprocesar)


def correr_silver(mes=None, computo=None, limite=None, reprocesar=None) -> list[Resultado]:
    """Paso silver: espejo de bronze, una tabla por fuente, sin duplicados."""
    return correr_paso("silver", mes=mes, computo=computo, limite=limite, reprocesar=reprocesar)


def correr_gold(mes=None, computo=None, limite=None, reprocesar=None) -> list[Resultado]:
    """Paso gold: las tablas de negocio que juntan silver."""
    return correr_paso("gold", mes=mes, computo=computo, limite=limite, reprocesar=reprocesar)


def cargar_snowflake(
    mes=None, computo=None, limite=None, reprocesar=None, conexion=None
) -> list[Resultado]:
    """Paso snowflake: crea las tablas y carga gold. No usa Spark, con cualquier cómputo."""
    return correr_paso(
        "snowflake",
        mes=mes,
        computo=computo,
        limite=limite,
        reprocesar=reprocesar,
        conexion=conexion,
    )
