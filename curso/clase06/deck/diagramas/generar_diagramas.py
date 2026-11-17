"""Genera los cinco diagramas de la clase 6 (Dc6-0 a Dc6-4).

Uso:  cd /Users/diegomanzur/Documents/udem/bigdata/bigdata-udem-2026/curso/clase06/deck/diagramas && python3 generar_diagramas.py

Lienzo 1120x440 (1:1 en la slide). Todo el texto mide 22 px o más. El color cobre es solo de
bronze, el gris azulado de silver y el ocre de gold; el acento (azul) es solo de la tabla de
control y de las flechas de consulta y registro, y del marco del DAG.
"""

from pathlib import Path
from xml.sax.saxutils import escape

from PIL import ImageFont

INK, GRIS, PANEL, ACENTO, REGLA, BLANCO = (
    "#15171C",
    "#5F6672",
    "#F0EEE7",
    "#2340D8",
    "#D9D6CC",
    "#FFFFFF",
)
BRONZE, SILVER, GOLD = "#B4622F", "#6E7F94", "#B07F0E"
T_BRONZE, T_SILVER, T_GOLD, T_ACENTO = "#F6E9E0", "#E4E8EE", "#F4EBD2", "#E3E6F6"
FONT = "Helvetica Neue, Arial, sans-serif"
MONO = "SF Mono, Menlo, Consolas, monospace"
W, H = 1120, 440
PASO = 27  # separación entre líneas de 22 px

_F = {}


def _fuente(bold, mono, size):
    clave = (bold, mono, size)
    if clave not in _F:
        if mono:
            _F[clave] = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", size, index=1 if bold else 0)
        else:
            ruta = "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf"
            _F[clave] = ImageFont.truetype(ruta, size)
    return _F[clave]


def ancho(t, size=22, bold=False, mono=False):
    return _fuente(bold, mono, size).getlength(t)


MARCAS = {"a": ACENTO, "g": GRIS, "b": BRONZE}


