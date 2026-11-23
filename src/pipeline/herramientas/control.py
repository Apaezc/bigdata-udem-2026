"""Tabla de control por entorno: la puerta que decide si un mes se ingesta o se salta.

Hay una tabla por entorno: BIGDATA.CONTROL_DEV.WATERMARK y BIGDATA.CONTROL_PROD.WATERMARK. Cada
vez que un paso termina bien registra una fila; antes de trabajar, el paso pregunta a la puerta
(`mes_ya_procesado`) si ese mes ya tiene registro. La regla es una sola:

    no hay registro y reprocesar=false  ->  se ingesta
    hay registro    y reprocesar=false  ->  se salta (sin mirar filas, cómputo ni límite)
    reprocesar=true                     ->  se ingesta siempre

La clave de la consulta es (TABLA, CAPA, MES). COMPUTO, LIMITE y LEIDAS se guardan solo para
informar. Reprocesar no borra nada: cada corrida deja su fila y la historia queda completa.

La conexión sale del secreto de Secrets Manager (WATERMARK_SECRET; en dev su defecto es
'<PREFIX>/snowflake', rol BIGDATA_DEV) y nunca de connections.toml, que usa ACCOUNTADMIN. Los
permisos de verdad los pone Snowflake: BIGDATA_DEV no puede escribir en CONTROL_PROD.

Para probar sin Snowflake: `instalar_backend(ControlEnMemoria())` cambia dónde se guardan los
registros y nada más; la puerta y `con_control` corren igual.
"""

from __future__ import annotations

from collections.abc import Callable
from datetime import UTC, datetime
from typing import Any

from pipeline.herramientas import archivos, bodega
from pipeline.herramientas.rutas import BASE_DATOS, validar_entorno

ROL_DEL_ENTORNO = {"dev": "BIGDATA_DEV", "prod": "BIGDATA_PROD"}

# Columnas de la tabla de control, en este orden (diseño técnico, 1.6).
COLUMNAS = [
    "FUENTE",
    "CAPA",
    "TABLA",
    "MES",
    "FILAS",
    "INICIO",
    "REPROCESAR",
    "COMPUTO",
    "LIMITE",
    "LEIDAS",
]

# Código de error de Snowflake cuando el objeto no existe o el rol no tiene permiso para verlo.
ERRNO_TABLA_NO_VISIBLE = 2003

SQL_CONSULTAR = """
    SELECT {columnas}
    FROM {tabla_control}
    WHERE TABLA = %s AND CAPA = %s AND MES = %s
    ORDER BY INICIO
"""
SQL_REGISTRAR = "INSERT INTO {tabla_control} ({columnas}) VALUES ({marcas})"
SQL_VACIAR = "DELETE FROM {tabla_control}"


def tabla_de_control(entorno: str) -> str:
    """'BIGDATA.CONTROL_DEV.WATERMARK' en dev; 'BIGDATA.CONTROL_PROD.WATERMARK' en prod."""
    validar_entorno(entorno)
    return f"{BASE_DATOS}.CONTROL_{entorno.upper()}.WATERMARK"


# --- dónde se guardan los registros -------------------------------------------------------------


def inicio_en_utc(inicio: datetime) -> datetime:
    """Deja la hora de inicio en UTC y sin zona horaria, que es como la guarda la tabla."""
    if inicio.tzinfo is None:
        return inicio
    return inicio.astimezone(UTC).replace(tzinfo=None)


def _registro_a_diccionario(fila: tuple) -> dict:
    """Una fila de la tabla (en el orden de COLUMNAS) como diccionario con claves en minúscula."""
    registro = dict(zip((nombre.lower() for nombre in COLUMNAS), fila, strict=True))
    for campo in ("filas", "leidas"):
        if registro[campo] is not None:
            registro[campo] = int(registro[campo])
    registro["inicio"] = registro["inicio"].isoformat()
    registro["reprocesar"] = bool(registro["reprocesar"])
    return registro


