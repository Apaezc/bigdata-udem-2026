"""Genera los diagramas de la clase 6 (Dc6-0 a Dc6-12; Dc6-7 a Dc6-11 envuelven capturas reales de Airflow).

Uso:  cd /Users/diegomanzur/Documents/udem/bigdata/bigdata-udem-2026/curso/clase06/deck/diagramas && python3 generar_diagramas.py

Lienzo 1120x440 (1:1 en la slide). Todo el texto mide 22 px o más. El color cobre es solo de
bronze, el gris azulado de silver y el ocre de gold; el acento (azul) es solo de la tabla de
control y de las flechas de consulta y registro, y del marco del DAG.
"""

import base64
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
AMARILLO, ROJO, T_ROJO = "#FFC83D", "#B3261E", "#F8E0DC"  # llamadas sobre capturas; error
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
            _F[clave] = ImageFont.truetype(
                "/System/Library/Fonts/Menlo.ttc", size, index=1 if bold else 0
            )
        else:
            ruta = (
                "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
                if bold
                else "/System/Library/Fonts/Supplemental/Arial.ttf"
            )
            _F[clave] = ImageFont.truetype(ruta, size)
    return _F[clave]


def ancho(t, size=22, bold=False, mono=False):
    return _fuente(bold, mono, size).getlength(t)


MARCAS = {"a": ACENTO, "g": GRIS, "b": BRONZE, "y": AMARILLO}


class S:
    def __init__(s, nombre, titulo, desc, w=W, h=H):
        s.nombre = nombre
        s.w, s.h = w, h
        s.avisos = []
        s.o = [
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" font-family="{FONT}">',
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
        s.o.append(
            f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}"{st}{d}/>'
        )
        if x < 0 or y < 0 or x + w > s.w or y + h > s.h:
            s.avisos.append(f"rect fuera del lienzo ({x},{y},{w},{h})")

    def text(s, x, y, t, size=22, col=INK, bold=False, anchor="start", mono=False, maxw=None):
        f = f' font-family="{MONO}"' if mono else ""
        b = ' font-weight="700"' if bold else ""
        s.o.append(
            f'<text x="{x}" y="{y}" font-size="{size}" fill="{col}" text-anchor="{anchor}"{b}{f}>{escape(t)}</text>'
        )
        w = ancho(t, size, bold, mono)
        x0 = x if anchor == "start" else (x - w / 2 if anchor == "middle" else x - w)
        if x0 < 0 or x0 + w > s.w:
            s.avisos.append(f"texto fuera del lienzo: {t!r} ({x0:.0f}..{x0 + w:.0f})")
        if maxw and w > maxw:
            s.avisos.append(f"texto más ancho que su caja: {t!r} ({w:.0f} > {maxw})")
        return w

    def lineas(s, x, y, ts, **kw):
        """Varias líneas con paso fijo; devuelve la y de la última."""
        for i, t in enumerate(ts):
            s.text(x, y + i * PASO, t, **kw)
        return y + (len(ts) - 1) * PASO

    def caja(
        s,
        x,
        y,
        w,
        h,
        ts,
        fill=PANEL,
        line=GRIS,
        lw=1.5,
        col=INK,
        bold=(True,),
        mono=False,
        dash=None,
        subcol=GRIS,
    ):
        """Caja con texto centrado; la primera línea va en negrita y las demás, en `subcol`."""
        s.rect(x, y, w, h, fill=fill, line=line, lw=lw, dash=dash)
        n = len(ts)
        y0 = y + (h - (n - 1) * PASO) / 2 + 8
        for i, t in enumerate(ts):
            if i == 0:
                s.text(x + w / 2, y0, t, bold=True, col=col, anchor="middle", mono=mono, maxw=w - 8)
            else:
                s.text(
                    x + w / 2,
                    y0 + i * PASO,
                    t,
                    col=(subcol if col == INK else col),
                    anchor="middle",
                    maxw=w - 8,
                )

    def flecha(s, x1, y1, x2, y2, col="g", lw=2.5, doble=False, dash=None):
        c = MARCAS[col]
        ini = f' marker-start="url(#m_{col})"' if doble else ""
        d = f' stroke-dasharray="{dash}"' if dash else ""
        s.o.append(
            f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{c}" stroke-width="{lw}"{d} '
            f'marker-end="url(#m_{col})"{ini}/>'
        )

    def linea(s, x1, y1, x2, y2, col=GRIS, lw=2.5, dash=None):
        d = f' stroke-dasharray="{dash}"' if dash else ""
        s.o.append(
            f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{col}" stroke-width="{lw}"{d}/>'
        )

    def guardar(s, ruta):
        Path(ruta).write_text("\n".join(s.o + ["</svg>"]) + "\n", encoding="utf-8")
        tams = {int(t) for t in __import__("re").findall(r'font-size="(\d+)"', "".join(s.o))}
        print(f"{s.nombre}: tamaños {sorted(tams)}; avisos: {s.avisos or 'ninguno'}")


