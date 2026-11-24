"""Genera el diagrama de la parte 1 de la clase 8 (Dc8-0.svg).

Uso:  cd ~/bigdata/curso/clase08/deck/diagramas && python3 generar_diagramas.py
No necesita librerías externas. Lienzo 1120x440 (1:1 en la slide), texto de 22 px o más.
El color cobre es solo de bronze, el gris azulado de silver y el ocre de gold.
"""

from pathlib import Path
from xml.sax.saxutils import escape

INK, GRIS, PANEL, ACENTO, ROJO = "#15171C", "#5F6672", "#F0EEE7", "#2340D8", "#B3261E"
CAPAS = {
    "bronze": ("#B4622F", "#F6E9E0"),
    "silver": ("#6E7F94", "#E4E8EE"),
    "gold": ("#B07F0E", "#F4EBD2"),
    "snowflake": ("#2340D8", "#E3E6F6"),
}
FONT = "Helvetica Neue, Arial, sans-serif"
W, H = 1120, 440
ANCHO, SEP, X0 = 250, 30, 15

# (capa, archivo, [(verbo, [líneas])])
CAJAS = [
    (
        "bronze",
        "bronze.py",
        [("Revisar", ["debe_ingestar", "registrar_ingesta"]), ("Completar", ["agregar_metadatos"])],
    ),
    (
        "silver",
        "silver.py",
        [("Completar", ["deduplicar"]), ("Modificar", ["limpiar_viajes", "o enriquecer"])],
    ),
    (
        "gold",
        "gold.py",
        [("Modificar", ["TABLAS_GOLD"]), ("Crear", ["tu función de gold"])],
    ),
    (
        "snowflake",
        "carga.py",
        [("Revisar", ["cargar_gold"]), ("Crear", ["DDL y tabla en Snowsight"])],
    ),
]
COLOR_VERBO = {"Revisar": GRIS, "Completar": ROJO, "Modificar": INK, "Crear": ACENTO}


def texto(x, y, s, size=22, bold=False, fill=INK):
    peso = ' font-weight="700"' if bold else ""
    return (
        f'<text x="{x}" y="{y}" font-family="{FONT}" font-size="{size}"{peso} '
        f'fill="{fill}">{escape(s)}</text>'
    )


partes = [
    f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">',
    f'<rect width="{W}" height="{H}" fill="#FFFFFF"/>',
]
for i, (capa, archivo, grupos) in enumerate(CAJAS):
    x = X0 + i * (ANCHO + SEP)
    fuerte, tenue = CAPAS[capa]
    partes.append(
        f'<rect x="{x}" y="20" width="{ANCHO}" height="330" rx="10" fill="{tenue}" '
        f'stroke="{fuerte}" stroke-width="3"/>'
    )
    partes.append(texto(x + 16, 62, archivo, 28, True, fuerte))
    y = 108
    for verbo, lineas in grupos:
        partes.append(texto(x + 16, y, verbo, 22, True, COLOR_VERBO[verbo]))
        for linea in lineas:
            y += 27
            partes.append(texto(x + 16, y, linea))
        y += 50
    if i < len(CAJAS) - 1:
        xf = x + ANCHO
        partes.append(
            f'<path d="M{xf + 4} 185 L{xf + SEP - 4} 185" stroke="{GRIS}" stroke-width="3"/>'
        )
partes.append(
    texto(15, 395, "Revisar: entender, no tocar.  Completar: obligatorio.", 22, False, GRIS)
)
partes.append(texto(15, 425, "Modificar y Crear: según tu contrato.", 22, False, GRIS))
partes.append("</svg>")
(Path(__file__).parent / "Dc8-0.svg").write_text("\n".join(partes), encoding="utf-8")
print("Dc8-0.svg")
