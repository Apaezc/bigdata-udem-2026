#!/usr/bin/env python3
"""build.py <carpeta_deck> [--clase N] [--sin-pdf] [--sin-png] [--sin-pptx]

Lee <carpeta_deck>/slides.json y genera index.html, slides.pdf, png/slide-NN.png
y slides.pptx. Una sola descripción de layout (primitivas rect/oval/texto/imagen)
alimenta HTML y PPTX, por eso coinciden.
"""

import html
import json
import math
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from tema import (
    CAPAS,
    COLORES,
    CW,
    FUENTES,
    LIMITE_PALABRAS,
    ML,
    TAM_COLUMNA_MAX,
    TAM_CUERPO_MIN,
    TAM_MARCA,
    TAM_PIE,
    TAM_TABLA_MAX,
    H,
    W,
    color,
    css_root,
    tinte,
)

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
AVISOS = []


def aviso(n, tipo, msg):
    AVISOS.append(f"[slide {n} · {tipo}] {msg}")
    print(f"AVISO slide {n} ({tipo}): {msg}", file=sys.stderr)


# ----------------------------------------------------------------- primitivas
def R(x, y, w, h, fill=None, line=None, lw=1, r=0, oval=False):
    return dict(k="rect", x=x, y=y, w=w, h=h, fill=fill, line=line, lw=lw, r=r, oval=oval)


INLINE = re.compile(r"(\*\*.+?\*\*|`.+?`)")


def inline(s):
    """'texto **negrita** y `mono`' -> runs [(texto, {..})]"""
    runs = []
    for parte in INLINE.split(s):
        if not parte:
            continue
        if parte.startswith("**") and parte.endswith("**"):
            runs.append((parte[2:-2], {"bold": True}))
        elif parte.startswith("`") and parte.endswith("`"):
            runs.append((parte[1:-1], {"mono": True}))
        else:
            runs.append((parte, {}))
    return runs or [("", {})]


def T(
    x,
    y,
    w,
    h,
    paras,
    size=24,
    col="ink",
    bold=False,
    align="l",
    anchor="t",
    lh=1.3,
    mono=False,
    after=0,
    nowrap=False,
    upper=False,
    cuenta=True,
    code=False,
    celda=False,
):
    if isinstance(paras, str):
        paras = [paras]
    norm = []
    for p in paras:
        if isinstance(p, str):
            p = inline(p.upper() if upper else p)
        norm.append(p)
    return dict(
        k="text",
        x=x,
        y=y,
        w=w,
        h=h,
        paras=norm,
        size=size,
        col=color(col),
        bold=bold,
        align=align,
        anchor=anchor,
        lh=lh,
        mono=mono,
        after=after,
        nowrap=nowrap,
        cuenta=cuenta,
        code=code,
        celda=celda,
    )


def texto_plano(p):
    return "".join(t for t, _ in p)


# ------------------------------------------------------------- piezas comunes
def titulo(s, y=54):
    return [
        R(ML, 36, 56, 5, fill="acento"),
        T(ML, y, CW, 96, s["titulo"], size=34, bold=True, lh=1.18),
    ]


def pie_comun(n, clase, claro=False):
    c = COLORES["acento_txt"] if claro else "gris"
    reg = tinte("acento", 0.4) if claro else "regla"
    return [
        R(ML, 668, CW, 1, fill=reg),
        T(ML, 676, 500, 22, f"Big Data · Clase {clase}", size=TAM_PIE, col=c, lh=1.2, cuenta=False),
        T(W - ML - 100, 676, 100, 22, str(n), size=TAM_PIE, col=c, lh=1.2, align="r", cuenta=False),
    ]


def marca_aqui(capa):
    """Marca 'estás aquí' reutilizable: tres pastillas de capa, la actual rellena."""
    if capa not in CAPAS:
        return []
    out = []
    cw, ch, gap, y = 100, 32, 8, 22  # pastillas: 32 px de alto (antes 26)
    x0 = W - ML - 3 * cw - 2 * gap
    out.append(
        T(
            x0 - 136,
            y,
            128,
            ch,
            "ESTÁS AQUÍ",
            size=TAM_MARCA,
            col="gris",
            bold=True,
            align="r",
            anchor="m",
            lh=1.2,
            cuenta=False,
        )
    )
    for i, c in enumerate(CAPAS):
        x = x0 + i * (cw + gap)
        if c == capa:
            out.append(R(x, y, cw, ch, fill=c))
            out.append(
                T(
                    x,
                    y,
                    cw,
                    ch,
                    c.upper(),
                    size=TAM_MARCA,
                    col="blanco",
                    bold=True,
                    align="c",
                    anchor="m",
                    lh=1.2,
                    cuenta=False,
                )
            )
        else:
            out.append(R(x, y, cw, ch, line=color("regla"), lw=1.5))
            out.append(
                T(
                    x,
                    y,
                    cw,
                    ch,
                    c.upper(),
                    size=TAM_MARCA,
                    col="gris",
                    bold=True,
                    align="c",
                    anchor="m",
                    lh=1.2,
                    cuenta=False,
                )
            )
    return out


def svg_tam(ruta):
    txt = Path(ruta).read_text(encoding="utf-8")
    m = re.search(r'viewBox="\s*[-\d.]+[ ,]+[-\d.]+[ ,]+([\d.]+)[ ,]+([\d.]+)', txt)
    if m:
        return float(m.group(1)), float(m.group(2))
    w = re.search(r'\swidth="([\d.]+)', txt)
    h = re.search(r'\sheight="([\d.]+)', txt)
    if w and h:
        return float(w.group(1)), float(h.group(1))
    raise ValueError(f"SVG sin viewBox/width/height: {ruta}")


# ------------------------------------------------------- relleno (alto útil)
ZONA_TOP, ZONA_BOT = 164, 656  # alto útil: bajo el título/marca, sobre la regla del pie (668)
ZONA_H = ZONA_BOT - ZONA_TOP  # 492 px
OCUP_MIN, OCUP_OBJ, OCUP_TOPE = 0.60, 0.75, 0.85
PASO_RELLENO = 2


