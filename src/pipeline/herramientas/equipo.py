"""Ayudas del cuaderno de la clase 7: probar y usar TUS funciones sin tocar los .py.

    usar_mis_funciones(agregar_metadatos=agregar_metadatos, deduplicar=deduplicar)
    probar_mis_funciones(agregar_metadatos=agregar_metadatos, deduplicar=deduplicar)

Las funciones del equipo viven en bronze.py (agregar_metadatos, debe_ingestar,
registrar_ingesta) y en silver.py (deduplicar). Mientras no las pases a esos archivos, el cuaderno
puede ponerlas «encima» para que `correr_bronze()` y `correr_silver()` usen las tuyas.

Este módulo no importa pyspark ni los pasos al cargarse: la caja de herramientas corre también en
la VM de Airflow (los pasos se importan solo cuando se necesitan).
"""

from __future__ import annotations

import sys
from collections.abc import Iterator
from contextlib import contextmanager
from importlib import import_module
from pathlib import Path

# nombre de la función -> módulo de pipeline donde vive.
DONDE_VIVEN = {
    "agregar_metadatos": "pipeline.bronze",
    "debe_ingestar": "pipeline.bronze",
    "registrar_ingesta": "pipeline.bronze",
    "deduplicar": "pipeline.silver",
}

# Las pruebas del equipo son las mismas que corre `make test`.
ARCHIVOS_DE_PRUEBA = ("test_equipo_bronze.py", "test_equipo_silver.py")

CARPETA_DE_PRUEBAS = Path(__file__).resolve().parents[3] / "tests"


def _validar_nombres(funciones: dict) -> None:
    """Falla si llega un nombre que no es un hueco del equipo, o algo que no es una función."""
    for nombre, funcion in funciones.items():
        if nombre not in DONDE_VIVEN:
            validos = ", ".join(DONDE_VIVEN)
            raise ValueError(
                f"'{nombre}' no es una función del equipo. Las válidas son: {validos}."
            )
        if not callable(funcion):
            raise TypeError(f"{nombre} debe ser una función, pero llegó {type(funcion).__name__}.")


def _computo_configurado() -> str:
    """El cómputo que usaría la próxima corrida (pipeline.yaml; nunca falla)."""
    from pipeline.herramientas.corrida import valores_de_pipeline_yaml

    return valores_de_pipeline_yaml()["computo"]


def usar_mis_funciones(**funciones) -> None:
    """Pone tus funciones en pipeline.bronze y pipeline.silver, solo en este proceso.

    Nombres válidos: agregar_metadatos, debe_ingestar, registrar_ingesta y deduplicar. Otro
    nombre es un error. Los .py no cambian: al reiniciar el cuaderno vuelven las de la casa.

    Con un cómputo de Glue falla: tus funciones del cuaderno viven en este proceso y no viajan a
    Glue. Cópialas a bronze.py (o silver.py) y corre de nuevo.
    """
    _validar_nombres(funciones)
    computo = _computo_configurado()
    if computo.startswith("glue_"):
        raise RuntimeError(
            f"pipeline.yaml usa el cómputo {computo}: tus funciones del cuaderno no viajan a "
            "Glue. Cópialas a bronze.py (agregar_metadatos, debe_ingestar, registrar_ingesta) o "
            "a silver.py (deduplicar), o usa computo: code_editor."
        )
    for nombre, funcion in funciones.items():
        modulo = import_module(DONDE_VIVEN[nombre])
        setattr(modulo, nombre, funcion)
        print(f"USA      {nombre} del cuaderno en {DONDE_VIVEN[nombre]} (solo en este proceso)")


@contextmanager
def _funciones_puestas(funciones: dict) -> Iterator[None]:
    """Pone las funciones mientras dura el bloque y deja los módulos como estaban."""
    anteriores = []
    for nombre, funcion in funciones.items():
        modulo = import_module(DONDE_VIVEN[nombre])
        anteriores.append((modulo, nombre, getattr(modulo, nombre)))
        setattr(modulo, nombre, funcion)
    try:
        yield
    finally:
        for modulo, nombre, original in anteriores:
            setattr(modulo, nombre, original)


class _Resumen:
    """Plugin de pytest: anota qué pasó con cada prueba para contarlo en español."""

    def __init__(self) -> None:
        self.lineas: list[tuple[str, str, str]] = []  # (estado, prueba, motivo)

    def pytest_runtest_logreport(self, report) -> None:
        prueba = report.nodeid.split("::")[-1].removeprefix("test_").replace("_", " ")
        if report.skipped:
            motivo = (
                report.longrepr[2] if isinstance(report.longrepr, tuple) else str(report.longrepr)
            )
            motivo = motivo.removeprefix("Skipped: ")
            estado = "PENDIENTE" if motivo.startswith("PENDIENTE") else "OMITIDA"
            self.lineas.append((estado, prueba, motivo))
        elif report.when == "call":
            estado = "OK" if report.passed else "FALLA"
            self.lineas.append((estado, prueba, ""))
        elif report.failed:  # falló al preparar la prueba o al limpiarla
            self.lineas.append(("FALLA", prueba, ""))

    def contar(self) -> str:
        cuentas = {}
        for estado, _, _ in self.lineas:
            cuentas[estado] = cuentas.get(estado, 0) + 1
        return ", ".join(f"{cantidad} {estado}" for estado, cantidad in cuentas.items())


def probar_mis_funciones(**funciones) -> int:
    """Corre en este proceso las MISMAS pruebas de make test, usando tus funciones.

    Son tests/test_equipo_bronze.py y tests/test_equipo_silver.py. Imprime una línea por prueba:
    OK, PENDIENTE (a la función todavía le queda la marca # PENDIENTE(equipo)) o FALLA, y
    devuelve el código de pytest: 0 si no falló ninguna.
    """
    _validar_nombres(funciones)
    import pytest

    archivos = [CARPETA_DE_PRUEBAS / nombre for nombre in ARCHIVOS_DE_PRUEBA]
    faltan = [str(archivo) for archivo in archivos if not archivo.exists()]
    if faltan:
        raise FileNotFoundError(f"No encuentro las pruebas del equipo: {', '.join(faltan)}")

    resumen = _Resumen()
    argumentos = ["-q", "--no-header", "--tb=short", "-p", "no:cacheprovider"]
    argumentos += [str(archivo) for archivo in archivos]
    with _funciones_puestas(funciones):
        codigo = int(pytest.main(argumentos, plugins=[resumen]))

    print("\nPruebas del equipo (las mismas de make test):")
    for estado, prueba, motivo in resumen.lineas:
        detalle = f"  <- {motivo}" if motivo else ""
        print(f"  {estado:<10} {prueba}{detalle}")
    print(f"  Resumen: {resumen.contar()}")
    sys.stdout.flush()
    return codigo