# --------------------------------------------------------------------------- Dc6-0
def dc6_0(ruta):
    s = S(
        "Dc6-0",
        "Mapa de la clase 6: de las fuentes a gold, con Athena, el lab y el DAG de Airflow",
        "De izquierda a derecha, tres fuentes (viajes, zonas, clima) entran cada una a su tarea de ingesta (ingestar_viajes, ingestar_zonas, ingestar_clima), que escriben bronze; "
        "después vienen silver y gold. Un marco que envuelve las cinco tareas es el DAG ingesta_mensual de Airflow; el DAG no carga a Snowflake. Athena mira bronze desde abajo; "
        "el lab construye silver y gold. Arriba, la tabla de control en Snowflake, con flechas de consulta y de registro.",
    )
    # tabla de control y sus dos flechas
    s.rect(236, 6, 640, 46, fill=T_ACENTO, line=ACENTO, lw=2.5)
    s.text(254, 37, "Tabla de control · BIGDATA.CONTROL.WATERMARK", bold=True, col=ACENTO, maxw=610)
    s.flecha(300, 128, 300, 54, col="a")
    s.flecha(400, 128, 400, 54, col="a")
    s.text(292, 92, "¿ya lo traje?", col=ACENTO, anchor="end")
    s.text(412, 92, "lo traje", col=ACENTO)
    # marco del DAG
    s.rect(224, 104, 884, 262, fill="none", line=ACENTO, lw=2.5, dash="9 6")
    s.text(1096, 134, "DAG ingesta_mensual de Airflow", bold=True, col=ACENTO, anchor="end")
    # fuentes y las tres tareas de ingesta
    for i, (a, b, tarea) in enumerate(
        (
            ("Viajes TLC", "Parquet", "ingestar_viajes"),
            ("Zonas TLC", "CSV", "ingestar_zonas"),
            ("Clima Open-Meteo", "JSON", "ingestar_clima"),
        )
    ):
        y = 154 + i * 70
        s.caja(6, y, 208, 60, [a, b])
        s.flecha(216, y + 30, 242, y + 30)
        s.caja(244, y, 210, 60, [tarea], fill=BLANCO, mono=False)
    # bronze, silver, gold
    s.flecha(456, 184, 520, 232)
    s.flecha(456, 254, 520, 254)
    s.flecha(456, 324, 520, 276)
    s.caja(522, 214, 130, 80, ["Bronze"], fill=BRONZE, line=BRONZE, col=BLANCO)
    s.flecha(654, 254, 708, 254)
    s.caja(710, 214, 130, 80, ["Silver"], fill=SILVER, line=SILVER, col=BLANCO)
    s.flecha(842, 254, 896, 254)
    s.caja(898, 214, 130, 80, ["Gold"], fill=GOLD, line=GOLD, col=BLANCO)
    # lab
    s.linea(710, 304, 1028, 304, col=GRIS, lw=2)
    s.linea(710, 296, 710, 304, col=GRIS, lw=2)
    s.linea(1028, 296, 1028, 304, col=GRIS, lw=2)
    s.text(869, 338, "Lab", bold=True, anchor="middle")
    # athena
    s.flecha(587, 388, 587, 297, col="g")
    s.text(601, 350, "solo mirar", col=GRIS)
    s.caja(492, 390, 190, 46, ["Athena"])
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
    s.text(
        826,
        37,
        "Tabla de control · BIGDATA.CONTROL.WATERMARK",
        bold=True,
        col=ACENTO,
        anchor="middle",
        maxw=560,
    )
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
    for i, (x, n) in enumerate(zip(xs, nombres, strict=True)):
        if i < 3:
            s.caja(x, 146, 190, 80, [n])
        elif i == 3:
            s.caja(x, 146, 190, 80, [n], fill=SILVER, line=SILVER, col=BLANCO)
        else:
            s.caja(x, 146, 190, 80, [n], fill=GOLD, line=GOLD, col=BLANCO)
        if i < 4:
            s.flecha(x + 192, 186, xs[i + 1] - 2, 186)
    firmas = [
        ["(reprocesar)"],
        ["(mes, reprocesar)"],
        ["(mes, reprocesar,", "limite_filas=1000)"],
        ["pipeline.silver"],
        ["pipeline.gold"],
    ]
    for c, f in zip(cx, firmas, strict=True):
        s.lineas(c, 262, f, anchor="middle", col=GRIS, maxw=214)
    # corchetes
    for x1, x2, t in (
        (xs[0], xs[2] + 190, "tus funciones de ingesta_alumno.py"),
        (xs[3], xs[4] + 190, "código del repositorio"),
    ):
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
    for (x, w), t in zip(cols, ("Silver y gold", "Bronze", "Tabla de control"), strict=True):
        s.rect(x, 4, w, 44, fill=INK, line=None, r=6)
        s.text(x + w / 2, 34, t, bold=True, col=BLANCO, anchor="middle", maxw=w - 10)
    # 1. silver y gold
    s.rect(14, 62, 316, 42, fill=PANEL, line=GRIS)
    s.text(172, 91, "pickup_date=2024-02-05", mono=True, col=GRIS, anchor="middle", maxw=306)
    s.flecha(40, 108, 40, 168, col="g", lw=3)
    s.text(56, 144, "sobrescribe, no suma", bold=True, maxw=270)
    s.rect(14, 172, 316, 42, fill=T_SILVER, line=SILVER, lw=3)
    s.text(172, 201, "pickup_date=2024-02-05", mono=True, bold=True, anchor="middle", maxw=306)
    s.lineas(
        172,
        256,
        ["gold hace lo mismo con", "la carpeta mes=2024-02"],
        anchor="middle",
        col=GRIS,
        maxw=316,
    )
    # 2. bronze
    for i in range(3):
        y = 62 + i * 46
        s.rect(366, y, 130, 38, fill=T_BRONZE, line=BRONZE, lw=2)
        s.text(431, y + 27, "lote=…", mono=True, anchor="middle", maxw=120)
    s.rect(506, 62 + 2 * 46, 226, 38, fill=BRONZE, line=BRONZE)
    s.text(
        619,
        62 + 2 * 46 + 27,
        "_LOTE_COMPLETO",
        mono=True,
        bold=True,
        col=BLANCO,
        anchor="middle",
        maxw=216,
    )
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
    s.lineas(
        940, 298, ["se escribe solo al", "terminar bien"], anchor="middle", col=ACENTO, maxw=346
    )
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
        (
            6,
            "Hoy",
            "Code Editor",
            ["DAG ingesta_mensual"],
            ["Spark local"],
            ["viajes de 1 000 filas"],
        ),
        (
            118,
            "Clase 7",
            "Glue",
            ["pipeline_taxi", "con el parámetro de cómputo"],
            ["Jobs de Glue"],
            ["mes completo", "o el año"],
        ),
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
    s.text(
        560,
        241,
        "Filas de bronze, silver y gold contra la tabla de control",
        bold=True,
        col=ACENTO,
        anchor="middle",
        maxw=1070,
    )
    for cxm, c, n in ((360, BRONZE, "Bronze"), (650, SILVER, "Silver"), (940, GOLD, "Gold")):
        s.flecha(cxm, 258, cxm, 284, col="a")
        s.caja(cxm - 90, 286, 180, 42, [n], fill=c, line=c, col=BLANCO)
    for cxm, ts in (
        (650, ["Athena sobre silver:", "filas, repetidos, nulos"]),
        (940, ["Snowflake sobre gold:", "filas y huérfanos"]),
    ):
        s.flecha(cxm, 350, cxm, 330, col="g")
        s.caja(cxm - 140, 352, 280, 76, ts, fill=BLANCO)
    s.text(20, 380, "Tres comprobaciones", bold=True)
    s.text(20, 407, "de la clase 7", bold=True)
    s.guardar(ruta)