def lineas_de(texto, ancho, size, bold=False, mono=False):
    """Líneas que ocupa `texto` en una caja de `ancho` px (ajuste por palabra, estimación conservadora)."""
    f = 0.62 if mono else (0.58 if bold else 0.54)
    por_linea = max(1, int(ancho // (size * f)))
    n, cur = 1, 0
    for palabra in texto.split() or [""]:
        L = len(palabra)
        if L > por_linea:  # palabra que no cabe: se parte a la fuerza
            if cur:
                n += 1
            n += (L - 1) // por_linea
            cur = L % por_linea or por_linea
        elif cur == 0:
            cur = L
        elif cur + 1 + L <= por_linea:
            cur += 1 + L
        else:
            n += 1
            cur = L
    return n


def crecer(base, maximo, medir):
    """Sube el cuerpo de 2 en 2 px mientras la ocupación esté por debajo del 60 %, hasta
    ~75 % o el máximo. `medir(size)` devuelve la altura del contenido en px, o None si no cabe.
    Nunca baja de `base` ni de TAM_CUERPO_MIN."""
    s = max(base, TAM_CUERPO_MIN)
    h = medir(s)
    if h is None or h / ZONA_H >= OCUP_MIN:
        return s
    while s + PASO_RELLENO <= maximo:
        h2 = medir(s + PASO_RELLENO)
        if h2 is None or h2 / ZONA_H > OCUP_TOPE:
            break
        s += PASO_RELLENO
        if h2 / ZONA_H >= OCUP_OBJ:
            break
    return s


# --------------------------------------------------------------------- tipos
def L_portada(s, n, ctx):
    return COLORES["bg"], [
        R(0, 0, 24, H, fill="acento"),
        T(ML + 20, 120, 900, 30, "BIG DATA · UDEM", size=20, col="acento", bold=True, cuenta=False),
        T(ML + 20, 190, 1000, 240, s["titulo"], size=64, bold=True, lh=1.08, anchor="m"),
        T(ML + 20, 450, 900, 90, s.get("subtitulo", ""), size=28, col="gris", lh=1.3),
        R(ML + 20, 590, 110, 10, fill="bronze"),
        R(ML + 20 + 110, 590, 110, 10, fill="silver"),
        R(ML + 20 + 220, 590, 110, 10, fill="gold"),
        T(
            ML + 20,
            620,
            1000,
            30,
            s.get("meta", f"Clase {ctx['clase']}"),
            size=20,
            col="gris",
            lh=1.2,
            cuenta=False,
        ),
    ]


def L_seccion(s, n, ctx):
    _n = str(s.get("numero", ""))
    num = _n.zfill(2) if _n.isdigit() else _n
    return COLORES["bg"], marca_aqui(s.get("aqui")) + [
        T(
            ML,
            110,
            520,
            400,
            num,
            size=300,
            col="acento",
            bold=True,
            lh=1.0,
            anchor="m",
            cuenta=False,
        ),
        R(620, 170, 3, 380, fill="regla"),
        T(
            660,
            170,
            540,
            30,
            s.get("etiqueta", "Sección").upper(),
            size=20,
            col="acento",
            bold=True,
            lh=1.2,
        ),
        T(660, 215, 540, 340, s["pregunta"], size=44, bold=True, lh=1.15),
    ] + pie_comun(n, ctx["clase"])


PIE_VIS_TAM, PIE_VIS_LH = 22, 1.2  # texto de pie bajo el diagrama
PIE_VIS_BASE = 652  # borde inferior del texto de pie (regla del pie en 668)
GAP_DIAG_PIE = 16  # separación mínima diagrama - pie


def L_titulo_visual(s, n, ctx):
    p = ctx["base"] / s["diagrama"]
    prims = titulo(s) + marca_aqui(s.get("aqui"))
    texto_pie = s.get("pie", "")
    nl = lineas_de(texto_pie, CW, PIE_VIS_TAM) if texto_pie else 1
    pie_h = nl * PIE_VIS_TAM * PIE_VIS_LH
    pie_y = PIE_VIS_BASE - pie_h
    if not p.exists():
        aviso(n, "titulo_visual", f"no existe el diagrama {p}")
    else:
        sw, sh = svg_tam(p)
        bx, by = ML, 164
        bw, bh = CW, (pie_y - GAP_DIAG_PIE) - by  # máximo alto disponible sobre el pie
        k = min(bw / sw, bh / sh)  # máximo ancho/alto manteniendo proporción
        w, h = sw * k, sh * k
        prims.append(
            dict(
                k="img",
                x=bx + (bw - w) / 2,
                y=by + (bh - h) / 2,
                w=w,
                h=h,
                src=s["diagrama"],
                ruta=str(p),
                alt=s.get("alt", ""),
            )
        )
    if texto_pie:
        prims.append(
            T(ML, pie_y, CW, pie_h, texto_pie, size=PIE_VIS_TAM, col="gris", lh=PIE_VIS_LH)
        )
    return COLORES["bg"], prims + pie_comun(n, ctx["clase"])


def L_dato_grande(s, n, ctx):
    cifra = str(s["cifra"])
    size = max(110, min(250, int(CW / (len(cifra) * 0.64))))
    c = s.get("capa", "acento")
    return COLORES["bg"], marca_aqui(s.get("aqui")) + [
        T(
            ML - 6,
            70,
            CW,
            300,
            cifra,
            size=size,
            col=c,
            bold=True,
            lh=1.0,
            anchor="b",
            cuenta=False,
        ),
        R(ML, 396, 120, 6, fill=c),
        T(ML, 424, 980, 140, s["contexto"], size=32, lh=1.25),
        T(ML, 612, CW, 28, s.get("fuente", ""), size=18, col="gris", lh=1.2),
    ] + pie_comun(n, ctx["clase"])


# ------------------------------------------------------------ tablas (ancho)
ANCHO_MIN_COL = 100  # px mínimo por columna
PAD_CELDA = 20  # la caja de texto deja 10 px a cada lado
TAB_TAM, TAB_TAM_MIN, TAB_PASO = 22, TAM_CUERPO_MIN, 2


def ancho_texto(texto, size, mono=False):
    """Estimación del ancho en px de un texto sin cortes (mono 0.6 em, sans 0.55 em por carácter)."""
    return len(texto) * size * (0.6 if mono else 0.55)


def anchos_proporcionales(pesos, total, minimo=ANCHO_MIN_COL):
    """Reparte `total` px en proporción a `pesos`; ninguna columna baja de `minimo`."""
    minimo = min(minimo, total / len(pesos))
    fijas = set()
    while True:
        libre = total - minimo * len(fijas)
        suma = sum(p for i, p in enumerate(pesos) if i not in fijas)
        ws = [minimo if i in fijas else libre * p / suma for i, p in enumerate(pesos)]
        nuevas = {i for i, w in enumerate(ws) if w < minimo and i not in fijas}
        if not nuevas:
            return ws
        fijas |= nuevas


def partir_snake(texto):
    """'distancia_promedio' -> ['distancia_', 'promedio'], cortando en el `_` más equilibrado."""
    pos = [i for i, c in enumerate(texto) if c == "_"]
    if not pos:
        return [texto]
    i = min(pos, key=lambda i: max(i + 1, len(texto) - i - 1))
    return [texto[: i + 1], texto[i + 1 :]]


def lineas_cab(texto, partir):
    return partir_snake(texto) if partir and "_" in texto else [texto]


def unidades(texto, partir=False):
    """Trozos que no pueden cortarse: palabras (y, con `partir`, las mitades de un snake_case)."""
    if partir and "_" in texto:
        return partir_snake(texto)
    return texto.split() or [""]


def cabe(celdas, anchos, size, partir):
    """celdas[i] = [(texto, mono, es_encabezado), ...]: ¿cabe la unidad más ancha de cada celda?"""
    for col, w in zip(celdas, anchos, strict=False):
        for texto, mono, cab in col:
            for u in unidades(texto, partir and cab):
                if round(ancho_texto(u, size, mono), 1) > w - PAD_CELDA:
                    return False
    return True


def ajustar_tabla(celdas, pesos, tam=TAB_TAM):
    """Anchos y tamaño común de la tabla. Baja de 2 en 2 px hasta 16; si aun así no cabe,
    parte los encabezados en `_`. Devuelve (anchos, tamaño, partir, cabe)."""
    anchos = anchos_proporcionales(pesos, CW)
    t = tam
    while not cabe(celdas, anchos, t, False) and t - TAB_PASO >= TAB_TAM_MIN:
        t -= TAB_PASO
    if cabe(celdas, anchos, t, False):
        return anchos, t, False, True
    return anchos, t, True, cabe(celdas, anchos, t, True)


def alto_cabecera_tabla(enc, ws, sz, partir):
    """Alto de la fila de encabezados (mín. 48 px; crece si un encabezado ocupa varias líneas)."""
    lineas = max(
        sum(lineas_de(t, w - 20, sz, bold=True) for t in lineas_cab(e, partir))
        for e, w in zip(enc, ws, strict=False)
    )
    return max(48, lineas * sz * 1.15 + 8)


def L_comparacion(s, n, ctx):
    prims = titulo(s) + marca_aqui(s.get("aqui"))
    if "tabla" in s:
        enc, filas = s["tabla"]["encabezados"], s["tabla"]["filas"]
        nc = len(enc)
        if len(filas) > 8:
            aviso(n, "comparacion", "tabla con más de 8 filas")
        celdas = [
            [(enc[i], False, True)] + [(str(f[i]), False, False) for f in filas if i < len(f)]
            for i in range(nc)
        ]
        pesos = [max(len(c[0]) for c in col) for col in celdas]
        ws, size, partir, ok = ajustar_tabla(celdas, pesos)
        rh0 = min(64, int(400 / max(1, len(filas))))
        y = 172

        def partir_en(sz):
            """Encabezados enteros si caben; si no, partidos en «_» (None: no cabe ni así)."""
            if cabe(celdas, ws, sz, partir):
                return partir
            return True if cabe(celdas, ws, sz, True) else None

        def alto_tabla(sz):
            p_ = partir_en(sz)
            if p_ is None:
                return None
            rh = max(
                rh0,
                max(
                    (
                        lineas_de(str(c), w - 20, sz, bold=(i == 0)) * sz * 1.15 + 20
                        for fila in filas
                        for i, (c, w) in enumerate(zip(fila, ws, strict=False))
                    ),
                    default=0,
                ),
            )
            hh = alto_cabecera_tabla(enc, ws, sz, p_)
            return (y - ZONA_TOP) + hh + 4 + len(filas) * rh

        size = crecer(size, TAM_TABLA_MAX, alto_tabla)
        partir = partir_en(size) or partir
        if not ok:
            aviso(n, "comparacion", f"tabla no cabe ni a {size} px con encabezados partidos")
        elif partir:
            aviso(n, "comparacion", f"encabezados partidos en 2 líneas en «_» (tabla a {size} px)")
        xs = [ML + sum(ws[:i]) for i in range(nc)]
        hh = alto_cabecera_tabla(enc, ws, size, partir)
        lh_cab = 1.1 if partir else 1.15
        for i, e in enumerate(enc):
            prims.append(
                T(
                    xs[i] + 10,
                    y,
                    ws[i] - 20,
                    hh,
                    lineas_cab(e, partir),
                    size=size,
                    bold=True,
                    col="gris",
                    anchor="m",
                    lh=lh_cab,
                    celda=True,
                )
            )
        prims.append(R(ML, y + hh + 2, CW, 2, fill="ink"))
        rh = max(
            rh0,
            max(
                (
                    lineas_de(str(c), w - 20, size, bold=(i == 0)) * size * 1.15 + 20
                    for fila in filas
                    for i, (c, w) in enumerate(zip(fila, ws, strict=False))
                ),
                default=0,
            ),
        )
        for r_i, fila in enumerate(filas):
            yy = y + hh + 4 + r_i * rh
            for i, c in enumerate(fila):
                prims.append(
                    T(
                        xs[i] + 10,
                        yy,
                        ws[i] - 20,
                        rh,
                        str(c),
                        size=size,
                        bold=(i == 0),
                        anchor="m",
                        lh=1.15,
                        celda=True,
                    )
                )
            prims.append(R(ML, yy + rh - 1, CW, 1, fill="regla"))
        return COLORES["bg"], prims + pie_comun(n, ctx["clase"])
    cols = s["columnas"]
    nc = len(cols)
    if not 2 <= nc <= 4:
        aviso(n, "comparacion", f"usa 2 a 4 columnas (hay {nc})")
    gap = 36
    cw = (CW - gap * (nc - 1)) / nc
    base = 26 if nc <= 3 else 22

    # título de columna: por encima del cuerpo, nunca mayor que el título de la slide (34)
    def cab(sz):
        return max(28, min(sz + 4, 32))

    def alto_columnas(sz):
        hc = cab(sz)
        mx = 0
        for c in cols:
            ht = lineas_de(c["titulo"], cw, hc, bold=True) * hc * 1.15
            hi = sum(lineas_de("– " + it, cw, sz) * sz * 1.3 for it in c["items"])
            hi += 18 * max(0, len(c["items"]) - 1)
            mx = max(mx, ht + 18 + hi)
        return (196 - ZONA_TOP) + mx

    size = crecer(base, TAM_COLUMNA_MAX, alto_columnas)
    hc = cab(size)
    for i, c in enumerate(cols):
        x = ML + i * (cw + gap)
        cc = c.get("capa", "ink")
        ht = lineas_de(c["titulo"], cw, hc, bold=True) * hc * 1.15
        prims += [
            R(x, 176, cw, 6, fill=cc),
            T(
                x,
                196,
                cw,
                ht,
                c["titulo"],
                size=hc,
                bold=True,
                col=cc if c.get("capa") else "ink",
                lh=1.15,
            ),
            T(
                x,
                196 + ht + 18,
                cw,
                ZONA_BOT - (196 + ht + 18),
                ["– " + it for it in c["items"]],
                size=size,
                lh=1.3,
                after=18,
            ),
        ]
    return COLORES["bg"], prims + pie_comun(n, ctx["clase"])


SQL_KW = set(
    """select from where group by order having join left right inner outer full cross on as
create or replace table view insert into values update set delete and not null is in case when then
else end limit distinct union all with using over partition desc asc between like exists""".split()
)


def sql_runs(linea):
    runs = []
    for m in re.finditer(
        r"(--[^\n]*)|('(?:[^']|'')*')|(\b\d+(?:\.\d+)?\b)|([A-Za-z_][A-Za-z_0-9]*)|(\s+)|(.)", linea
    ):
        txt = m.group(0)
        if m.group(1):
            runs.append((txt, {"color": COLORES["sql_com"], "italic": True}))
        elif m.group(2):
            runs.append((txt, {"color": COLORES["sint_str"]}))
        elif m.group(4) and txt.lower() in SQL_KW:
            runs.append((txt, {"color": COLORES["acento"], "bold": True}))
        else:
            runs.append((txt, {}))
    return runs or [("", {})]


def L_codigo(s, n, ctx):
    lineas = s["sql"].rstrip("\n").split("\n")
    size, lh = 22, 1.5
    lpx = size * lh
    if len(lineas) > 12:
        aviso(n, "codigo", f"{len(lineas)} líneas de código (máx. 12)")
    if any(len(l) > 78 for l in lineas):
        aviso(n, "codigo", "hay líneas de más de 78 caracteres: se cortarán")
    ph = min(len(lineas) * lpx + 36, 440)
    prims = titulo(s) + marca_aqui(s.get("aqui"))
    prims += [R(ML, 164, CW, ph, fill="panel"), R(ML, 164, 6, ph, fill="acento")]
    for i in s.get("resaltar", []):
        prims.append(R(ML + 6, 164 + 18 + (i - 1) * lpx, CW - 6, lpx, fill=tinte("acento", 0.16)))
    prims.append(
        T(
            ML + 34,
            164 + 18,
            CW - 60,
            ph - 18,
            [sql_runs(l) for l in lineas],
            size=size,
            lh=lh,
            mono=True,
            nowrap=True,
            cuenta=False,
            code=True,
        )
    )
    ey = 164 + ph + 16
    prims.append(
        T(ML, ey, CW, max(30, 662 - ey), s.get("explicacion", ""), size=24, lh=1.25, anchor="t")
    )
    return COLORES["bg"], prims + pie_comun(n, ctx["clase"])


def L_fila(s, n, ctx):
    cols = s["columnas"]
    nc = len(cols)
    if nc > 7:
        aviso(n, "fila", f"{nc} columnas (máx. 7)")
    prims = titulo(s) + marca_aqui(s.get("aqui"))
    if s.get("tabla"):
        prims.append(
            T(ML, 164, CW, 28, s["tabla"], size=20, col="gris", mono=True, lh=1.2, cuenta=False)
        )
    celdas = []
    for c in cols:
        col = [(c["nombre"], True, True), (str(c["valor"]), True, False)]
        if c.get("nota"):
            col.append((c["nota"], False, False))
        celdas.append(col)
    pesos = [max(len(c["nombre"]), len(str(c["valor"]))) for c in cols]
    anchos, size, partir, ok = ajustar_tabla(celdas, pesos)
    hy = 204
    notas = [(c, w) for c, w in zip(cols, anchos, strict=False) if c.get("nota")]

    def partir_en(sz):
        """Encabezados enteros si caben; si no, partidos en «_» (None: no cabe ni así)."""
        if cabe(celdas, anchos, sz, partir):
            return partir
        return True if cabe(celdas, anchos, sz, True) else None

    def geometria(sz, p_):
        """Altura del encabezado, de la celda de valor y del bloque de notas a `sz` px."""
        hh = max(
            56,
            max(
                sum(
                    lineas_de(t, w - 20, sz, bold=True, mono=True)
                    for t in lineas_cab(c["nombre"], p_)
                )
                for c, w in zip(cols, anchos, strict=False)
            )
            * sz
            * 1.15
            + 16,
        )
        vh = max(
            132,
            max(
                lineas_de(str(c["valor"]), w - 20, sz, mono=True)
                for c, w in zip(cols, anchos, strict=False)
            )
            * sz
            * 1.25
            + 24,
        )
        nh = 0
        if notas:
            nh = 38 + max(lineas_de(c["nota"], w - 12, sz, bold=True) for c, w in notas) * sz * 1.25
        return hh, vh, nh

    def alto_fila(sz):
        p_ = partir_en(sz)
        if p_ is None:
            return None
        hh, vh, nh = geometria(sz, p_)
        return (hy - ZONA_TOP) + hh + vh + nh

    size = crecer(size, TAM_TABLA_MAX, alto_fila)
    partir = partir_en(size) or partir
    if not ok:
        aviso(n, "fila", f"no cabe ni a {size} px con encabezados partidos")
    elif partir:
        aviso(n, "fila", f"encabezados partidos en 2 líneas en «_» (fila a {size} px)")
    hh, vh, nh = geometria(size, partir)
    x = ML
    for c, cw in zip(cols, anchos, strict=False):
        cc = c.get("capa")
        if cc:
            prims += [R(x, hy, cw, hh, fill=cc), R(x, hy + hh, cw, vh, fill=tinte(cc, 0.16))]
        else:
            prims += [R(x, hy, cw, hh, fill="panel"), R(x, hy + hh, cw, vh, fill=None)]
        prims += [
            T(
                x + 10,
                hy,
                cw - 20,
                hh,
                lineas_cab(c["nombre"], partir),
                size=size,
                bold=True,
                mono=True,
                col="blanco" if cc else "ink",
                anchor="m",
                lh=1.15,
                cuenta=False,
                celda=True,
            ),
            T(
                x + 10,
                hy + hh + 6,
                cw - 20,
                vh - 12,
                str(c["valor"]),
                size=size,
                mono=True,
                anchor="m",
                lh=1.25,
                cuenta=False,
                celda=True,
            ),
        ]
        x += cw
    # bordes de la tabla
    prims += [R(ML, hy + hh + vh - 1, CW, 2, fill="ink"), R(ML, hy, CW, 2, fill="ink")]
    x = ML
    for c, cw in zip(cols, anchos, strict=False):
        if c.get("nota"):
            cc = c.get("capa", "acento")
            prims += [
                R(x + 14, hy + hh + vh, 3, 30, fill=cc),
                T(
                    x + 6,
                    hy + hh + vh + 38,
                    cw - 12,
                    nh - 38,
                    c["nota"],
                    size=size,
                    lh=1.25,
                    col="ink",
                    bold=True,
                    celda=True,
                ),
            ]
        x += cw
    return COLORES["bg"], prims + pie_comun(n, ctx["clase"])


def L_pregunta(s, n, ctx):
    fondo = COLORES["acento"]
    return fondo, [
        T(
            ML,
            110,
            600,
            30,
            s.get("etiqueta", "Pregunta").upper(),
            size=20,
            col="acento_txt",
            bold=True,
            cuenta=False,
        ),
        T(ML, 160, 1060, 360, s["pregunta"], size=60, col="blanco", bold=True, lh=1.12),
        T(ML, 560, 1060, 50, s.get("pista", ""), size=26, col="acento_txt", lh=1.2),
    ] + pie_comun(n, ctx["clase"], claro=True)


def L_pasos(s, n, ctx):
    pasos = s["pasos"]
    npz = len(pasos)
    if not 3 <= npz <= 6:
        aviso(n, "pasos", f"usa 3 a 6 pasos (hay {npz})")
    prims = titulo(s) + marca_aqui(s.get("aqui"))
    v = s.get("ventana", "Ventana")
    bw = 112 + len(v) * 13
    prims += [
        R(ML, 164, bw, 38, line="ink", lw=2, r=6),
        R(ML + 14, 178, 10, 10, fill="gris", oval=True),
        R(ML + 30, 178, 10, 10, fill="gris", oval=True),
        R(ML + 46, 178, 10, 10, fill="gris", oval=True),
        T(ML + 72, 164, bw - 80, 38, v, size=22, bold=True, anchor="m", lh=1.1),
    ]
    top = 226
    rh0 = min(70, 420 // max(1, npz))
    textos = [texto_plano(inline(p)) for p in pasos]

    def rh_de(sz):
        """Alto de fila: el base, o más si el texto a `sz` px necesita más líneas."""
        mx = max((lineas_de(t, CW - 70, sz) for t in textos), default=1)
        return max(rh0, mx * sz * 1.2 + 16)

    size = crecer(24, TAM_COLUMNA_MAX, lambda sz: (top - ZONA_TOP) + npz * rh_de(sz))
    rh = rh_de(size)
    for i, p in enumerate(pasos):
        y = top + i * rh
        prims += [
            T(
                ML,
                y,
                56,
                rh,
                str(i + 1),
                size=34,
                col="acento",
                bold=True,
                anchor="m",
                lh=1.0,
                cuenta=False,
            ),
            T(ML + 70, y, CW - 70, rh, p, size=size, anchor="m", lh=1.2),
            R(ML, y + rh - 1, CW, 1, fill="regla"),
        ]
    return COLORES["bg"], prims + pie_comun(n, ctx["clase"])


TIPOS = {
    "portada": L_portada,
    "seccion": L_seccion,
    "titulo_visual": L_titulo_visual,
    "dato_grande": L_dato_grande,
    "comparacion": L_comparacion,
    "codigo": L_codigo,
    "fila": L_fila,
    "pregunta": L_pregunta,
    "pasos": L_pasos,
}


# --------------------------------------------------------------- validaciones
def validar(prims, n, tipo):
    palabras = 0
    for p in prims:
        if p["k"] != "text":
            continue
        plano = [texto_plano(x) for x in p["paras"]]
        if p["cuenta"]:
            palabras += sum(len(t.split()) for t in plano)
        f = 0.62 if p["mono"] else (0.56 if p["bold"] else 0.52)
        cw = p["w"]
        lineas = 0
        for t in plano:
            lineas += 1 if p["nowrap"] else max(1, math.ceil(len(t) * p["size"] * f / cw))
        alto = lineas * p["size"] * p["lh"] + p["after"] * max(0, len(plano) - 1)
        if p["nowrap"] and any(len(t) * p["size"] * f > cw for t in plano):
            aviso(n, tipo, f"línea de código más ancha que la caja: «{plano[0][:30]}…»")
        if p.get("celda"):
            for t in plano:
                for u in unidades(t):
                    ancho = ancho_texto(u, p["size"], p["mono"])
                    if round(ancho, 1) > p["w"]:
                        aviso(
                            n,
                            tipo,
                            f"desborde horizontal: «{u}» ({ancho:.0f} px) no cabe en {p['w']:.0f} px",
                        )
        if alto > p["h"] * 1.04 + 2:
            aviso(n, tipo, f"posible desborde vertical ({lineas} líneas): «{plano[0][:40]}…»")
    lim = LIMITE_PALABRAS.get(tipo, 40)
    if palabras > lim:
        aviso(n, tipo, f"{palabras} palabras (límite {lim})")


# ------------------------------------------------------------------ HTML
CSS = """
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;background:#0E0F12;overflow:hidden;font-family:var(--sans);color:var(--ink)}
#stage{position:absolute;left:50%;top:0;width:1280px;height:720px;margin-left:-640px;transform-origin:top center}
.slide{display:none;position:relative;width:1280px;height:720px;overflow:hidden;background:var(--bg)}
.slide.on{display:block}
.slide .e{position:absolute}
.slide .t{position:absolute;overflow:hidden;display:flex;flex-direction:column;font-family:var(--sans)}
.slide .t p{min-height:var(--lh);margin:0}
.slide .t.m p{font-family:var(--mono)}
.slide .t.nw p{white-space:pre}
.slide .t span.mono{font-family:var(--mono);font-size:.92em}
.slide .t span.b{font-weight:700}
.slide img{position:absolute}
.slide .notas{display:none}
#panel{display:none;position:fixed;left:0;right:0;bottom:0;height:var(--ph);background:#17191F;color:#E7E5DE;
  padding:14px 24px;font:20px/1.45 var(--sans);overflow:auto;border-top:3px solid var(--acento)}
#panel b{color:#fff}#panel .meta{color:#9AA0AB;font-size:15px;margin-bottom:6px}
body.pres #panel{display:block}
#ayuda{position:fixed;right:10px;top:8px;font:12px var(--sans);color:#8a8f99}
body.solo #stage{position:absolute;left:0;top:0;margin:0;transform:none!important}
body.solo #panel,body.solo #ayuda{display:none!important}
@page{size:1280px 720px;margin:0}
@media print{
 html,body{background:none;height:auto;overflow:visible}
 #stage{position:static;margin:0;width:auto;height:auto;transform:none!important}
 .slide{display:block!important;break-after:page;page-break-after:always}
 .slide:last-child{break-after:auto;page-break-after:auto}
 #panel,#ayuda{display:none!important}
}
"""

JS = """
const slides=[...document.querySelectorAll('.slide')],stage=document.getElementById('stage'),
panel=document.getElementById('panel');let i=0;
const q=new URLSearchParams(location.search),solo=parseInt(q.get('solo'));
function show(n){i=Math.max(0,Math.min(slides.length-1,n));slides.forEach((s,k)=>s.classList.toggle('on',k===i));
 const s=slides[i],nt=s.querySelector('.notas').textContent.trim();
 panel.innerHTML='<div class="meta">Slide '+(i+1)+' / '+slides.length+' · '+(s.dataset.min?s.dataset.min+' min · ':'')+
 'p: ocultar notas</div>'+(nt?nt.replace(/\\n/g,'<br>'):'<i>(sin notas)</i>');
 if(!isNaN(solo))return;history.replaceState(null,'','#'+(i+1));}
function fit(){if(!isNaN(solo))return;const ph=document.body.classList.contains('pres')?Math.round(innerHeight*.26):0;
 document.documentElement.style.setProperty('--ph',ph+'px');
 const k=Math.min(innerWidth/1280,(innerHeight-ph)/720);
 stage.style.transform='scale('+k+')';stage.style.top=Math.max(0,(innerHeight-ph-720*k)/2)+'px';}
if(!isNaN(solo)){document.body.classList.add('solo');show(solo-1);}
else{show((parseInt(location.hash.slice(1))||1)-1);fit();
 addEventListener('resize',fit);
 addEventListener('keydown',e=>{const k=e.key;
  if(['ArrowRight','ArrowDown','PageDown',' ','Enter'].includes(k)){show(i+1);e.preventDefault()}
  else if(['ArrowLeft','ArrowUp','PageUp','Backspace'].includes(k)){show(i-1);e.preventDefault()}
  else if(k==='Home')show(0);else if(k==='End')show(slides.length-1);
  else if(k==='p'||k==='P'){document.body.classList.toggle('pres');fit()}
  else if(k==='f'||k==='F'){document.fullscreenElement?document.exitFullscreen():document.documentElement.requestFullscreen()}});
 stage.addEventListener('click',e=>show(e.clientX>innerWidth/2?i+1:i-1));}
"""


def estilo(p):
    return f"left:{p['x']:.1f}px;top:{p['y']:.1f}px;width:{p['w']:.1f}px;height:{p['h']:.1f}px;"


def html_prim(p):
    if p["k"] == "rect":
        st = estilo(p)
        if p["fill"]:
            st += f"background:{color(p['fill'])};"
        if p["line"]:
            st += f"border:{p['lw']}px solid {color(p['line'])};"
        if p["r"]:
            st += f"border-radius:{p['r']}px;"
        if p["oval"]:
            st += "border-radius:50%;"
        return f'<div class="e" style="{st}"></div>'
    if p["k"] == "img":
        return (
            f'<img src="{html.escape(p["src"])}" alt="{html.escape(p["alt"])}" style="{estilo(p)}">'
        )
    just = {"t": "flex-start", "m": "center", "b": "flex-end"}[p["anchor"]]
    lpx = p["size"] * p["lh"]
    st = (
        estilo(p)
        + f"font-size:{p['size']}px;line-height:{lpx:.1f}px;--lh:{lpx:.1f}px;color:{p['col']};"
        f"text-align:{ {'l': 'left', 'c': 'center', 'r': 'right'}[p['align']] };justify-content:{just};"
    )
    if p["bold"]:
        st += "font-weight:700;"
    cls = "t" + (" m" if p["mono"] else "") + (" nw" if p["nowrap"] else "")
    ps = []
    for k, par in enumerate(p["paras"]):
        sp = ""
        for t, f in par:
            attrs = []
            if f.get("color"):
                attrs.append(f"color:{f['color']}")
            if f.get("italic"):
                attrs.append("font-style:italic")
            if f.get("bold"):
                attrs.append("font-weight:700")
            c = ("mono " if f.get("mono") else "") + ("b" if f.get("bold") else "")
            sp += f'<span class="{c.strip()}" style="{";".join(attrs)}">{html.escape(t)}</span>'
        mb = f"margin-bottom:{p['after']}px;" if p["after"] and k < len(p["paras"]) - 1 else ""
        ps.append(f'<p style="{mb}">{sp}</p>')
    return f'<div class="{cls}" style="{st}">{"".join(ps)}</div>'


def pagina_html(slides, titulo_doc):
    secs = []
    for n, s in enumerate(slides, 1):
        cuerpo = "\n".join(html_prim(p) for p in s["prims"])
        notas = html.escape(s.get("notas", ""))
        mn = s.get("min", "")
        secs.append(
            f'<section class="slide" id="s{n}" data-tipo="{s["tipo"]}" data-min="{mn}" '
            f'style="background:{s["fondo"]}">\n{cuerpo}\n<div class="notas">{notas}</div></section>'
        )
    return f"""<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{html.escape(titulo_doc)}</title>
<style>
{css_root()}
{CSS}</style></head>
<body>
<div id="stage">
{chr(10).join(secs)}
</div>
<div id="panel"></div>
<div id="ayuda">← → navegar · p notas · f pantalla completa</div>
<script>{JS}</script>
</body></html>"""


# ------------------------------------------------------------------ Chrome
def chrome(args, timeout=90):
    ud = tempfile.mkdtemp(prefix="chrome-ud-")
    try:
        r = subprocess.run(
            [
                CHROME,
                "--headless",
                "--disable-gpu",
                "--hide-scrollbars",
                "--no-first-run",
                f"--user-data-dir={ud}",
                *args,
            ],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return r
    finally:
        shutil.rmtree(ud, ignore_errors=True)


def hacer_pdf(index, pdf):
    chrome(["--no-pdf-header-footer", f"--print-to-pdf={pdf}", index.as_uri()])
    if not pdf.exists():
        raise RuntimeError("Chrome no generó el PDF")


def hacer_pngs(index, carpeta, n):
    carpeta.mkdir(exist_ok=True)
    for f in carpeta.glob("slide-*.png"):
        f.unlink()
    for k in range(1, n + 1):
        out = carpeta / f"slide-{k:02d}.png"
        chrome(
            [
                f"--screenshot={out}",
                "--window-size=1280,720",
                "--virtual-time-budget=1500",
                index.as_uri() + f"?solo={k}",
            ]
        )
        if not out.exists():
            raise RuntimeError(f"Chrome no generó {out}")


def rasterizar_svg(ruta, destino):
    w, h = svg_tam(ruta)
    wrap = Path(tempfile.mkdtemp(prefix="svg-")) / "w.html"
    wrap.write_text(
        f'<html><body style="margin:0;background:{COLORES["bg"]}">'
        f'<img src="{Path(ruta).resolve().as_uri()}" style="width:{w}px;height:{h}px;display:block">'
        f"</body></html>"
    )
    chrome(
        [
            f"--screenshot={destino}",
            f"--window-size={int(w)},{int(h)}",
            "--force-device-scale-factor=2",
            "--virtual-time-budget=1500",
            wrap.as_uri(),
        ]
    )
    shutil.rmtree(wrap.parent, ignore_errors=True)
    if not Path(destino).exists():
        raise RuntimeError(f"no se pudo rasterizar {ruta}")


# ------------------------------------------------------------------ PPTX
def hex_rgb(h):
    from pptx.dml.color import RGBColor

    h = color(h).lstrip("#")
    return RGBColor(int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def hacer_pptx(slides, destino, tmpdir):
    from pptx import Presentation
    from pptx.enum.shapes import MSO_SHAPE
    from pptx.enum.text import MSO_ANCHOR, MSO_AUTO_SIZE, PP_ALIGN
    from pptx.util import Emu, Pt

    E = 9525  # EMU por px (1280 px = 13.333 in)
    prs = Presentation()
    prs.slide_width, prs.slide_height = Emu(W * E), Emu(H * E)
    blank = prs.slide_layouts[6]
    for _n, s in enumerate(slides, 1):
        sl = prs.slides.add_slide(blank)
        sl.background.fill.solid()
        sl.background.fill.fore_color.rgb = hex_rgb(s["fondo"])
        for p in s["prims"]:
            x, y, w, h = (Emu(int(p[k] * E)) for k in "xywh")
            if p["k"] == "rect":
                forma = (
                    MSO_SHAPE.OVAL
                    if p["oval"]
                    else (MSO_SHAPE.ROUNDED_RECTANGLE if p["r"] else MSO_SHAPE.RECTANGLE)
                )
                sh = sl.shapes.add_shape(forma, x, y, w, h)
                if p["r"] and not p["oval"]:
                    sh.adjustments[0] = min(0.5, p["r"] / min(p["w"], p["h"]))
                if p["fill"]:
                    sh.fill.solid()
                    sh.fill.fore_color.rgb = hex_rgb(p["fill"])
                else:
                    sh.fill.background()
                if p["line"]:
                    sh.line.color.rgb = hex_rgb(p["line"])
                    sh.line.width = Pt(p["lw"] * 0.75)
                else:
                    sh.line.fill.background()
                sh.shadow.inherit = False
            elif p["k"] == "img":
                png = Path(tmpdir) / (Path(p["ruta"]).stem + ".png")
                if not png.exists():
                    rasterizar_svg(p["ruta"], png)
                sl.shapes.add_picture(str(png), x, y, w, h)
            else:
                tb = sl.shapes.add_textbox(x, y, w, h)
                tf = tb.text_frame
                tf.word_wrap = not p["nowrap"]
                tf.auto_size = MSO_AUTO_SIZE.NONE
                tf.margin_left = tf.margin_right = tf.margin_top = tf.margin_bottom = 0
                tf.vertical_anchor = {
                    "t": MSO_ANCHOR.TOP,
                    "m": MSO_ANCHOR.MIDDLE,
                    "b": MSO_ANCHOR.BOTTOM,
                }[p["anchor"]]
                for k, par in enumerate(p["paras"]):
                    pa = tf.paragraphs[0] if k == 0 else tf.add_paragraph()
                    pa.alignment = {"l": PP_ALIGN.LEFT, "c": PP_ALIGN.CENTER, "r": PP_ALIGN.RIGHT}[
                        p["align"]
                    ]
                    pa.line_spacing = Pt(p["size"] * p["lh"] * 0.75)
                    if p["after"] and k < len(p["paras"]) - 1:
                        pa.space_after = Pt(p["after"] * 0.75)
                    for t, f in par:
                        r = pa.add_run()
                        r.text = t
                        mono = p["mono"] or f.get("mono")
                        r.font.name = FUENTES["mono_pptx"] if mono else FUENTES["sans_pptx"]
                        r.font.size = Pt(
                            p["size"] * (0.92 if f.get("mono") and not p["mono"] else 1) * 0.75
                        )
                        r.font.bold = bool(p["bold"] or f.get("bold"))
                        r.font.italic = bool(f.get("italic"))
                        r.font.color.rgb = hex_rgb(f.get("color", p["col"]))
        notas = s.get("notas", "")
        if s.get("min"):
            notas = (notas + f"\n\n[Duración: {s['min']} min]").strip()
        sl.notes_slide.notes_text_frame.text = notas
    prs.save(str(destino))


# ------------------------------------------------------------------ main
def main():
    args = sys.argv[1:]
    if not args or args[0].startswith("-"):
        print(__doc__)
        sys.exit(1)
    base = Path(args[0]).resolve()
    flags = set(a for a in args[1:] if a.startswith("--sin-"))
    clase_arg = args[args.index("--clase") + 1] if "--clase" in args else None
    datos = json.loads((base / "slides.json").read_text(encoding="utf-8"))
    cfg = datos if isinstance(datos, dict) else {}
    lista = cfg.get("slides") if cfg else datos
    m = re.search(r"clase(\d+)", str(base))
    clase = clase_arg or cfg.get("clase") or (str(int(m.group(1))) if m else "?")
    ctx = {"clase": clase, "base": base}

    slides = []
    for n, s in enumerate(lista, 1):
        t = s.get("tipo")
        if t not in TIPOS:
            sys.exit(f"slide {n}: tipo desconocido {t!r}. Válidos: {', '.join(TIPOS)}")
        try:
            fondo, prims = TIPOS[t](s, n, ctx)
        except KeyError as e:
            sys.exit(f"slide {n} ({t}): falta el campo {e}")
        validar(prims, n, t)
        if t not in ("portada", "seccion", "pregunta") and len(s.get("titulo", "").split()) > 18:
            aviso(n, t, "el título supera 18 palabras")
        if not s.get("notas"):
            aviso(n, t, "sin notas del orador")
        slides.append(dict(s, tipo=t, fondo=fondo, prims=prims))

    titulo_doc = cfg.get("titulo") or f"Big Data · Clase {clase}"
    index = base / "index.html"
    index.write_text(pagina_html(slides, titulo_doc), encoding="utf-8")
    print(f"index.html ({len(slides)} slides)")
    if "--sin-pdf" not in flags:
        hacer_pdf(index, base / "slides.pdf")
        print("slides.pdf")
    if "--sin-png" not in flags:
        hacer_pngs(index, base / "png", len(slides))
        print(f"png/slide-01..{len(slides):02d}.png")
    if "--sin-pptx" not in flags:
        tmp = tempfile.mkdtemp(prefix="deck-")
        try:
            hacer_pptx(slides, base / "slides.pptx", tmp)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
        print("slides.pptx")
    total_min = sum(float(s.get("min", 0) or 0) for s in slides)
    print(f"duración total declarada: {total_min:g} min · avisos: {len(AVISOS)}")


if __name__ == "__main__":
    main()
