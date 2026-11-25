"""Capa bronze: trae el crudo y lo guarda tal cual, un lote nuevo en cada ingesta.

ESTE CAMBIO LO HIZO
DIEGO PASO POR AQUI

Es la versión «lista para copiar» del cuaderno `01_construir_paso_a_paso`: el pipeline corre de
punta a punta con ella, pero trae un problema A PROPÓSITO que se dice en voz alta en clase:

    agregar_metadatos NO agrega las cinco columnas de metadatos (`_hash_fila` y compañía).

Sin `_hash_fila` silver no puede saber qué filas ya vio, así que al reprocesar un mes (otro lote
de bronze) silver duplica. Tu trabajo es escribir `agregar_metadatos` (la marca
`# PENDIENTE(equipo)` es lo que buscan las pruebas del equipo: bórrala cuando la tengas lista).

Las otras dos funciones del equipo, `debe_ingestar` y `registrar_ingesta`, ya están hechas: son
la puerta de la tabla de control (una llamada a `mes_ya_procesado` y una a `registrar_control`).

La receta de `main`, por cada tabla (fhvhv, taxi_zones y clima):

    debe_ingestar?  no -> SE SALTÓ
                    sí -> traer_crudo_* -> leer_crudo -> agregar_metadatos -> escribir_bronze
                          -> registrar_ingesta -> REGISTRÓ

Bronze es solo de agregar: cada ingesta escribe un lote nuevo (lote=<id>/) y nunca borra los
anteriores. Quien lee bronze (silver) junta todos los lotes completos del mes.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import TYPE_CHECKING, Any

from pipeline.herramientas.capas import (
    COLUMNAS_METADATOS,
    escribir_bronze,
    hash_fila,
    leer_crudo,
)
from pipeline.herramientas.control import (
    consultar_control,
    mes_ya_procesado,
    registrar_control,
)
from pipeline.herramientas.corrida import Resultado
from pipeline.herramientas.crudo import (
    traer_crudo_clima,
    traer_crudo_taxi_zones,
    traer_crudo_viajes,
    url_clima,
    url_viajes,
    url_zonas,
)
from pipeline.herramientas.rutas import (
    MES_SIN_MES,
    TABLA_CLIMA,
    TABLA_VIAJES,
    TABLA_ZONAS,
)

if TYPE_CHECKING:  # pyspark solo hace falta para los tipos: este módulo carga también sin Spark
    from pyspark.sql import DataFrame, SparkSession

    from pipeline.herramientas.corrida import Corrida

# hash_fila y COLUMNAS_METADATOS no los usa este archivo todavía: son las piezas con las que el
# equipo escribe agregar_metadatos.
__all__ = [
    "COLUMNAS_METADATOS",
    "agregar_metadatos",
    "debe_ingestar",
    "hash_fila",
    "main",
    "registrar_ingesta",
]

CAPA = "bronze"


# --- las tres funciones del equipo ------------------------------------------------------------


def agregar_metadatos(
    df: DataFrame, fuente: str, archivo_origen: str, id_lote: str, fecha_ingesta: datetime
) -> DataFrame:
    """Agrega las cinco columnas de metadatos a las columnas originales (que no se tocan).

    El orden de las columnas nuevas es el de COLUMNAS_METADATOS:
    _fecha_ingesta, _id_lote, _hash_fila, _fuente, _archivo_origen.

    El hash se calcula primero, solo con las columnas originales (`hash_fila(df.columns)`); así
    no depende de las otras columnas de metadatos y dos ingestas del mismo archivo dan el mismo
    hash fila por fila. Eso es lo que después permite deduplicar en silver.
    """
    # PENDIENTE(equipo): hoy esta función devuelve df tal cual, sin metadatos. Por eso bronze
    # no guarda de qué lote ni de qué archivo vino cada fila, y silver no puede deduplicar.
    return df


def debe_ingestar(corrida: Corrida, tabla: str, mes: str) -> bool:
    """La puerta de bronze: True = ingestar este mes, False = saltarlo.

    La regla (la de la tabla de control) es una sola: si ya hay un registro de bronze para
    (tabla, mes) y no se pidió reprocesar, se salta; en cualquier otro caso se ingesta.
    `mes_ya_procesado` ya contiene esa regla: aquí solo se invierte la pregunta.
    """
    ya_esta_registrado = mes_ya_procesado(corrida, tabla, CAPA, mes)
    if ya_esta_registrado:
        return False
    return True


def registrar_ingesta(
    corrida: Corrida,
    tabla: str,
    mes: str,
    fuente: str,
    leidas: int,
    filas: int,
    inicio: datetime,
) -> None:
    """Anota en la tabla de control que bronze terminó bien este mes.

    Solo se llama DESPUÉS de escribir el lote: si la escritura falla no queda registro y el mes
    se puede volver a intentar. `filas` son las escritas; `leidas` es solo informativo.
    """
    registrar_control(corrida, tabla, CAPA, mes, filas, inicio, fuente, leidas)


# --- el paso ----------------------------------------------------------------------------------


def _cifras_del_ultimo_registro(
    corrida: Corrida, tabla: str, mes_en_control: str
) -> tuple[int, int]:
    """(leídas, escritas) del último registro de bronze, para mostrarlas cuando se salta."""
    registros = consultar_control(corrida.entorno, tabla, CAPA, mes_en_control)
    if len(registros) == 0:
        return 0, 0
    ultimo = registros[-1]
    escritas = ultimo.get("filas") or 0
    leidas = ultimo.get("leidas")
    if leidas is None:
        leidas = escritas
    return leidas, escritas


def _ingestar_tabla(
    spark: SparkSession,
    corrida: Corrida,
    tabla: str,
    mes: str,
    fuente: str,
    traer_crudo,
) -> Resultado:
    """Ingesta una tabla de un mes: puerta, crudo, metadatos, lote nuevo y registro."""
    # taxi_zones no se parte por mes: en el lake no lleva mes y en la tabla de control es 'sin_mes'.
    if tabla == TABLA_ZONAS:
        mes_en_lake = None
        mes_en_control = MES_SIN_MES
    else:
        mes_en_lake = mes
        mes_en_control = mes

    if not debe_ingestar(corrida, tabla, mes_en_control):
        leidas, escritas = _cifras_del_ultimo_registro(corrida, tabla, mes_en_control)
        return Resultado(tabla, CAPA, mes_en_control, leidas, escritas, "SE SALTÓ")

    inicio = datetime.now(UTC).replace(microsecond=0)
    ruta_del_crudo = traer_crudo()
    archivo_origen = ruta_del_crudo.rstrip("/").rsplit("/", 1)[-1]

    crudo = leer_crudo(spark, corrida.entorno, tabla, mes_en_lake, corrida.limite_filas)
    leidas = crudo.count()
    con_metadatos = agregar_metadatos(
        crudo, fuente, archivo_origen, corrida.id_lote, corrida.fecha_ingesta
    )
    filas = escribir_bronze(con_metadatos, corrida.entorno, tabla, mes_en_lake, corrida.id_lote)
    registrar_ingesta(corrida, tabla, mes_en_control, fuente, leidas, filas, inicio)
    return Resultado(tabla, CAPA, mes_en_control, leidas, filas, "REGISTRÓ")


def main(spark: Any, corrida: Corrida) -> list[Resultado]:
    """Bronze de los meses de la corrida: fhvhv y clima por mes, y taxi_zones una vez.

    No imprime banner ni cierre (eso lo hace pipeline.correr); devuelve un Resultado por tabla.
    """
    resultados: list[Resultado] = []
    entorno = corrida.entorno

    for indice, mes in enumerate(corrida.meses):
        resultados.append(
            _ingestar_tabla(
                spark,
                corrida,
                TABLA_VIAJES,
                mes,
                url_viajes(mes),
                lambda mes=mes: traer_crudo_viajes(entorno, mes),
            )
        )
        # Las zonas no cambian con el mes: se ingestan una sola vez por corrida.
        if indice == 0:
            resultados.append(
                _ingestar_tabla(
                    spark,
                    corrida,
                    TABLA_ZONAS,
                    mes,
                    url_zonas(),
                    lambda: traer_crudo_taxi_zones(entorno),
                )
            )
        resultados.append(
            _ingestar_tabla(
                spark,
                corrida,
                TABLA_CLIMA,
                mes,
                url_clima(mes),
                lambda mes=mes: traer_crudo_clima(entorno, mes),
            )
        )
    return resultados