# --------------------------------------------------------------------------- Dc6-5
def dc6_5(ruta):
    s = S(
        "Dc6-5",
        "Dónde vive cada cosa: S3, el disco del Code Editor y Snowflake",
        "Tres zonas. A la izquierda, el bucket de S3 bigdata-lake-<CUENTA>-us-east-2 con el bronze del año (239 470 448 viajes), que Athena lee. En el centro, el disco del Code Editor: "
        "~/datos_clase05/ con bronze_alumno, silver_alumno y gold_alumno, que escribe el DAG ingesta_mensual (viajes 1 000 filas, silver 1 000, gold 281), y ~/datos_clase06/lake_lab, que escribe el lab. "
        "A la derecha, el DAG, el lab y la tabla de control de Snowflake BIGDATA.CONTROL.WATERMARK, con flechas punteadas de consulta y registro desde el DAG y el lab.",
    )
    # S3 y Athena
    s.rect(6, 14, 372, 196, fill=PANEL, line=GRIS)
    s.text(22, 46, "Bucket de S3", bold=True)
    s.text(22, 75, "bigdata-lake-<CUENTA>-us-east-2", maxw=344)
    s.rect(22, 100, 340, 92, fill=BRONZE, line=BRONZE)
    s.text(192, 134, "bronze del año", bold=True, col=BLANCO, anchor="middle", maxw=320)
    s.text(192, 168, "239 470 448 viajes", col=BLANCO, anchor="middle", maxw=320)
    s.flecha(192, 296, 192, 212, col="g")
    s.text(206, 262, "lee", bold=True)
    s.caja(92, 298, 200, 56, ["Athena"])
    # disco del Code Editor
    s.rect(398, 14, 350, 236, fill=PANEL, line=GRIS)
    s.text(414, 46, "Disco del Code Editor", bold=True)
    s.text(414, 75, "~/datos_clase05/", mono=True, maxw=320)
    for i, (n, c, f) in enumerate(
        (
            ("bronze_alumno", BRONZE, "1 000 filas"),
            ("silver_alumno", SILVER, "1 000 filas"),
            ("gold_alumno", GOLD, "281 filas"),
        )
    ):
        y = 94 + i * 50
        s.rect(414, y, 206, 42, fill=c, line=c)
        s.text(517, y + 29, n, mono=True, bold=True, col=BLANCO, anchor="middle", maxw=198)
        s.text(634, y + 29, f, maxw=108)
    s.rect(398, 270, 350, 90, fill=PANEL, line=GRIS)
    s.text(414, 304, "~/datos_clase06/lake_lab", mono=True, bold=True, maxw=326)
    s.text(414, 340, "silver y gold del lab", col=GRIS, maxw=326)
    # DAG, lab y tabla de control
    s.rect(842, 14, 272, 76, fill=BLANCO, line=ACENTO, lw=2.5, dash="9 6")
    s.text(978, 46, "DAG", bold=True, col=ACENTO, anchor="middle")
    s.text(978, 74, "ingesta_mensual", bold=True, col=ACENTO, anchor="middle", maxw=260)
    s.rect(842, 284, 272, 76, fill=BLANCO, line=GRIS, lw=2)
    s.text(978, 330, "Lab", bold=True, anchor="middle")
    s.flecha(840, 52, 750, 52, col="g", lw=3)
    s.text(795, 38, "escribe", bold=True, anchor="middle", maxw=86)
    s.flecha(840, 322, 750, 322, col="g", lw=3)
    s.text(795, 308, "escribe", bold=True, anchor="middle", maxw=86)
    s.rect(842, 150, 272, 100, fill=T_ACENTO, line=ACENTO, lw=2.5)
    s.text(978, 176, "Snowflake", bold=True, col=ACENTO, anchor="middle")
    s.text(978, 206, "BIGDATA.CONTROL.", col=ACENTO, anchor="middle", mono=True, maxw=262)
    s.text(978, 234, "WATERMARK", col=ACENTO, anchor="middle", mono=True, maxw=262)
    s.flecha(900, 92, 900, 148, col="a", dash="7 6", doble=True)
    s.flecha(900, 282, 900, 252, col="a", dash="7 6", doble=True)
    s.text(912, 126, "consulta / registra", col=ACENTO, maxw=202)
    s.text(912, 268, "consulta / registra", col=ACENTO, maxw=202)
    s.guardar(ruta)