class ControlEnSnowflake:
    """Guarda y lee los registros en la tabla de control del entorno (la de verdad)."""

    def __init__(self, conexion: Any = None):
        self.conexion = conexion

    def _abrir(self, entorno: str) -> tuple[Any, bool]:
        """(conexión, si hay que cerrarla). La que llega por parámetro la cierra quien la abrió."""
        if self.conexion is not None:
            return self.conexion, False
        conexion = bodega.abrir_conexion_de_entorno(entorno)
        try:
            exigir_rol_del_entorno(entorno, conexion)
        except Exception:
            conexion.close()
            raise
        return conexion, True

    def _ejecutar(self, entorno: str, sql: str, valores: tuple = ()) -> list[tuple]:
        conexion, cerrar = self._abrir(entorno)
        try:
            cursor = conexion.cursor()
            try:
                cursor.execute(sql, valores)
            except Exception as error:
                if getattr(error, "errno", None) == ERRNO_TABLA_NO_VISIBLE:
                    raise RuntimeError(_mensaje_tabla_no_visible(entorno)) from error
                raise
            if sql.lstrip().upper().startswith("SELECT"):
                return list(cursor.fetchall())
            return [(int(cursor.rowcount or 0),)]
        finally:
            if cerrar:
                conexion.close()

    def consultar(self, entorno: str, tabla: str, capa: str, mes: str) -> list[dict]:
        tabla_control = tabla_de_control(entorno)
        archivos.anunciar("CONSULTA", tabla_control, f"tabla={tabla} capa={capa} mes={mes}")
        sql = SQL_CONSULTAR.format(tabla_control=tabla_control, columnas=", ".join(COLUMNAS))
        return [
            _registro_a_diccionario(f) for f in self._ejecutar(entorno, sql, (tabla, capa, mes))
        ]

    def registrar(self, entorno: str, registro: dict) -> None:
        tabla_control = tabla_de_control(entorno)
        archivos.anunciar(
            "REGISTRA", tabla_control, f"tabla={registro['tabla']} mes={registro['mes']}"
        )
        sql = SQL_REGISTRAR.format(
            tabla_control=tabla_control,
            columnas=", ".join(COLUMNAS),
            marcas=", ".join(["%s"] * len(COLUMNAS)),
        )
        valores = tuple(registro[nombre.lower()] for nombre in COLUMNAS)
        self._ejecutar(entorno, sql, valores)

    def vaciar(self, entorno: str) -> int:
        tabla_control = tabla_de_control(entorno)
        archivos.anunciar("BORRA", tabla_control, "todos los registros")
        return self._ejecutar(entorno, SQL_VACIAR.format(tabla_control=tabla_control))[0][0]


class ControlEnMemoria:
    """Misma interfaz que ControlEnSnowflake, pero los registros viven en una lista (pruebas).

    `registros` guarda cada fila como diccionario con claves en minúscula y la clave extra
    `entorno`, en el orden en que se registraron.
    """

    def __init__(self):
        self.registros: list[dict] = []

    def consultar(self, entorno: str, tabla: str, capa: str, mes: str) -> list[dict]:
        validar_entorno(entorno)
        encontrados = [
            r
            for r in self.registros
            if (r["entorno"], r["tabla"], r["capa"], r["mes"]) == (entorno, tabla, capa, mes)
        ]
        return [self._sin_entorno(r) for r in sorted(encontrados, key=lambda r: r["inicio"])]

    def registrar(self, entorno: str, registro: dict) -> None:
        validar_entorno(entorno)
        self.registros.append({"entorno": entorno, **registro})

    def vaciar(self, entorno: str) -> int:
        validar_entorno(entorno)
        borrados = [r for r in self.registros if r["entorno"] == entorno]
        self.registros = [r for r in self.registros if r["entorno"] != entorno]
        return len(borrados)

    @staticmethod
    def _sin_entorno(registro: dict) -> dict:
        salida = {k: v for k, v in registro.items() if k != "entorno"}
        salida["inicio"] = salida["inicio"].isoformat()
        return salida


_backend_instalado: Any = None


def instalar_backend(backend: Any) -> None:
    """Solo pruebas: cambia dónde se guardan los registros. `None` vuelve a Snowflake."""
    global _backend_instalado
    _backend_instalado = backend


def _backend(conexion: Any = None) -> Any:
    return _backend_instalado if _backend_instalado is not None else ControlEnSnowflake(conexion)


def _mensaje_tabla_no_visible(entorno: str) -> str:
    return (
        f"No se encontró la tabla {tabla_de_control(entorno)}, o el rol de la conexión no tiene "
        f"permiso sobre ella. La crea Terraform: corre `make snowflake` y vuelve a intentar."
    )


# --- rol ----------------------------------------------------------------------------------------


