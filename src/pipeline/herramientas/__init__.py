"""Caja de herramientas de la casa: lo único que los equipos importan.

    from pipeline.herramientas import ruta_lake, Corrida, leer_crudo, registrar_control

Es una fachada perezosa: cada nombre apunta a su módulo y el módulo se importa la primera vez que
alguien lo pide. Así `from pipeline.herramientas import ruta_lake, Corrida` funciona en la VM de
Airflow, que no tiene pyspark (solo `capas` y los pasos lo necesitan).

Reglas de la caja:
1. Los equipos importan solo desde aquí.
2. La caja nunca importa pipeline.bronze, silver, gold ni carga (evita ciclos).
3. A los estudiantes se les enseñan 12 funciones (más crear_tabla): traer_crudo_viajes,
   traer_crudo_taxi_zones, traer_crudo_clima, leer_crudo, escribir_bronze, hash_fila (con
   COLUMNAS_METADATOS), mes_ya_procesado, registrar_control, leer_capa, escribir_capa y
   cargar_gold. El resto es importable pero no se enseña.
4. Todo lo que lee, escribe, consulta o borra dice en voz alta dónde (io.anunciar).
"""

from __future__ import annotations

from importlib import import_module

# nombre -> módulo de pipeline.herramientas donde vive.
_DONDE_VIVE: dict[str, str] = {}


def _registrar(modulo: str, nombres: str) -> None:
    for nombre in nombres.split():
        _DONDE_VIVE[nombre] = modulo


# rutas.py (re-exporta pipeline.settings)
_registrar(
    "rutas",
    """ENTORNOS CAPAS TABLA_VIAJES TABLA_ZONAS TABLA_CLIMA MES_SIN_MES ConfigError
    validar_entorno validar_mes inicio_fin_mes rango_meses ultimo_dia_mes bucket_del_lake
    ruta_lake dir_del_crudo ruta_del_crudo dir_del_lote nombre_tabla_snowflake donde_estoy
    describir_rutas""",
)
# corrida.py
_registrar(
    "corrida",
    """COMPUTOS LIMITES PASOS DEFECTOS EntornoNoPermitido LimiteNoPermitido entorno_actual
    valores_de_pipeline_yaml Corrida cargar_configuracion Resultado rutas_del_paso banner cierre
    lanzar_en_glue""",
)
# crudo.py
_registrar(
    "crudo",
    """traer_crudo_viajes traer_crudo_taxi_zones traer_crudo_clima url_viajes url_zonas url_clima
    descargar URL_VIAJES URL_ZONAS URL_CLIMA""",
)
# capas.py
_registrar(
    "capas",
    """leer_crudo escribir_bronze leer_capa escribir_capa mover_entre_capas nuevo_id_lote
    hash_fila COLUMNAS_METADATOS MARCADOR_NULO SEPARADOR_HASH""",
)
# control.py
_registrar(
    "control",
    """tabla_de_control consultar_control mes_ya_procesado registrar_control con_control
    exigir_rol_del_entorno vaciar_control ControlEnMemoria instalar_backend""",
)
# athena.py
_registrar("athena", "nombre_tabla_athena esquema_de_athena verificar_esquema_con_athena")
# bodega.py (la parte de Snowflake)
_registrar(
    "bodega",
    """crear_tabla esquema_de_tabla cargar_gold cargar_gold_a_snowflake comparar_columnas
    ColumnasDistintas""",
)
# reseteo.py
_registrar("reseteo", "borrar_capas_s3 borrar_tablas_snowflake")
# equipo.py (ayudas del cuaderno)
_registrar("equipo", "usar_mis_funciones probar_mis_funciones")

__all__ = sorted(_DONDE_VIVE)


def __getattr__(nombre: str):
    modulo = _DONDE_VIVE.get(nombre)
    if modulo is None:
        raise AttributeError(f"pipeline.herramientas no tiene '{nombre}'")
    valor = getattr(import_module(f"pipeline.herramientas.{modulo}"), nombre)
    globals()[nombre] = valor  # la próxima vez ya no pasa por aquí
    return valor


def __dir__() -> list[str]:
    return sorted({*globals(), *_DONDE_VIVE})