# --------------------------------------------------------------------------- Dc6-6
def dc6_6(ruta):
    s = S(
        "Dc6-6",
        "Dos palancas para leer menos: meses y columnas",
        "Cuadrícula de dos por dos. Con una columna, un mes lee 53 MB y doce meses leen 641 MB. Con siete columnas, un mes lee 141 MB y doce meses superan 1 GB: "
        "la consulta queda CANCELLED con el mensaje Bytes scanned limit was exceeded. Abajo, el tope del workgroup: 1 GB por consulta.",
    )
    x0, cw, gap = 240, 420, 24
    xs = [x0, x0 + cw + gap]
    ys = [60, 214]
    ch = 142
    s.text(18, 28, "meses →", bold=True, col=GRIS)
    s.text(18, 52, "↓ columnas", bold=True, col=GRIS)
    for x, t in zip(xs, ("1 mes · WHERE mes = '2024-01'", "12 meses · sin filtro"), strict=True):
        s.text(x + cw / 2, 40, t, bold=True, anchor="middle", maxw=cw)
    filas = (("1 columna", "pickup_datetime"), ("7 columnas", "las del paso 8"))
    for y, (a, b) in zip(ys, filas, strict=True):
        s.text(18, y + ch / 2 - 2, a, bold=True, maxw=216)
        s.text(18, y + ch / 2 + 28, b, col=GRIS, maxw=216)
    celdas = (
        (0, 0, "53 MB", ["una carpeta, 1.1 s"], False),
        (0, 1, "641 MB", ["doce carpetas: 12 veces más"], False),
        (1, 0, "141 MB", ["una carpeta, 1.4 s"], False),
        (1, 1, "más de 1 GB", ["CANCELLED", "Bytes scanned limit was exceeded"], True),
    )
    for r, c, cifra, sub, mal in celdas:
        x, y = xs[c], ys[r]
        if mal:
            s.rect(x, y, cw, ch, fill=T_ROJO, line=ROJO, lw=3)
            s.text(x + cw / 2, y + 62, cifra, size=44, bold=True, col=ROJO, anchor="middle")
            s.text(x + cw / 2, y + 96, sub[0], bold=True, col=ROJO, anchor="middle", maxw=cw - 16)
            s.text(x + cw / 2, y + 124, sub[1], col=ROJO, anchor="middle", maxw=cw - 16)
        else:
            s.rect(x, y, cw, ch, fill=PANEL, line=GRIS)
            s.text(x + cw / 2, y + 74, cifra, size=44, bold=True, anchor="middle")
            s.text(x + cw / 2, y + 114, sub[0], col=GRIS, anchor="middle", maxw=cw - 16)
    s.rect(6, 374, 1108, 56, fill=BLANCO, line=GRIS)
    s.text(
        560,
        410,
        "Tope del workgroup: 1 GB leído por consulta (1 073 741 824 bytes)",
        bold=True,
        anchor="middle",
        maxw=1090,
    )
    s.guardar(ruta)


