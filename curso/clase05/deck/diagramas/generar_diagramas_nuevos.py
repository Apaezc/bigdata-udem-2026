"""Genera los diagramas nuevos de la clase 5 (Dc5-4, Dc5-5, Dc5-8 a Dc5-12)."""

import sys
from pathlib import Path
from xml.sax.saxutils import escape

INK, GRIS, PANEL, ACENTO, BRONZE, REGLA, BLANCO = (
    "#15171C",
    "#5F6672",
    "#F0EEE7",
    "#2340D8",
    "#B4622F",
    "#D9D6CC",
    "#FFFFFF",
)
TINTE = "#E3E6F6"
FONT = "Helvetica Neue, Arial, sans-serif"
MONO = "SF Mono, Menlo, Consolas, monospace"


class S:
    def __init__(s, w, h, titulo, desc):
        s.w, s.h = w, h
        s.o = [
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" font-family="{FONT}">',
            f"<title>{escape(titulo)}</title><desc>{escape(desc)}</desc>",
            "<defs>"
            + "".join(
                f'<marker id="m_{n}" markerUnits="userSpaceOnUse" markerWidth="12" markerHeight="12" refX="12" refY="6" orient="auto"><path d="M0,0 L12,6 L0,12 Z" fill="{c}"/></marker>'
                for n, c in (("a", ACENTO), ("g", GRIS), ("b", BRONZE))
            )
            + "</defs>",
        ]

    def rect(s, x, y, w, h, fill=PANEL, line=None, lw=1.5, r=6, dash=None):
        st = f' stroke="{line}" stroke-width="{lw}"' if line else ' stroke="none"'
        d = f' stroke-dasharray="{dash}"' if dash else ""
        s.o.append(
            f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}"{st}{d}/>'
        )

    def text(s, x, y, t, size=20, col=INK, bold=False, anchor="start", mono=False):
        f = f' font-family="{MONO}"' if mono else ""
        b = ' font-weight="700"' if bold else ""
        s.o.append(
            f'<text x="{x}" y="{y}" font-size="{size}" fill="{col}" text-anchor="{anchor}"{b}{f}>{escape(t)}</text>'
        )

    def rich(s, x, y, partes, size=20, mono=True, anchor="start"):
        """partes: [(texto, color, negrita)]"""
        f = f' font-family="{MONO}"' if mono else ""
        negrita = ' font-weight="700"'
        spans = "".join(
            f'<tspan fill="{c}"{negrita if b else ""}>{escape(t)}</tspan>' for t, c, b in partes
        )
        s.o.append(
            f'<text x="{x}" y="{y}" font-size="{size}" text-anchor="{anchor}"{f} xml:space="preserve">{spans}</text>'
        )

    def flecha(s, x1, y1, x2, y2, col="g", lw=2):
        c = {"a": ACENTO, "g": GRIS, "b": BRONZE}[col]
        s.o.append(
            f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{c}" stroke-width="{lw}" marker-end="url(#m_{col})"/>'
        )

    def circulo(s, x, y, n, col=ACENTO):
        s.o.append(f'<circle cx="{x}" cy="{y}" r="15" fill="{col}"/>')
        s.text(x, y + 6, str(n), size=17, col=BLANCO, bold=True, anchor="middle")

    def guardar(s, ruta):
        Path(ruta).write_text("\n".join(s.o + ["</svg>"]) + "\n", encoding="utf-8")


def dc5_8(ruta):
    """GROUP BY en dos fases."""
    s = S(
        1200,
        480,
        "GROUP BY en dos fases",
        "Cuatro particiones cuentan sus viajes por zona; solo los resúmenes viajan por el shuffle y se suman al final.",
    )
    s.circulo(55, 30, 1)
    s.text(80, 37, "Cada partición cuenta sus viajes", size=22, bold=True)
    s.circulo(505, 30, 2)
    s.text(530, 37, "Viajan los resúmenes", size=22, bold=True)
    s.circulo(855, 30, 3)
    s.text(880, 37, "Se suman por zona", size=22, bold=True)
    for i in range(4):
        y = 64 + i * 84
        s.rect(40, y, 190, 68, line=GRIS)
        s.text(135, y + 30, f"partición {i + 1}", size=19, bold=True, anchor="middle")
        s.text(135, y + 55, "≈ 4.9 M viajes", size=18, col=GRIS, anchor="middle")
        s.flecha(232, y + 34, 272, y + 34)
        s.rect(276, y + 4, 190, 60, fill=BLANCO, line=ACENTO)
        s.text(371, y + 30, "≤ 262 filas", size=19, bold=True, col=ACENTO, anchor="middle")
        s.text(371, y + 53, "una por zona", size=17, col=GRIS, anchor="middle")
        s.flecha(468, y + 34, 556, 210, col="a")
    s.rect(560, 150, 250, 120, fill=TINTE, line=ACENTO, lw=2.5, dash="8 6")
    s.text(685, 188, "shuffle", size=20, col=GRIS, anchor="middle")
    s.text(685, 222, "1 041 filas", size=26, bold=True, col=ACENTO, anchor="middle")
    s.text(685, 252, "no 19 663 930", size=19, anchor="middle")
    s.flecha(812, 210, 850, 210, col="a")
    s.rect(854, 80, 306, 260, fill=BLANCO, line=GRIS)
    s.text(872, 114, "Ejemplo: zona 132 (JFK)", size=19, bold=True)
    filas = [
        ("partición 1", "120"),
        ("partición 2", "95"),
        ("partición 3", "110"),
        ("partición 4", "101"),
    ]
    for j, (a, b) in enumerate(filas):
        s.text(872, 150 + j * 32, a, size=19, col=GRIS)
        s.text(1140, 150 + j * 32, b, size=19, anchor="end", mono=True)
    s.o.append(f'<line x1="872" y1="278" x2="1140" y2="278" stroke="{INK}" stroke-width="1.5"/>')
    s.text(872, 308, "total de la zona", size=19, bold=True)
    s.text(1140, 308, "426", size=19, bold=True, anchor="end", mono=True)
    s.text(872, 334, "cifras de ejemplo", size=16, col=GRIS)
    s.rect(40, 404, 1120, 66, fill=PANEL)
    s.text(
        60,
        445,
        "Como en unas elecciones: cada mesa cuenta sus votos y solo viaja el acta, no las papeletas.",
        size=21,
    )
    s.guardar(ruta)


def dc5_4(ruta):
    """Join normal frente a broadcast, con dos ejecutores."""
    s = S(
        1200,
        480,
        "Join normal frente a broadcast",
        "Izquierda: los viajes de cada ejecutor cruzan al otro para encontrarse con su zona. Derecha: la tabla de zonas se copia a cada ejecutor y los viajes no se mueven.",
    )
    # izquierda
    s.text(40, 34, "Join normal: se mueven los viajes", size=22, bold=True)
    s.text(560, 34, "8.27 s", size=22, bold=True, col=BRONZE, anchor="end")
    for i, x in enumerate((40, 320)):
        x = 40 if i == 0 else 320
        s.rect(x, 60, 240 if i == 1 else 240, 160, fill=BLANCO, line=GRIS)
        s.text(x + 120, 88, f"ejecutor {'AB'[i]}", size=19, bold=True, anchor="middle")
        s.rect(x + 16, 102, 208, 44, line=GRIS)
        s.text(x + 120, 131, "viajes de todas las zonas", size=17, anchor="middle")
        s.rect(x + 16, 156, 208, 44, line=GRIS)
        s.text(x + 120, 185, "parte de las zonas", size=17, anchor="middle")
    s.flecha(282, 112, 318, 112, col="b", lw=4)
    s.flecha(318, 132, 282, 132, col="b", lw=4)
    s.text(300, 98, "shuffle", size=15, col=BRONZE, bold=True, anchor="middle")
    s.rect(40, 240, 520, 92, fill="#F6E9E0")
    s.text(56, 272, "Cada viaje viaja al ejecutor que tiene su zona:", size=19)
    s.text(56, 300, "se reparten por la red millones de filas", size=19)
    s.text(56, 322, "para encontrar el nombre de 265 zonas.", size=19)
    # derecha
    s.text(640, 34, "Broadcast: se copia la tabla pequeña", size=22, bold=True)
    s.text(1160, 34, "2.96 s", size=22, bold=True, col=ACENTO, anchor="end")
    s.rect(820, 52, 160, 44, fill=TINTE, line=ACENTO, lw=2)
    s.text(900, 81, "zonas · 265 filas", size=17, bold=True, col=ACENTO, anchor="middle")
    for i, x in enumerate((640, 920)):
        s.flecha(900, 98, x + 120, 128, col="a", lw=2.5)
        s.rect(x, 130, 240, 160, fill=BLANCO, line=GRIS)
        s.text(x + 120, 158, f"ejecutor {'AB'[i]}", size=19, bold=True, anchor="middle")
        s.rect(x + 16, 172, 208, 44, line=GRIS)
        s.text(x + 120, 201, "sus viajes, quietos", size=17, anchor="middle")
        s.rect(x + 16, 226, 208, 44, fill=TINTE, line=ACENTO)
        s.text(x + 120, 255, "copia de las zonas", size=17, col=ACENTO, anchor="middle")
    s.text(900, 322, "cada ejecutor une localmente", size=19, col=GRIS, anchor="middle")
    s.rect(40, 360, 1120, 110, fill=PANEL)
    s.text(
        60,
        396,
        "Como fotocopiar el directorio de zonas para cada oficina, en vez de mandar",
        size=21,
    )
    s.text(60, 424, "a cada viajero a la oficina que tiene su zona.", size=21)
    s.text(
        60,
        454,
        "Spark lo hace solo si la tabla pequeña mide menos de 10 MB; debe caber en cada ejecutor.",
        size=18,
        col=GRIS,
    )
    s.guardar(ruta)


def dc5_9(ruta):
    """Ventanas: qué hacen y cómo se ejecutan."""
    s = S(
        1200,
        480,
        "Función de ventana con y sin PARTITION BY",
        "A la izquierda, viajes numerados por hora dentro de cada zona. A la derecha, sin PARTITION BY todas las particiones van a una sola tarea; con PARTITION BY se reparten por zona.",
    )
    s.text(40, 32, "Qué hace: numera dentro de cada grupo", size=22, bold=True)
    s.rich(
        40,
        64,
        [
            ("ROW_NUMBER() OVER (", INK, False),
            ("PARTITION BY zona", ACENTO, True),
            (" ORDER BY hora)", INK, False),
        ],
        size=15,
    )
    cab = ("zona", "hora", "n")
    xs = (60, 200, 340)
    s.rect(40, 80, 420, 36, fill=PANEL)
    for x, c in zip(xs, cab, strict=True):
        s.text(x, 105, c, size=19, bold=True)
    filas = [
        ("132", "08:00", "1"),
        ("132", "08:05", "2"),
        ("132", "09:10", "3"),
        ("161", "07:30", "1"),
        ("161", "08:20", "2"),
    ]
    for j, f in enumerate(filas):
        y = 146 + j * 34
        if j == 3:
            s.o.append(
                f'<line x1="40" y1="{y - 24}" x2="460" y2="{y - 24}" stroke="{GRIS}" stroke-width="1.5" stroke-dasharray="5 4"/>'
            )
        for k, (x, v) in enumerate(zip(xs, f, strict=True)):
            s.text(x, y, v, size=19, mono=True, bold=(k == 2), col=ACENTO if k == 2 else INK)
    s.text(40, 334, "La cuenta vuelve a 1 en cada zona.", size=19, col=GRIS)
    s.text(40, 360, "Sirve para «el primer viaje de cada zona».", size=19, col=GRIS)
    # derecha
    s.text(540, 32, "Cómo lo ejecuta Spark (5 % de enero)", size=22, bold=True)
    s.text(540, 72, "Sin PARTITION BY", size=19, bold=True, col=BRONZE)
    for i in range(4):
        x = 540 + i * 70
        s.rect(x, 86, 56, 40, line=GRIS)
        s.text(x + 28, 112, f"p{i + 1}", size=16, anchor="middle")
        s.o.append(
            f'<line x1="{x + 28}" y1="128" x2="{x + 28}" y2="146" stroke="{BRONZE}" stroke-width="2"/>'
        )
    s.o.append(f'<line x1="568" y1="146" x2="778" y2="146" stroke="{BRONZE}" stroke-width="2"/>')
    s.flecha(778, 146, 856, 146, col="b")
    s.rect(860, 116, 300, 62, fill="#F6E9E0", line=BRONZE, lw=2)
    s.text(1010, 142, "1 tarea", size=19, bold=True, col=BRONZE, anchor="middle")
    s.text(1010, 167, "983 931 filas juntas", size=17, anchor="middle")
    s.text(540, 222, "Con PARTITION BY zona", size=19, bold=True, col=ACENTO)
    for i in range(4):
        x = 540 + i * 70
        s.rect(x, 236, 56, 40, line=GRIS)
        s.text(x + 28, 262, f"p{i + 1}", size=16, anchor="middle")
    s.flecha(830, 256, 856, 256, col="a")
    for i in range(4):
        x = 860 + i * 76
        s.rect(x, 236, 64, 40, fill=TINTE, line=ACENTO)
        s.text(x + 32, 262, "tarea", size=15, anchor="middle")
    s.text(860, 302, "una por grupo de zonas;", size=17, col=GRIS)
    s.text(860, 324, "la mayor zona: 18 784 filas", size=17, col=GRIS)
    s.rect(40, 392, 1120, 78, fill=PANEL)
    s.text(
        60,
        424,
        "Con todo el año, una sola tarea tendría que sostener todas las filas en un solo ejecutor.",
        size=20,
    )
    s.text(60, 452, "Regla: a una ventana siempre se le da un PARTITION BY.", size=20, bold=True)
    s.guardar(ruta)


def dc5_5(ruta):
    """Medallion y los tres pasos de una ingesta en bronze."""
    s = S(
        1200,
        470,
        "Medallion y los tres pasos de una ingesta",
        "Las tres capas; debajo, lo que escribe una ingesta en bronze en tres pasos: crudo, Parquet con metadatos y marcador de lote completo.",
    )
    capas = [
        (40, "bronze", "guarda cada fuente tal como llega", BRONZE),
        (430, "silver", "limpia, tipa y une zonas y clima", "#6E7F94"),
        (820, "gold", "resume por día, zona y empresa", "#B07F0E"),
    ]
    for x, n, d, c in capas:
        s.rect(x, 10, 340, 66, fill=c, r=4)
        s.text(x + 16, 38, n, size=21, col=BLANCO, bold=True)
        s.text(x + 16, 64, d, size=18, col=BLANCO)
    s.flecha(382, 43, 426, 43)
    s.flecha(772, 43, 816, 43)
    s.text(
        40,
        116,
        "Una ingesta de clima de enero escribe en bronze, en este orden:",
        size=21,
        bold=True,
    )
    pasos = [
        (
            "Guarda el archivo tal como llegó (el crudo)",
            "bronze/_crudo/clima/mes=2024-01/lote=20261117T143005Z_a3f9c1/open_meteo_2024-01.json",
            "Sirve para reprocesar sin volver a pedirlo a la fuente.",
        ),
        (
            "Escribe el Parquet con las 5 columnas de metadatos",
            "bronze/clima/mes=2024-01/lote=20261117T143005Z_a3f9c1/part-….parquet",
            "Es lo que leen Spark, Athena y silver.",
        ),
        (
            "Al final, escribe un archivo vacío: _LOTE_COMPLETO",
            "bronze/clima/mes=2024-01/lote=20261117T143005Z_a3f9c1/_LOTE_COMPLETO",
            "Si falta, la ingesta se cortó y silver ignora ese lote.",
        ),
    ]
    for i, (t, r, p) in enumerate(pasos):
        y = 140 + i * 96
        s.rect(40, y, 1120, 84, fill=PANEL)
        s.circulo(68, y + 28, i + 1)
        s.text(96, y + 35, t, size=20, bold=True)
        s.text(690, y + 35, p, size=17, col=GRIS)
        s.text(96, y + 66, r, size=16, mono=True, col=BRONZE)
    s.text(
        40,
        458,
        "Otra ingesta del mismo mes crea lote=20261118T091210Z_07be44 al lado; no borra el anterior.",
        size=19,
        col=GRIS,
    )
    s.guardar(ruta)


def dc5_10(ruta):
    """Las tres fuentes y sus URL."""
    s = S(
        1200,
        470,
        "Cómo se pide cada fuente",
        "Tres tarjetas: viajes con un archivo por mes, zonas con un archivo único y clima con una consulta por rango de fechas; en cada URL se resalta lo que cambia con el mes.",
    )
    filas = [
        (
            "Viajes",
            "Parquet · un archivo por mes",
            "el mes va en el nombre del archivo",
            [
                [
                    ("https://d37ci6vzurychx.cloudfront.net/trip-data/fhvhv_tripdata_", INK, False),
                    ("2024-02", ACENTO, True),
                    (".parquet", INK, False),
                ]
            ],
            "450.9 MiB por mes",
        ),
        (
            "Zonas",
            "CSV · un solo archivo",
            "no tiene mes: siempre la misma URL",
            [[("https://d37ci6vzurychx.cloudfront.net/misc/taxi_zone_lookup.csv", INK, False)]],
            "265 filas",
        ),
        (
            "Clima",
            "JSON · una consulta a una API",
            "la URL lleva el primer y el último día del mes",
            [
                [
                    (
                        "https://archive-api.open-meteo.com/v1/archive?latitude=40.71&longitude=-74.01",
                        INK,
                        False,
                    )
                ],
                [
                    ("&start_date=", INK, False),
                    ("2024-02-01", ACENTO, True),
                    ("&end_date=", INK, False),
                    ("2024-02-29", ACENTO, True),
                    ("&daily=precipitation_sum,…", INK, False),
                ],
            ],
            "febrero de 2024 tiene 29 días",
        ),
    ]
    y = 0
    for nombre, formato, regla, urls, dato in filas:
        alto = 96 + 28 * (len(urls) - 1)
        s.rect(40, y, 1120, alto, fill=PANEL)
        s.rect(40, y, 8, alto, fill=ACENTO, r=0)
        s.text(70, y + 34, nombre, size=23, bold=True)
        s.text(190, y + 34, formato, size=19, col=GRIS)
        s.text(1140, y + 34, dato, size=18, col=GRIS, anchor="end")
        for k, partes in enumerate(urls):
            s.rich(70, y + 68 + 28 * k, partes, size=16)
        s.text(1140, y + alto - 12, regla, size=16, col=ACENTO, anchor="end") if False else None
        y += alto + 18
    s.rect(40, y + 2, 1120, 56, fill=BLANCO, line=REGLA)
    s.text(
        60,
        y + 36,
        "En azul, lo que cambia con el parámetro mes. Zonas no lo usa: por eso su carpeta no lleva mes=.",
        size=19,
    )
    s.guardar(ruta)


def dc5_11(ruta):
    """Algoritmo del hash y la deduplicación."""
    s = S(
        1200,
        480,
        "Cómo se calcula el hash de una fila y cómo se deduplica",
        "Cuatro pasos para calcular la huella de una fila de clima, y un quinto que deja una sola fila por huella.",
    )
    s.text(40, 28, "Calcular la huella de una fila (al ingestar)", size=21, bold=True)
    pasos = [
        (
            "Toma solo las columnas originales",
            [("fecha=2024-01-01  lluvia_mm=0.0  temp=", INK, False), ("null", BRONZE, True)],
        ),
        (
            "Pasa cada valor a texto; el nulo se vuelve <nulo>",
            [('"2024-01-01"  "0.0"  ', INK, False), ('"<nulo>"', BRONZE, True)],
        ),
        ("Une los textos con el separador ||", [('"2024-01-01||0.0||<nulo>"', INK, False)]),
        ("Aplica SHA-256: 64 caracteres", [("1baf1e0ef58639edffd09ba9236bdd36…", ACENTO, True)]),
    ]
    for i, (t, partes) in enumerate(pasos):
        y = 48 + i * 58
        s.rect(40, y, 680, 50, fill=PANEL)
        s.circulo(66, y + 25, i + 1)
        s.text(92, y + 22, t, size=17, bold=True)
        s.rich(92, y + 43, partes, size=16)
    s.text(
        40,
        300,
        "Por qué <nulo> y ||: sin ellos, un nulo y un texto vacío darían igual,",
        size=17,
        col=GRIS,
    )
    s.text(40, 322, "y «1»+«23» se confundiría con «12»+«3».", size=17, col=GRIS)
    # deduplicar
    s.text(760, 28, "Deduplicar (silver, clase 6)", size=21, bold=True)
    s.circulo(774, 66, 5)
    s.text(798, 72, "Una fila por cada huella", size=18, bold=True)
    s.rect(760, 96, 400, 34, fill=PANEL)
    for x, c in ((774, "fecha"), (920, "_hash_fila"), (1060, "_id_lote")):
        s.text(x, 119, c, size=16, bold=True)
    datos = [
        ("2024-01-01", "1baf…", "lote 1", False),
        ("2024-01-01", "1baf…", "lote 2", True),
        ("2024-01-02", "a2b6…", "lote 1", False),
    ]
    for j, (a, b, c, tachada) in enumerate(datos):
        y = 158 + j * 32
        col = GRIS if tachada else INK
        s.text(774, y, a, size=16, mono=True, col=col)
        s.text(920, y, b, size=16, mono=True, col=BRONZE if j < 2 else col)
        s.text(1060, y, c, size=16, mono=True, col=col)
        if tachada:
            s.o.append(
                f'<line x1="770" y1="{y - 6}" x2="1150" y2="{y - 6}" stroke="{BRONZE}" stroke-width="2"/>'
            )
    s.text(760, 272, "3 filas → 2: misma huella, mismo dato.", size=17)
    s.rich(760, 304, [('dropDuplicates(["_hash_fila"])', ACENTO, True)], size=17)
    s.rect(40, 356, 1120, 114, fill=BLANCO, line=REGLA)
    s.text(
        60,
        388,
        "Cambia un solo valor y cambia toda la huella: comparar filas es comparar un texto.",
        size=19,
    )
    s.text(60, 416, "Para reunir las filas con la misma huella, Spark hace un shuffle.", size=19)
    s.text(
        60,
        444,
        "La huella detecta filas idénticas, no parecidas: eso lo limpia silver.",
        size=19,
        col=GRIS,
    )
    s.guardar(ruta)


def dc5_12(ruta):
    """Los dos métodos de la tabla de control en tres momentos."""
    s = S(
        1200,
        480,
        "Consultar y registrar en la tabla de control",
        "Tres momentos: consultar un mes que no existe devuelve una lista vacía; registrar enero agrega una fila; reprocesar enero agrega otra fila sin borrar la primera.",
    )
    momentos = [
        (
            "Consultar un mes que nunca llegó",
            'consultar_watermark("demo",',
            '  "bronze", "2099-12")',
            "'[]'",
            [],
        ),
        (
            "Registrar enero (reprocesar=False)",
            'registrar_watermark(url, "bronze",',
            '  "demo", "2024-01", 31, inicio, False)',
            "1 registro",
            [("2024-01", "31", "False")],
        ),
        (
            "Reprocesar enero (reprocesar=True)",
            'registrar_watermark(url, "bronze",',
            '  "demo", "2024-01", 31, inicio, True)',
            "2 registros",
            [("2024-01", "31", "False"), ("2024-01", "31", "True")],
        ),
    ]
    for i, (t, l1, l2, resp, filas) in enumerate(momentos):
        x = 40 + i * 380
        s.circulo(x + 15, 22, i + 1)
        s.text(x + 40, 29, t, size=18, bold=True)
        s.rect(x, 50, 360, 70, fill=PANEL)
        s.text(x + 12, 78, l1, size=14, mono=True)
        s.text(x + 12, 102, l2, size=14, mono=True)
        s.text(x + 180, 152, "tabla CONTROL.WATERMARK", size=15, col=GRIS, anchor="middle")
        s.rect(x, 162, 360, 32, fill=TINTE)
        for cx, c in ((x + 14, "mes"), (x + 140, "filas"), (x + 250, "reprocesar")):
            s.text(cx, 184, c, size=15, bold=True)
        if not filas:
            s.text(x + 180, 222, "(vacía)", size=16, col=GRIS, anchor="middle")
        for j, (a, b, c) in enumerate(filas):
            y = 222 + j * 30
            nueva = j == len(filas) - 1
            col = ACENTO if nueva else INK
            for cx, v in ((x + 14, a), (x + 140, b), (x + 250, c)):
                s.text(cx, y, v, size=16, mono=True, col=col, bold=nueva)
        s.rect(x, 268, 360, 40, fill=BLANCO, line=REGLA)
        s.text(x + 14, 294, "consultar devuelve:", size=16, col=GRIS)
        s.text(x + 346, 294, resp, size=16, mono=True, bold=True, anchor="end")
        if i < 2:
            s.flecha(x + 362, 30, x + 378, 30)
    s.rect(40, 330, 1120, 140, fill=PANEL)
    s.text(60, 362, "Lo que decide tu ingesta con esa respuesta:", size=19, bold=True)
    s.text(60, 394, "• lista vacía → descarga, escribe un lote nuevo y registra", size=19)
    s.text(60, 424, "• hay registro y reprocesar=False → no hace nada y avisa por qué", size=19)
    s.text(
        60,
        454,
        "• hay registro y reprocesar=True → lote nuevo y una fila más; las anteriores no se tocan",
        size=19,
    )
    s.guardar(ruta)


if __name__ == "__main__":
    d = Path(sys.argv[1])
    dc5_4(d / "Dc5-4.svg")
    dc5_5(d / "Dc5-5.svg")
    dc5_8(d / "Dc5-8.svg")
    dc5_9(d / "Dc5-9.svg")
    dc5_10(d / "Dc5-10.svg")
    dc5_11(d / "Dc5-11.svg")
    dc5_12(d / "Dc5-12.svg")
    print("ok")
