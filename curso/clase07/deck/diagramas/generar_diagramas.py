"""Genera los diagramas de la clase 7 (Dc7-0 a Dc7-6).

Uso:  cd ~/bigdata/curso/clase07/deck/diagramas && python3 generar_diagramas.py
Necesita Pillow (solo para medir el ancho del texto y avisar si algo no cabe).

Lienzo 1120x440 (1:1 en la slide). Todo el texto mide 22 px o más. El color cobre es solo de
bronze, el gris azulado de silver y el ocre de gold; el acento (azul) es solo de la tabla de
control y de las flechas de consulta y registro; el rojo, de lo que no se puede hacer.
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


MARCAS = {"a": ACENTO, "g": GRIS, "b": BRONZE, "y": AMARILLO, "r": ROJO}


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


# --------------------------------------------------------------------------- Dc7-0
def dc7_0(ruta):
    s = S(
        "Dc7-0",
        "El pipeline de la clase 7: cuatro pasos y una tabla de control que hace de puerta",
        "De izquierda a derecha, las fuentes entran a cuatro pasos: bronze (correr_bronze), silver (correr_silver), gold (correr_gold) y snowflake (cargar_snowflake). "
        "Arriba, la tabla de control del entorno; cada paso tiene una flecha de doble punta con ella: pregunta antes de trabajar y anota al terminar bien. "
        "Abajo, una nota: la misma función corre desde un notebook, con make correr y como tarea del DAG pipeline_taxi.",
    )
    s.rect(196, 6, 920, 46, fill=T_ACENTO, line=ACENTO, lw=2.5)
    s.text(
        656,
        37,
        "Tabla de control · BIGDATA.CONTROL_DEV.WATERMARK (una por entorno)",
        bold=True,
        col=ACENTO,
        anchor="middle",
        maxw=900,
    )
    s.caja(6, 140, 150, 110, ["Fuentes", "viajes", "zonas, clima"])
    pasos = (
        (196, "Bronze", "correr_bronze", "guarda tal cual", BRONZE),
        (436, "Silver", "correr_silver", "limpia y espeja", SILVER),
        (676, "Gold", "correr_gold", "resume el negocio", GOLD),
        (916, "Snowflake", "cargar_snowflake", "carga la tabla", None),
    )
    s.flecha(158, 195, 194, 195)
    for i, (x, nombre, funcion, que, color) in enumerate(pasos):
        if color:
            s.caja(x, 140, 200, 110, [nombre, funcion, que], fill=color, line=color, col=BLANCO)
        else:
            s.caja(x, 140, 200, 110, [nombre, funcion, que], fill=PANEL, line=INK, lw=2.5)
        s.flecha(x + 100, 138, x + 100, 54, col="a", doble=True)
        if i < 3:
            s.flecha(x + 202, 195, pasos[i + 1][0] - 2, 195)
    s.text(6, 24, "pregunta antes", col=ACENTO, maxw=186)
    s.text(6, 52, "y anota al final", col=ACENTO, maxw=186)
    s.text(
        560,
        300,
        "La misma función corre en un notebook, con make correr",
        anchor="middle",
        bold=True,
        maxw=1090,
    )
    s.text(
        560,
        330,
        "y como tarea del DAG pipeline_taxi (con el mismo nombre).",
        anchor="middle",
        bold=True,
        maxw=1090,
    )
    s.text(
        560,
        384,
        "Para pasar de Spark en el Code Editor a Glue cambia solo el cómputo.",
        anchor="middle",
        col=GRIS,
        maxw=1090,
    )
    s.guardar(ruta)


# --------------------------------------------------------------------------- Dc7-1
def dc7_1(ruta):
    s = S(
        "Dc7-1",
        "Dev y prod no comparten ninguna carpeta ni ningún esquema",
        "A la izquierda, el bucket del lake con dos carpetas separadas, dev y prod, cada una con bronze, silver y gold; code, dags, logs y tmp son del lake. "
        "A la derecha, Snowflake con cuatro esquemas: DEV, PROD, CONTROL_DEV y CONTROL_PROD. Abajo, el Code Editor siempre escribe en dev, dev y CONTROL_DEV; "
        "la VM de Airflow solo escribe en prod, PROD y CONTROL_PROD, y solo después de un pull request y del CI/CD. Una flecha roja marca que el Code Editor no puede escribir en prod.",
    )
    s.rect(6, 6, 670, 260, fill=PANEL, line=GRIS)
    s.text(22, 36, "Bucket del lake", bold=True, maxw=300)
    s.text(662, 36, "code/ dags/ logs/ tmp/ son del lake", col=GRIS, anchor="end", maxw=400)
    s.text(22, 66, "s3://bigdata-lake-<cuenta>-us-east-2", mono=True, col=GRIS, maxw=480)
    for x, nombre in ((22, "dev/"), (346, "prod/")):
        s.rect(x, 84, 306, 170, fill=BLANCO, line=INK, lw=2.5)
        s.text(x + 14, 112, nombre, bold=True, maxw=200)
        for j, (capa, color) in enumerate((("bronze", BRONZE), ("silver", SILVER), ("gold", GOLD))):
            s.caja(x + 16, 124 + j * 42, 274, 36, [capa], fill=color, line=color, col=BLANCO)
    s.rect(692, 6, 422, 260, fill=PANEL, line=GRIS)
    s.text(708, 36, "Snowflake · base BIGDATA", bold=True, maxw=390)
    s.caja(704, 56, 196, 90, ["DEV"], fill=BLANCO, line=INK, lw=2.5)
    s.caja(912, 56, 196, 90, ["PROD"], fill=BLANCO, line=INK, lw=2.5)
    s.caja(704, 162, 196, 90, ["CONTROL_DEV"], fill=T_ACENTO, line=ACENTO, lw=2.5, col=ACENTO)
    s.caja(912, 162, 196, 90, ["CONTROL_PROD"], fill=T_ACENTO, line=ACENTO, lw=2.5, col=ACENTO)
    s.caja(6, 330, 548, 100, ["Code Editor · siempre dev", "escribe dev/, DEV y CONTROL_DEV"])
    s.caja(
        572,
        330,
        542,
        100,
        ["VM de Airflow · solo prod", "tras PR y CI/CD: prod/, PROD, CONTROL_PROD"],
        fill=BLANCO,
        line=INK,
        lw=2.5,
    )
    s.flecha(180, 328, 180, 256, col="g", lw=3)
    s.flecha(600, 328, 600, 256, col="g", lw=3)
    s.flecha(440, 328, 440, 256, col="r", lw=3, dash="8 6")
    s.text(452, 304, "no puede", bold=True, col=ROJO, maxw=120)
    s.guardar(ruta)


# --------------------------------------------------------------------------- Dc7-2
def dc7_2(ruta):
    s = S(
        "Dc7-2",
        "Qué da la casa y qué escribe el equipo en cada paso",
        "Cuatro columnas, una por paso. En cada una, arriba la caja de la casa con las funciones ya hechas y abajo la caja del equipo con lo que escribe: "
        "agregar_metadatos en bronze, deduplicar en silver, la tabla de gold propia en gold y el CREATE TABLE propio en snowflake. "
        "Abajo, una nota: agregar_metadatos y deduplicar hoy no hacen nada a propósito; debe_ingestar y registrar_ingesta ya vienen resueltas.",
    )
    columnas = (
        (
            "Bronze",
            BRONZE,
            ["traer_crudo_*", "leer_crudo", "escribir_bronze", "la tabla de control"],
            "agregar_metadatos",
        ),
        (
            "Silver",
            SILVER,
            ["leer_capa", "escribir_capa", "limpiar_viajes", "main de silver"],
            "deduplicar",
        ),
        (
            "Gold",
            GOLD,
            ["leer_capa", "escribir_capa", "ejemplo: tarifa por", "milla por barrio"],
            "tu tabla de gold",
        ),
        (
            "Snowflake",
            None,
            ["esquema_de_tabla", "cargar_gold", "ejemplo de", "CREATE TABLE"],
            "tu CREATE TABLE",
        ),
    )
    for i, (nombre, color, casa, equipo) in enumerate(columnas):
        x = 6 + i * 280
        if color:
            s.caja(x, 6, 262, 54, [nombre], fill=color, line=color, col=BLANCO)
        else:
            s.caja(x, 6, 262, 54, [nombre], fill=PANEL, line=INK, lw=2.5)
        s.caja(x, 70, 262, 168, ["De la casa", *casa], fill=PANEL, line=GRIS)
        s.caja(x, 250, 262, 76, ["Del equipo", equipo], fill=BLANCO, line=INK, lw=3)
    s.text(
        560,
        372,
        "Problemas a propósito: agregar_metadatos y deduplicar hoy no hacen nada.",
        bold=True,
        anchor="middle",
        maxw=1100,
    )
    s.text(
        560,
        408,
        "debe_ingestar y registrar_ingesta ya vienen resueltas.",
        anchor="middle",
        col=GRIS,
        maxw=1100,
    )
    s.guardar(ruta)


# --------------------------------------------------------------------------- Dc7-3
def dc7_3(ruta):
    s = S(
        "Dc7-3",
        "La puerta de la tabla de control: tres casos y una sola regla",
        "Arriba, la tabla de control con una flecha de doble punta hacia las tres filas de abajo. Cada fila es un caso. "
        "Sin registro y reprocesar falso: se ingesta. Con registro y reprocesar falso: se salta, sin mirar filas, cómputo ni límite. "
        "Con reprocesar verdadero: se ingesta siempre. Abajo, una nota: el paso anota su fila solo al terminar bien.",
    )
    s.rect(6, 6, 1108, 46, fill=T_ACENTO, line=ACENTO, lw=2.5)
    s.text(
        560,
        37,
        "Tabla de control · clave (tabla, capa, mes) · una fila por paso terminado",
        bold=True,
        col=ACENTO,
        anchor="middle",
        maxw=1090,
    )
    s.flecha(300, 112, 300, 54, col="a", doble=True)
    s.text(316, 92, "¿ya hay una fila para esta clave?", col=ACENTO, maxw=500)
    s.text(150, 136, "¿hay registro?", col=GRIS, anchor="middle", maxw=270)
    s.text(430, 136, "reprocesar", col=GRIS, anchor="middle", maxw=230)
    s.text(690, 136, "qué hace el paso", col=GRIS, anchor="middle", maxw=270)
    filas = (
        ("no hay registro", "false", "SE INGESTA", ["la primera vez"], BLANCO, INK),
        (
            "sí hay registro",
            "false",
            "SE SALTÓ",
            ["sin mirar filas,", "cómputo ni límite"],
            PANEL,
            GRIS,
        ),
        (
            "da igual",
            "true",
            "SE INGESTA",
            ["a propósito; silver", "resuelve los duplicados"],
            BLANCO,
            INK,
        ),
    )
    for i, (reg, rep, resultado, nota, fondo, borde) in enumerate(filas):
        y = 150 + i * 72
        s.caja(6, y, 288, 62, [reg], fill=PANEL, line=GRIS)
        s.caja(310, y, 240, 62, [rep], fill=PANEL, line=GRIS, mono=True)
        s.flecha(552, y + 31, 574, y + 31)
        s.caja(576, y, 230, 62, [resultado], fill=fondo, line=borde, lw=2.5)
        s.lineas(830, y + 23 if len(nota) > 1 else y + 38, nota, col=GRIS, maxw=284)
    s.text(
        560,
        396,
        "El paso anota su fila solo al terminar bien:",
        bold=True,
        anchor="middle",
        maxw=1090,
    )
    s.text(
        560,
        426,
        "si falla, no queda registro y el mes se puede reintentar.",
        col=GRIS,
        anchor="middle",
        maxw=1090,
    )
    s.guardar(ruta)


# --------------------------------------------------------------------------- Dc7-4
def dc7_4(ruta):
    s = S(
        "Dc7-4",
        "La escalera de dev a prod: siete peldaños, y prod solo se alcanza por PR y CI/CD",
        "Siete peldaños que suben de izquierda a derecha. Los cuatro primeros son dev, desde el Code Editor: notebook y make test, make correr con code_editor, "
        "make correr con glue_small y Airflow del Code Editor. Una línea punteada separa dev de prod. Los tres últimos son prod: pull request y CI, merge y Deploy, y el DAG en la VM.",
    )
    pasos = (
        ["Notebook", "y make test"],
        ["make correr", "code_editor"],
        ["make correr", "glue_small"],
        ["Airflow del", "Code Editor"],
        ["Pull request", "y CI"],
        ["Merge y", "Deploy"],
        ["DAG en la", "VM (prod)"],
    )
    for i, ts in enumerate(pasos):
        x = 6 + i * 158
        y = 340 - i * 46
        if i < 4:
            s.caja(x, y, 148, 84, ts, fill=PANEL, line=GRIS)
        else:
            s.caja(x, y, 148, 84, ts, fill=BLANCO, line=INK, lw=3)
    xd = 6 + 4 * 158 - 5
    s.linea(xd, 66, xd, 432, col=ROJO, lw=2.5, dash="8 6")
    s.text(xd - 12, 36, "dev: todo desde el Code Editor", bold=True, anchor="end", maxw=560)
    s.text(xd + 12, 36, "prod: solo por PR y CI/CD", bold=True, col=ROJO, maxw=470)
    s.guardar(ruta)


# --------------------------------------------------------------------------- Dc7-5
def dc7_5(ruta):
    s = S(
        "Dc7-5",
        "Reprocesar con silver sin deduplicar: silver se multiplica y gold se multiplica al cubo",
        "Tres filas, una por corrida. En la primera hay un lote en bronze, silver multiplicado por uno y gold por uno. En la segunda, con reprocesar, dos lotes, silver por dos y gold por ocho. "
        "En la tercera, tres lotes, silver por tres y gold por veintisiete. La barra de gold crece con el cubo del número de lotes, porque enriquecer une zonas y clima, que también se repiten.",
    )
    s.text(228, 30, "lotes en bronze", col=GRIS, maxw=150)
    s.text(430, 30, "silver", col=GRIS)
    s.text(640, 30, "gold", col=GRIS)
    filas = (
        (1, "1.ª corrida"),
        (2, "2.ª corrida"),
        (3, "3.ª corrida"),
    )
    for i, (n, etiqueta) in enumerate(filas):
        y = 56 + i * 104
        s.text(6, y + 34, etiqueta, bold=True, maxw=190)
        s.text(6, y + 62, "reprocesar" if n > 1 else "primera vez", col=GRIS, maxw=190)
        for j in range(n):
            s.rect(228 + j * 44, y + 14, 36, 36, fill=BRONZE, line=BRONZE)
        s.rect(430, y + 14, 56 * n, 36, fill=SILVER, line=SILVER)
        s.text(430 + 56 * n + 12, y + 42, f"×{n}", bold=True, col=(ROJO if n > 1 else INK))
        ancho_gold = max(14, int(14.5 * n**3))
        s.rect(640, y + 14, ancho_gold, 36, fill=GOLD, line=GOLD)
        s.text(640 + ancho_gold + 12, y + 42, f"×{n**3}", bold=True, col=(ROJO if n > 1 else INK))
    s.text(
        560,
        392,
        "gold sube con el cubo de los lotes: enriquecer une zonas y clima,",
        anchor="middle",
        maxw=1100,
    )
    s.text(560, 422, "y esas dos tablas de silver también se repiten.", anchor="middle", maxw=1100)
    s.guardar(ruta)


# --------------------------------------------------------------------------- Dc7-6
def dc7_6(ruta):
    s = S(
        "Dc7-6",
        "El mismo paso desde tres puertas: solo cambia el cómputo",
        "A la izquierda, tres formas de lanzar el paso silver: la función correr_silver en un notebook, make correr PASO=silver en la terminal y la tarea correr_silver del DAG pipeline_taxi. "
        "Las tres llaman a la misma función de pipeline/correr.py, que imprime el mismo encabezado y cierre. A la derecha, el cómputo decide dónde se calcula: code_editor, Spark en tu máquina, o un job de Glue.",
    )
    entradas = (
        (40, ["Notebook", "correr_silver()"]),
        (170, ["Terminal", "make correr PASO=silver"]),
        (300, ["Airflow", "tarea correr_silver"]),
    )
    for y, ts in entradas:
        s.caja(6, y, 340, 80, ts)
        s.flecha(348, y + 40, 396, 215, col="g", lw=3)
    s.caja(
        398,
        130,
        300,
        170,
        ["correr_silver", "pipeline/correr.py", "mismo encabezado", "mismo cierre"],
        fill=BLANCO,
        line=INK,
        lw=3,
    )
    s.flecha(700, 190, 746, 106, col="g", lw=3)
    s.flecha(700, 240, 746, 324, col="g", lw=3)
    s.caja(748, 56, 366, 100, ["computo = code_editor", "Spark en tu máquina"])
    s.caja(748, 276, 366, 100, ["computo = glue_*", "un job de Glue en la nube"])
    s.text(931, 228, "lo único que cambia", bold=True, anchor="middle", col=GRIS, maxw=360)
    s.guardar(ruta)


if __name__ == "__main__":
    base = Path(__file__).parent
    dc7_0(base / "Dc7-0.svg")
    dc7_1(base / "Dc7-1.svg")
    dc7_2(base / "Dc7-2.svg")
    dc7_3(base / "Dc7-3.svg")
    dc7_4(base / "Dc7-4.svg")
    dc7_5(base / "Dc7-5.svg")
    dc7_6(base / "Dc7-6.svg")