# --------------------------------------------------------------------------- capturas (Dc6-7 a Dc6-9)
CAPTURAS = Path(__file__).resolve().parent.parent / "capturas"


def _captura(nombre, titulo, desc, png, crop, ancho_lienzo, anotar):
    """Lienzo con un recorte de la captura. `crop` = (x, y, ancho, alto) en píxeles de la captura;
    `anotar(s, m)` dibuja llamadas con m(x, y) = punto de la captura en el lienzo."""
    from PIL import Image

    cx, cy, cw, ch = crop
    k = ancho_lienzo / cw
    alto = round(ch * k)
    ruta_png = CAPTURAS / png
    iw, ih = Image.open(ruta_png).size
    b64 = base64.b64encode(ruta_png.read_bytes()).decode("ascii")
    s = S(nombre, titulo, desc, w=ancho_lienzo, h=alto)
    s.o.append(
        f'<clipPath id="rec"><rect x="0" y="0" width="{ancho_lienzo}" height="{alto}"/></clipPath>'
        f'<image clip-path="url(#rec)" x="{-cx * k:.2f}" y="{-cy * k:.2f}" width="{iw * k:.2f}" '
        f'height="{ih * k:.2f}" href="data:image/png;base64,{b64}"/>'
    )

    def m(x, y):
        return round((x - cx) * k, 1), round((y - cy) * k, 1)

    anotar(s, m, k)
    s.guardar(CAPTURAS.parent / "diagramas" / f"{nombre}.svg")