def exigir_rol_del_entorno(entorno: str, conexion: Any = None) -> None:
    """Falla si la conexión no corre con el rol del entorno (BIGDATA_DEV o BIGDATA_PROD).

    ACCOUNTADMIN se rechaza siempre: puede escribir en los dos entornos y la tabla de control
    perdería su sentido. Si no llega conexión, abre una con el secreto del entorno.
    """
    from pipeline.herramientas.corrida import EntornoNoPermitido

    esperado = ROL_DEL_ENTORNO[validar_entorno(entorno)]
    cerrar = conexion is None
    if conexion is None:
        conexion = bodega.abrir_conexion_de_entorno(entorno)
    try:
        cursor = conexion.cursor()
        cursor.execute("SELECT CURRENT_ROLE()")
        rol = str(cursor.fetchone()[0]).upper()
    finally:
        if cerrar:
            conexion.close()
    if rol == "ACCOUNTADMIN":
        raise EntornoNoPermitido(
            f"La conexión corre con ACCOUNTADMIN y el pipeline no lo acepta. Usa el rol {esperado} "
            f"(el secreto de Secrets Manager del entorno {entorno})."
        )
    if rol != esperado:
        raise EntornoNoPermitido(
            f"El entorno {entorno} exige el rol {esperado}, pero la conexión corre con {rol}."
        )


# --- las funciones que usan los pasos -----------------------------------------------------------


def consultar_control(
    entorno: str, tabla: str, capa: str, mes: str, conexion: Any = None
) -> list[dict]:
    """Registros de esa tabla, capa y mes, del más antiguo al más reciente (claves en minúscula)."""
    return _backend(conexion).consultar(entorno, tabla, capa, mes)


def mes_ya_procesado(corrida: Any, tabla: str, capa: str, mes: str, conexion: Any = None) -> bool:
    """LA PUERTA. True = se salta; False = se ingesta.

    Con reprocesar=true no se consulta nada: siempre se ingesta.
    """
    if corrida.reprocesar:
        return False
    return len(consultar_control(corrida.entorno, tabla, capa, mes, conexion)) > 0


def registrar_control(
    corrida: Any,
    tabla: str,
    capa: str,
    mes: str,
    filas: int,
    inicio: datetime,
    fuente: str,
    leidas: int | None = None,
    conexion: Any = None,
) -> None:
    """Anota que el paso terminó bien. `filas` son las escritas; `leidas` es solo informativo."""
    registro = {
        "fuente": fuente,
        "capa": capa,
        "tabla": tabla,
        "mes": mes,
        "filas": int(filas),
        "inicio": inicio_en_utc(inicio),
        "reprocesar": bool(corrida.reprocesar),
        "computo": corrida.computo,
        "limite": corrida.limite,
        "leidas": None if leidas is None else int(leidas),
    }
    _backend(conexion).registrar(corrida.entorno, registro)


def con_control(
    corrida: Any,
    tabla: str,
    capa: str,
    mes: str,
    fuente: str,
    trabajo: Callable[[], tuple[int, int]],
    conexion: Any = None,
):
    """Puerta y registro juntos, para silver, gold y snowflake.

    Si la puerta dice que se salta, no corre `trabajo` y devuelve Resultado('SE SALTÓ') con las
    cifras del último registro. Si no, corre `trabajo()` (que devuelve (leidas, escritas)), anota
    el registro y devuelve Resultado('REGISTRÓ'). Si `trabajo` falla no se anota nada, así el mes
    se puede volver a intentar. No imprime.
    """
    from pipeline.herramientas.corrida import Resultado

    if mes_ya_procesado(corrida, tabla, capa, mes, conexion):
        previos = consultar_control(corrida.entorno, tabla, capa, mes, conexion)
        ultimo = previos[-1] if previos else {}
        escritas = ultimo.get("filas") or 0
        leidas = ultimo.get("leidas")
        return Resultado(
            tabla, capa, mes, escritas if leidas is None else leidas, escritas, "SE SALTÓ"
        )

    inicio = datetime.now(UTC).replace(microsecond=0)
    leidas, escritas = trabajo()
    registrar_control(corrida, tabla, capa, mes, escritas, inicio, fuente, leidas, conexion)
    return Resultado(tabla, capa, mes, leidas, escritas, "REGISTRÓ")


def vaciar_control(entorno: str, conexion: Any = None) -> int:
    """Borra todos los registros de CONTROL_<ENTORNO> (solo ese entorno). Lo usa el reset."""
    return _backend(conexion).vaciar(entorno)