class S:
    def __init__(s, nombre, titulo, desc):
        s.nombre = nombre
        s.avisos = []
        s.o = [
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" font-family="{FONT}">',
            f"<title>{escape(titulo)}</title><desc>{escape(desc)}</desc>",
            "<defs>"
            + "".join(
                f'<marker id="m_{n}" markerUnits="userSpaceOnUse" markerWidth="12" markerHeight="12" '
                f'refX="12" refY="6" orient="auto"><path d="M0,0 L12,6 L0,12 Z" fill="{c}"/></marker>'
                for n, c in MARCAS.items()
            )
            + "</defs>",
        ]

    def rect(s, x, y, w, h, fill=PANEL, line=None, lw=1.5, r=6, dash=None):
        st = f' stroke="{line}" stroke-width="{lw}"' if line else ' stroke="none"'
        d = f' stroke-dasharray="{dash}"' if dash else ""
        s.o.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}"{st}{d}/>')
        if x < 0 or y < 0 or x + w > W or y + h > H:
            s.avisos.append(f"rect fuera del lienzo ({x},{y},{w},{h})")

    def text(s, x, y, t, size=22, col=INK, bold=False, anchor="start", mono=False, maxw=None):
        f = f' font-family="{MONO}"' if mono else ""
        b = ' font-weight="700"' if bold else ""
        s.o.append(
            f'<text x="{x}" y="{y}" font-size="{size}" fill="{col}" text-anchor="{anchor}"{b}{f}>{escape(t)}</text>'
        )
        w = ancho(t, size, bold, mono)
        x0 = x if anchor == "start" else (x - w / 2 if anchor == "middle" else x - w)
        if x0 < 0 or x0 + w > W:
            s.avisos.append(f"texto fuera del lienzo: {t!r} ({x0:.0f}..{x0 + w:.0f})")
        if maxw and w > maxw:
            s.avisos.append(f"texto más ancho que su caja: {t!r} ({w:.0f} > {maxw})")
        return w

    def lineas(s, x, y, ts, **kw):
        """Varias líneas con paso fijo; devuelve la y de la última."""
        for i, t in enumerate(ts):
            s.text(x, y + i * PASO, t, **kw)
        return y + (len(ts) - 1) * PASO

    def caja(s, x, y, w, h, ts, fill=PANEL, line=GRIS, lw=1.5, col=INK, bold=(True,), mono=False, dash=None, subcol=GRIS):
        """Caja con texto centrado; la primera línea va en negrita y las demás, en `subcol`."""
        s.rect(x, y, w, h, fill=fill, line=line, lw=lw, dash=dash)
        n = len(ts)
        y0 = y + (h - (n - 1) * PASO) / 2 + 8
        for i, t in enumerate(ts):
            if i == 0:
                s.text(x + w / 2, y0, t, bold=True, col=col, anchor="middle", mono=mono, maxw=w - 8)
            else:
                s.text(x + w / 2, y0 + i * PASO, t, col=(subcol if col == INK else col), anchor="middle", maxw=w - 8)

    def flecha(s, x1, y1, x2, y2, col="g", lw=2.5, doble=False):
        c = MARCAS[col]
        ini = f' marker-start="url(#m_{col})"' if doble else ""
        s.o.append(
            f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{c}" stroke-width="{lw}" '
            f'marker-end="url(#m_{col})"{ini}/>'
        )

    def linea(s, x1, y1, x2, y2, col=GRIS, lw=2.5, dash=None):
        d = f' stroke-dasharray="{dash}"' if dash else ""
        s.o.append(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{col}" stroke-width="{lw}"{d}/>')

    def guardar(s, ruta):
        Path(ruta).write_text("\n".join(s.o + ["</svg>"]) + "\n", encoding="utf-8")
        tams = {int(t) for t in __import__("re").findall(r'font-size="(\d+)"', "".join(s.o))}
        print(f"{s.nombre}: tamaños {sorted(tams)}; avisos: {s.avisos or 'ninguno'}")


# --------------------------------------------------------------------------- Dc6-0
def dc6_0(ruta):
    s = S(
        "Dc6-0",
        "Mapa de la clase 6: de las fuentes a Snowflake, con Athena, el lab y el DAG de Airflow",
        "De izquierda a derecha, tres fuentes (viajes, zonas, clima) llegan a la ingesta, que escribe bronze; Athena mira bronze; "
        "el lab construye silver y gold; gold se carga a Snowflake. Un marco que envuelve las cinco tareas es el DAG de Airflow. "
        "Arriba, la tabla de control en Snowflake, con flechas de consulta y de registro.",
    )
    # tabla de control y sus dos flechas
    s.rect(262, 6, 596, 46, fill=T_ACENTO, line=ACENTO, lw=2.5)
    s.text(280, 37, "Tabla de control · BIGDATA.CONTROL.WATERMARK", bold=True, col=ACENTO, maxw=570)
    s.flecha(292, 128, 292, 54, col="a")
    s.flecha(362, 128, 362, 54, col="a")
    s.text(284, 92, "¿ya lo traje?", col=ACENTO, anchor="end")
    s.text(374, 92, "lo traje", col=ACENTO)
    # marco del DAG
    s.rect(248, 104, 648, 262, fill="none", line=ACENTO, lw=2.5, dash="9 6")
    s.text(884, 134, "DAG ingesta_mensual de Airflow", bold=True, col=ACENTO, anchor="end")
    # fuentes
    for i, (a, b) in enumerate((("Viajes TLC", "Parquet"), ("Zonas TLC", "CSV"), ("Clima Open-Meteo", "JSON"))):
        y = 128 + i * 74
        s.caja(8, y, 216, 64, [a, b])
        s.flecha(226, y + 32, 260, y + 32)
    # línea principal
    s.caja(262, 128, 130, 212, ["Ingesta", "(clase 5)"])
    s.flecha(394, 234, 428, 234)
    s.caja(430, 194, 130, 80, ["Bronze"], fill=BRONZE, line=BRONZE, col=BLANCO)
    s.flecha(562, 234, 596, 234)
    s.caja(598, 194, 120, 80, ["Silver"], fill=SILVER, line=SILVER, col=BLANCO)
    s.flecha(720, 234, 754, 234)
    s.caja(756, 194, 120, 80, ["Gold"], fill=GOLD, line=GOLD, col=BLANCO)
    s.flecha(878, 234, 928, 234)
    s.caja(930, 194, 182, 80, ["Snowflake"])
    # lab
    s.linea(598, 300, 876, 300, col=GRIS, lw=2)
    s.linea(598, 292, 598, 300, col=GRIS, lw=2)
    s.linea(876, 292, 876, 300, col=GRIS, lw=2)
    s.text(737, 330, "Lab", bold=True, anchor="middle")
    # athena
    s.flecha(495, 388, 495, 277, col="g")
    s.text(509, 338, "solo mirar", col=GRIS)
    s.caja(400, 390, 190, 46, ["Athena"])
    s.guardar(ruta)


# --------------------------------------------------------------------------- Dc6-1
def dc6_1(ruta):
    s = S(
        "Dc6-1",
        "Athena consulta el lake: catálogo, carpetas por mes y workgroup",
        "A la izquierda, una consulta SQL entra a Athena. Athena consulta un catálogo (base bigdata_lake) que dice dónde están los archivos "
        "y qué columnas tienen, y lee en S3 solo las carpetas mes= que el filtro pide. Abajo, el workgroup bigdata-wg con su tope de 1 GB leído por consulta.",
    )
    # consulta, athena y catálogo
    s.rect(8, 170, 312, 100, fill=PANEL, line=GRIS)
    s.text(164, 206, "Consulta SQL", bold=True, anchor="middle")
    s.text(164, 246, "WHERE mes = '2024-01'", mono=True, anchor="middle", maxw=300)
    s.flecha(322, 220, 362, 220)
    s.caja(364, 170, 170, 100, ["Athena"])
    s.rect(316, 6, 290, 112, fill=BLANCO, line=GRIS, lw=1.5)
    s.text(461, 36, "Catálogo bigdata_lake", bold=True, anchor="middle", maxw=280)
    s.text(461, 66, "dónde están los archivos", anchor="middle", maxw=280)
    s.text(461, 93, "y qué columnas tienen", anchor="middle", maxw=280)
    s.flecha(449, 168, 449, 120, col="g", doble=True)
    # S3
    s.rect(646, 6, 466, 368, fill=PANEL, line=GRIS)
    s.text(666, 38, "S3 · bronze/fhvhv/", bold=True, maxw=430)
    meses = [f"mes=2024-{m:02d}" for m in range(1, 13)]
    for i, m in enumerate(meses):
        col, fila = divmod(i, 6)
        x, y = 666 + col * 218, 56 + fila * 44
        if i == 0:
            s.rect(x, y, 200, 36, fill=T_BRONZE, line=BRONZE, lw=3)
            s.text(x + 100, y + 26, m, mono=True, bold=True, col=BRONZE, anchor="middle", maxw=190)
        else:
            s.rect(x, y, 200, 36, fill="#F8F7F3", line=REGLA, lw=1.5)
            s.text(x + 100, y + 26, m, mono=True, col=GRIS, anchor="middle", maxw=190)
    s.text(666, 346, "Las otras once carpetas no se abren.", col=GRIS, maxw=430)
    s.flecha(536, 214, 662, 78, col="b", lw=3)
    s.text(580, 210, "se lee", bold=True, col=BRONZE)
    # poda
    s.text(8, 308, "Una sola columna, pickup_datetime:", col=GRIS, maxw=620)
    s.text(8, 340, "Con filtro de mes lee una carpeta: 53 MB", bold=True, col=BRONZE, maxw=620)
    s.text(8, 372, "Sin filtro abre las doce: 641 MB", bold=True, col=INK, maxw=620)
    # workgroup
    s.rect(8, 390, 1104, 46, fill=PANEL, line=GRIS)
    s.text(
        560,
        421,
        "Workgroup bigdata-wg · tope de 1 GB leído por consulta · resultados en S3",
        bold=True,
        anchor="middle",
        maxw=1080,
    )
    s.guardar(ruta)


# --------------------------------------------------------------------------- Dc6-2
def dc6_2(ruta):
    s = S(
        "Dc6-2",
        "DAG ingesta_mensual: cinco tareas en orden",
        "Cinco cajas conectadas en fila por flechas: ingestar_zonas, ingestar_clima, ingestar_viajes, silver, gold. Un marco las agrupa con el rótulo ingesta_mensual. "
        "Debajo de las tres primeras, la función de ingesta_alumno.py que llaman; debajo de silver y gold, el código del repositorio. "
        "Arriba del marco, dos parámetros: mes y reprocesar, y la tabla de control a la que las cinco tareas consultan y registran.",
    )
    # pastillas y tabla de control
    s.rect(8, 6, 196, 42, fill=PANEL, line=GRIS, r=21)
    s.text(106, 35, "mes: 2024-02", bold=True, anchor="middle", maxw=186)
    s.rect(218, 6, 250, 42, fill=PANEL, line=GRIS, r=21)
    s.text(343, 35, "reprocesar: falso", bold=True, anchor="middle", maxw=240)
    s.rect(540, 6, 572, 46, fill=T_ACENTO, line=ACENTO, lw=2.5)
    s.text(826, 37, "Tabla de control · BIGDATA.CONTROL.WATERMARK", bold=True, col=ACENTO, anchor="middle", maxw=560)
    # bus de consulta y registro
    xs = [17 + i * 224 for i in range(5)]
    cx = [x + 95 for x in xs]
    s.text(cx[0] - 8, 76, "cada tarea consulta y registra", col=ACENTO, maxw=500)
    s.linea(cx[0], 88, cx[4], 88, col=ACENTO, lw=2.5)
    for c in cx:
        s.linea(c, 88, c, 146, col=ACENTO, lw=2.5)
    s.flecha(826, 88, 826, 54, col="a")
    # marco
    s.rect(6, 102, 1108, 332, fill="none", line=ACENTO, lw=2.5, dash="9 6")
    nombres = ["ingestar_zonas", "ingestar_clima", "ingestar_viajes", "silver", "gold"]
    for i, (x, n) in enumerate(zip(xs, nombres)):
        if i < 3:
            s.caja(x, 146, 190, 80, [n])
        elif i == 3:
            s.caja(x, 146, 190, 80, [n], fill=SILVER, line=SILVER, col=BLANCO)
        else:
            s.caja(x, 146, 190, 80, [n], fill=GOLD, line=GOLD, col=BLANCO)
        if i < 4:
            s.flecha(x + 192, 186, xs[i + 1] - 2, 186)
    firmas = [["(reprocesar)"], ["(mes, reprocesar)"], ["(mes, reprocesar,", "limite_filas=1000)"], ["pipeline.silver"], ["pipeline.gold"]]
    for c, f in zip(cx, firmas):
        s.lineas(c, 262, f, anchor="middle", col=GRIS, maxw=214)
    # corchetes
    for x1, x2, t in ((xs[0], xs[2] + 190, "tus funciones de ingesta_alumno.py"), (xs[3], xs[4] + 190, "código del repositorio")):
        s.linea(x1, 330, x2, 330, col=GRIS, lw=2)
        s.linea(x1, 320, x1, 330, col=GRIS, lw=2)
        s.linea(x2, 320, x2, 330, col=GRIS, lw=2)
        s.text((x1 + x2) / 2, 360, t, bold=True, anchor="middle", maxw=x2 - x1)
    s.text(22, 418, "DAG ingesta_mensual", bold=True, col=ACENTO)
    s.text(1098, 418, "Una tarea espera a que termine la anterior", col=GRIS, anchor="end")
    s.guardar(ruta)


# --------------------------------------------------------------------------- Dc6-3
def dc6_3(ruta):
    s = S(
        "Dc6-3",
        "Idempotencia: un mecanismo por capa",
        "Tres columnas, una por mecanismo. Silver y gold: reemplazar la partición del día o del mes. Bronze: cada ingesta escribe un lote nuevo y silver lee el último lote "
        "completo, marcado con _LOTE_COMPLETO. Tabla de control: solo se registra al terminar bien, y se consulta antes de trabajar. Abajo, el caso de la pregunta del descanso: "
        "una tarea que falla a mitad deja un lote sin marcador y ninguna fila en la tabla.",
    )
    cols = [(4, 336), (352, 396), (764, 352)]
    for (x, w), t in zip(cols, ("Silver y gold", "Bronze", "Tabla de control")):
        s.rect(x, 4, w, 44, fill=INK, line=None, r=6)
        s.text(x + w / 2, 34, t, bold=True, col=BLANCO, anchor="middle", maxw=w - 10)
    # 1. silver y gold
    s.rect(14, 62, 316, 42, fill=PANEL, line=GRIS)
    s.text(172, 91, "pickup_date=2024-02-05", mono=True, col=GRIS, anchor="middle", maxw=306)
    s.flecha(40, 108, 40, 168, col="g", lw=3)
    s.text(56, 144, "sobrescribe, no suma", bold=True, maxw=270)
    s.rect(14, 172, 316, 42, fill=T_SILVER, line=SILVER, lw=3)
    s.text(172, 201, "pickup_date=2024-02-05", mono=True, bold=True, anchor="middle", maxw=306)
    s.lineas(172, 256, ["gold hace lo mismo con", "la carpeta mes=2024-02"], anchor="middle", col=GRIS, maxw=316)
    # 2. bronze
    for i in range(3):
        y = 62 + i * 46
        s.rect(366, y, 130, 38, fill=T_BRONZE, line=BRONZE, lw=2)
        s.text(431, y + 27, "lote=…", mono=True, anchor="middle", maxw=120)
    s.rect(506, 62 + 2 * 46, 226, 38, fill=BRONZE, line=BRONZE)
    s.text(619, 62 + 2 * 46 + 27, "_LOTE_COMPLETO", mono=True, bold=True, col=BLANCO, anchor="middle", maxw=216)
    s.text(506, 232, "↑ silver lee este lote", bold=True, col=BRONZE, maxw=236)
    s.rect(366, 252, 130, 38, fill="#F8F7F3", line=REGLA, lw=2)
    s.text(431, 279, "lote=…", mono=True, col=GRIS, anchor="middle", maxw=120)
    s.linea(372, 284, 490, 258, col=GRIS, lw=3)
    s.text(506, 279, "a medias: nadie la lee", col=GRIS, maxw=236)
    # 3. tabla de control
    s.text(940, 78, "se consulta antes de trabajar", col=ACENTO, anchor="middle", maxw=346)
    s.flecha(940, 90, 940, 120, col="a")
    s.rect(780, 124, 320, 108, fill=BLANCO, line=ACENTO, lw=2.5)
    s.linea(780, 160, 1100, 160, col=ACENTO, lw=1.5)
    s.text(796, 150, "capa · mes", col=GRIS, bold=True)
    s.text(796, 190, "bronze · 2024-02", maxw=300)
    s.text(796, 224, "silver · 2024-02", maxw=300)
    s.flecha(940, 272, 940, 234, col="a")
    s.lineas(940, 298, ["se escribe solo al", "terminar bien"], anchor="middle", col=ACENTO, maxw=346)
    # franja
    s.rect(4, 336, 1112, 100, fill=PANEL, line=None)
    s.text(20, 368, "Caso del descanso:", bold=True)
    s.text(
        20,
        396,
        "la tarea falla a la mitad y bronze queda con un lote sin sello; la tabla no tiene fila;",
        maxw=1090,
    )
    s.text(20, 424, "el reintento escribe un lote nuevo y registra.", maxw=1090)
    s.guardar(ruta)


# --------------------------------------------------------------------------- Dc6-4
def dc6_4(ruta):
    s = S(
        "Dc6-4",
        "De hoy a la clase 7: del DAG local a Glue y las tres comprobaciones",
        "Dos filas. Hoy: el DAG ingesta_mensual en el Code Editor con Spark local y viajes de 1 000 filas. Clase 7: el DAG pipeline_taxi, que tiene el parámetro de cómputo, "
        "lanza los jobs de Glue sobre el mes completo; debajo, tres comprobaciones: filas de bronze, silver y gold contra la tabla de control, Athena sobre silver y Snowflake sobre gold.",
    )
    filas = [
        (6, "Hoy", "Code Editor", ["DAG ingesta_mensual"], ["Spark local"], ["viajes de 1 000 filas"]),
        (118, "Clase 7", "Glue", ["pipeline_taxi", "con el parámetro de cómputo"], ["Jobs de Glue"], ["mes completo", "o el año"]),
    ]
    for y, a, b, c1, c2, c3 in filas:
        s.text(8, y + 28, a, bold=True, col=ACENTO)
        s.text(8, y + 55, b, bold=True, col=INK)
        s.caja(190, y, 350, 64, c1, fill=BLANCO)
        s.flecha(542, y + 32, 586, y + 32)
        s.caja(588, y, 196, 64, c2, fill=BLANCO)
        s.flecha(786, y + 32, 832, y + 32)
        s.caja(834, y, 278, 64, c3, fill=BLANCO)
    s.flecha(365, 72, 365, 116, col="g", lw=3)
    s.text(382, 102, "cambia el DAG y dónde corre", bold=True, maxw=380)
    # comprobaciones de la clase 7
    s.rect(4, 204, 1112, 232, fill=PANEL, line=None)
    s.rect(12, 212, 1096, 44, fill=T_ACENTO, line=ACENTO, lw=2.5)
    s.text(560, 241, "Filas de bronze, silver y gold contra la tabla de control", bold=True, col=ACENTO, anchor="middle", maxw=1070)
    for cxm, c, n in ((360, BRONZE, "Bronze"), (650, SILVER, "Silver"), (940, GOLD, "Gold")):
        s.flecha(cxm, 258, cxm, 284, col="a")
        s.caja(cxm - 90, 286, 180, 42, [n], fill=c, line=c, col=BLANCO)
    for cxm, ts in ((650, ["Athena sobre silver:", "filas, repetidos, nulos"]), (940, ["Snowflake sobre gold:", "filas y huérfanos"])):
        s.flecha(cxm, 350, cxm, 330, col="g")
        s.caja(cxm - 140, 352, 280, 76, ts, fill=BLANCO)
    s.text(20, 380, "Tres comprobaciones", bold=True)
    s.text(20, 407, "de la clase 7", bold=True)
    s.guardar(ruta)


if __name__ == "__main__":
    base = Path(__file__).parent
    dc6_0(base / "Dc6-0.svg")
    dc6_1(base / "Dc6-1.svg")
    dc6_2(base / "Dc6-2.svg")
    dc6_3(base / "Dc6-3.svg")
    dc6_4(base / "Dc6-4.svg")