def _marco(s, m, k, x, y, w, h):
    x1, y1 = m(x, y)
    s.rect(x1, y1, round(w * k, 1), round(h * k, 1), fill="none", line=AMARILLO, lw=4, r=4)


def _rotulo(s, cx, cy, t, anchor="middle"):
    """Rótulo amarillo de 22 px con texto negro, centrado verticalmente en cy."""
    w = ancho(t, 22, True) + 20
    x = cx - w / 2 if anchor == "middle" else (cx if anchor == "start" else cx - w)
    s.rect(round(x, 1), round(cy - 21, 1), round(w, 1), 42, fill=AMARILLO, line=None, r=5)
    s.text(round(x + w / 2, 1), round(cy + 8, 1), t, bold=True, anchor="middle", col=INK)


def dc6_7(ruta):
    def anotar(s, m, k):
        _marco(s, m, k, 1779, 321, 48, 32)  # interruptor de hola_airflow
        _marco(s, m, k, 1832, 320, 34, 34)  # ▶ Trigger
        ax, ay = m(1540, 416)
        _rotulo(s, ax, ay, "Interruptor")
        s.flecha(round(ax + 40, 1), round(ay - 22, 1), *m(1782, 356), col="y", lw=3)
        bx, by = m(1790, 416)
        _rotulo(s, bx, by, "▶ Trigger")
        s.flecha(round(bx + 20, 1), round(by - 22, 1), *m(1850, 358), col="y", lw=3)

    _captura(
        "Dc6-7",
        "Lista de DAGs de Airflow con el interruptor y el botón ▶ Trigger",
        "Captura real de la lista de DAGs: hola_airflow, ingesta_mensual y pipeline_taxi. En la fila de hola_airflow, un recuadro amarillo marca el interruptor que activa o pausa el DAG "
        "y otro marca el botón ▶ Trigger que lo lanza.",
        "airflow_lista_dags.png",
        (90, 200, 1910, 690),
        1120,
        anotar,
    )


def dc6_8(ruta):
    def anotar(s, m, k):
        _marco(s, m, k, 482, 322, 40, 84)  # tres tareas en verde
        ax, ay = m(250, 255)
        _rotulo(s, ax, ay, "Tres tareas en verde")
        s.flecha(round(ax + 110, 1), round(ay + 16, 1), *m(478, 340), col="y", lw=3)
        _marco(s, m, k, 680, 533, 90, 36)  # total 37 s
        tx, ty = m(1250, 620)
        _rotulo(s, tx, ty, "Corrida completa: 37 s")
        s.flecha(round(tx - 125, 1), ty, *m(776, 568), col="y", lw=3)

    _captura(
        "Dc6-8",
        "Cuadrícula de hola_airflow con las tres tareas en verde y 37 s en total",
        "Captura real de la página de hola_airflow. A la izquierda, la cuadrícula con saludar, esperar y reintentar en verde, marcadas con un recuadro amarillo. "
        "A la derecha, la gráfica de la última corrida, con un total de 37 segundos, también marcado.",
        "airflow_hola_cuadricula.png",
        (0, 0, 2000, 780),
        1120,
        anotar,
    )


def dc6_9(ruta):
    def anotar(s, m, k):
        _marco(s, m, k, 576, 370, 98, 52)  # intento 1 (rojo)
        _marco(s, m, k, 676, 370, 98, 52)  # intento 2 (verde)
        _marco(s, m, k, 570, 272, 76, 46)  # pestaña Logs
        tx, ty = m(1250, 396)
        _rotulo(s, tx, ty, "Task Tries: el 1 falló, el 2 pasó")
        s.flecha(round(tx - 160, 1), ty, *m(782, 396), col="y", lw=3)
        lx, ly = m(1000, 246)
        _rotulo(s, lx, ly, "Logs: aquí se lee el error")
        s.flecha(round(lx - 120, 1), round(ly + 18, 1), *m(650, 280), col="y", lw=3)

    _captura(
        "Dc6-9",
        "Tarea reintentar de hola_airflow: la pestaña Logs y los intentos de Task Tries",
        "Captura real de la tarea reintentar. Debajo de la pestaña Logs, Task Tries muestra el intento 1 con una cruz roja y el intento 2 con una marca verde; "
        "el registro del intento 1 trae el error FALLO INTENCIONAL. Recuadros amarillos marcan la pestaña Logs y los dos intentos.",
        "airflow_reintentar_intentos.png",
        (0, 0, 2000, 880),
        1000,
        anotar,
    )


def _anota_ejecucion(duracion_x, duracion_w, duracion_txt, col_x, col_txt, desv=0):
    def anotar(s, m, k):
        _marco(s, m, k, duracion_x, 122 + desv, duracion_w, 58)  # Duration
        _marco(s, m, k, 1048, 458 + desv, 116, 292)  # columna State
        _marco(s, m, k, col_x, 256, 24, 146)  # primera columna de la cuadrícula
        dx, dy = m(1560, 262)
        _rotulo(s, dx, dy, duracion_txt)
        s.flecha(round(dx + 40, 1), round(dy - 22, 1), *m(1590, 186), col="y", lw=3)
        sx, sy = m(1100, 830)
        _rotulo(s, sx, sy, "State: cinco en Success")
        s.flecha(sx, round(sy - 22, 1), *m(1105, 756), col="y", lw=3)
        cx, cy = m(250, 215)
        _rotulo(s, cx, cy, col_txt)
        s.flecha(round(cx + 60, 1), round(cy + 22, 1), *m(col_x - 4, 262), col="y", lw=3)

    return anotar


def dc6_10(ruta):
    _captura(
        "Dc6-10",
        "Ejecución 2 de ingesta_mensual desde la interfaz: 16 segundos y cinco tareas en Success",
        "Captura real de la ejecución 2 de ingesta_mensual lanzada desde la interfaz. Recuadros amarillos marcan la duración, 16 segundos, la columna State con las cinco tareas en Success "
        "y la primera columna roja de la cuadrícula, que es la corrida automática fallida.",
        "airflow_ejecucion2.png",
        (0, 0, 2000, 880),
        1000,
        _anota_ejecucion(1508, 168, "Duración: 16 s", 498, "Corrida automática", desv=-9),
    )


def dc6_11(ruta):
    _captura(
        "Dc6-11",
        "Ejecución 3 de ingesta_mensual con reprocesar: 2 minutos 4 segundos y cinco tareas en Success",
        "Captura real de la ejecución 3 de ingesta_mensual, con reprocesar. Recuadros amarillos marcan la duración, 2 minutos 4 segundos, la columna State con las cinco tareas en Success "
        "y la primera columna roja de la cuadrícula, que es la corrida automática fallida.",
        "airflow_ejecucion3.png",
        (0, 0, 2000, 880),
        1000,
        _anota_ejecucion(1530, 100, "Duración: 2 min 4 s", 478, "Corrida automática"),
    )


# --------------------------------------------------------------------------- Dc6-12
def dc6_12(ruta):
    s = S(
        "Dc6-12",
        "Qué datos leemos hoy y dónde se guardan",
        "Tres carriles de izquierda a derecha, con un rótulo común a la izquierda: los mismos archivos de la TLC y Open-Meteo. "
        "Clase 4: make muestra, un job de Glue, descargó el año a S3 bronze, 239 470 448 viajes, y hoy lo lee Athena. "
        "Hoy: tus funciones y el DAG en el Code Editor escriben en el disco del Code Editor, bronze_alumno con 1 000 viajes, silver con 1 000 filas y gold con 281; "
        "una flecha punteada va a la tabla de control de Snowflake, y un rótulo dice que nada de eso llega a S3. "
        "Clase 7, en línea punteada: tus funciones en Glue escriben bronze, silver y gold del mes completo en S3, y Athena lee tu bronze y lo concilia con la tabla de control.",
    )
    s.rect(6, 7, 150, 426, fill=PANEL, line=GRIS)
    s.text(81, 160, "Las fuentes:", bold=True, anchor="middle", maxw=140)
    s.lineas(
        81,
        200,
        ["los mismos", "archivos de", "la TLC y", "Open-Meteo"],
        anchor="middle",
        maxw=140,
    )
    carriles = (
        # (y, alto, título, discontinuo)
        (7, 112, "Clase 4 · ya hecho", None),
        (125, 190, "Hoy · clases 5 y 6", None),
        (321, 112, "Clase 7 · la próxima", "9 6"),
    )
    for (y, h, tit, dash), colt in zip(carriles, (INK, INK, GRIS), strict=True):
        s.rect(
            164,
            y,
            950,
            h,
            fill=BLANCO,
            line=(INK if y == 125 else GRIS),
            lw=(2.5 if y == 125 else 1.5),
            dash=dash,
        )
        s.text(180, y + 31, tit, bold=True, col=colt, maxw=420)
        s.flecha(158, y + 74, 188, y + 74, col="g", lw=3)
    X = (190, 460, 800)
    Wd = (230, 300, 300)
    # Carril a: clase 4
    ya = 7 + 42
    cajas_a = (
        (["make muestra", "(job de Glue)"], PANEL, GRIS, INK),
        (["S3: bronze del año", "239 470 448 viajes"], BRONZE, BRONZE, BLANCO),
        (["Athena", "hoy lee este bronze"], PANEL, GRIS, INK),
    )
    for x, w, (ts, f, borde, c) in zip(X, Wd, cajas_a, strict=True):
        s.caja(x, ya, w, 62, ts, fill=f, line=borde, col=c)
    for x1, x2 in ((420, 458), (760, 798)):
        s.flecha(x1, ya + 31, x2, ya + 31, col="g", lw=3)
    # Carril b: hoy
    yb = 125 + 40
    s.caja(190, yb, 230, 68, ["Tus funciones y DAG", "(Code Editor)"], fill=PANEL, line=INK, lw=2)
    s.flecha(420, yb + 34, 438, yb + 34, col="g", lw=3)
    discos = (
        (440, "bronze_alumno", "viajes: 1 000", BRONZE),
        (675, "silver_alumno", "1 000 filas", SILVER),
        (910, "gold_alumno", "281 filas", GOLD),
    )
    for x, n, f, c in discos:
        s.caja(x, yb, 190, 68, [n, f], fill=c, line=c, col=BLANCO, mono=True)
    for x1, x2 in ((630, 673), (865, 908)):
        s.flecha(x1, yb + 34, x2, yb + 34, col="g", lw=3)
    s.linea(440, yb + 80, 1100, yb + 80, col=ROJO, lw=3)
    s.text(
        770,
        yb + 118,
        "Disco del Code Editor: no llega a S3",
        bold=True,
        col=ROJO,
        anchor="middle",
        maxw=640,
    )
    s.caja(
        190,
        yb + 96,
        230,
        46,
        ["Control en Snowflake"],
        fill=T_ACENTO,
        line=ACENTO,
        lw=2.5,
        col=ACENTO,
    )
    s.flecha(240, yb + 70, 240, yb + 94, col="a", dash="7 6", doble=True, lw=2.5)
    s.text(256, yb + 87, "consulta y registra", col=ACENTO, maxw=200)
    # Carril c: clase 7
    yc = 321 + 42
    cajas_c = (
        (["Tus funciones", "corren en Glue"], BLANCO, GRIS, GRIS),
        (["S3: bronze, silver, gold", "del mes completo"], BLANCO, GRIS, GRIS),
        (["Athena lee tu bronze", "y concilia con el control"], BLANCO, GRIS, GRIS),
    )
    for x, w, (ts, f, borde, c) in zip(X, Wd, cajas_c, strict=True):
        s.caja(x, yc, w, 62, ts, fill=f, line=borde, col=c, dash="9 6", subcol=GRIS)
    for x1, x2 in ((420, 458), (760, 798)):
        s.flecha(x1, yc + 31, x2, yc + 31, col="g", lw=3, dash="9 6")
    s.guardar(ruta)


if __name__ == "__main__":
    base = Path(__file__).parent
    dc6_0(base / "Dc6-0.svg")
    dc6_1(base / "Dc6-1.svg")
    dc6_2(base / "Dc6-2.svg")
    dc6_3(base / "Dc6-3.svg")
    dc6_4(base / "Dc6-4.svg")
    dc6_5(base / "Dc6-5.svg")
    dc6_6(base / "Dc6-6.svg")
    dc6_7(base / "Dc6-7.svg")
    dc6_8(base / "Dc6-8.svg")
    dc6_9(base / "Dc6-9.svg")
    dc6_10(base / "Dc6-10.svg")
    dc6_11(base / "Dc6-11.svg")
    dc6_12(base / "Dc6-12.svg")
