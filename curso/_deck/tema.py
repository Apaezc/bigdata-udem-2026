"""Tema compartido: HTML (variables CSS) y PPTX leen de aquí. Una sola fuente de verdad."""

COLORES = {
    "bg": "#FBFAF6",        # fondo casi blanco
    "ink": "#15171C",       # texto casi negro
    "gris": "#5F6672",      # texto secundario
    "regla": "#D9D6CC",     # líneas finas
    "panel": "#F0EEE7",     # paneles/código
    "acento": "#2340D8",    # acento (cobalto)
    "bronze": "#B4622F",    # capa bronze (cobre)
    "silver": "#6E7F94",    # capa silver (gris azulado)
    "gold": "#B07F0E",      # capa gold (ocre)
    "blanco": "#FFFFFF",
    "sint_str": "#2E7D5B",  # sintaxis: cadenas
    "acento_txt": "#DDE4FF",  # texto (kicker, pie, pista) sobre fondo acento: contraste >= 5:1
    "sql_com": "#4A5160",     # comentarios SQL: gris oscuro legible sobre el resaltado acento
}

# tamaños mínimos y de relleno (px sobre lienzo 1280x720)
TAM_PIE = 15            # "Big Data · Clase N" y número de slide (mínimo 14)
TAM_MARCA = 14          # "ESTÁS AQUÍ" y pastillas BRONZE/SILVER/GOLD (mínimo 14)
TAM_CUERPO_MIN = 18     # ningún cuerpo de texto baja de aquí
TAM_COLUMNA_MAX = 30    # columnas y pasos
TAM_TABLA_MAX = 26      # tablas y filas

CAPAS = ["bronze", "silver", "gold"]

FUENTES = {
    "sans_css": '"Inter", "Helvetica Neue", Helvetica, Arial, sans-serif',
    "mono_css": '"JetBrains Mono", "SF Mono", Menlo, Consolas, "Courier New", monospace',
    "sans_pptx": "Arial",     # segura en macOS y Windows
    "mono_pptx": "Consolas",
}

W, H = 1280, 720
ML = 80                      # margen lateral
CW = W - 2 * ML              # ancho de contenido (1120)

# límites de palabras por tipo (texto visible, sin código ni pie/marcas)
LIMITE_PALABRAS = {
    "portada": 25, "seccion": 25, "titulo_visual": 32, "dato_grande": 32,
    "comparacion": 42, "codigo": 45, "fila": 42, "pregunta": 28, "pasos": 42,
}


def mezcla(hex_a, hex_b, p):
    """Mezcla hex_a con hex_b; p = fracción de hex_a (0..1)."""
    a = [int(hex_a[i:i + 2], 16) for i in (1, 3, 5)]
    b = [int(hex_b[i:i + 2], 16) for i in (1, 3, 5)]
    return "#%02X%02X%02X" % tuple(round(x * p + y * (1 - p)) for x, y in zip(a, b))


def tinte(nombre, p=0.13):
    """Versión muy clara de un color sobre el fondo."""
    return mezcla(COLORES[nombre], COLORES["bg"], p)


def color(nombre):
    """Acepta nombre de color del tema o un hex."""
    return COLORES.get(nombre, nombre)


def css_root():
    v = [f"  --{k.replace('_', '-')}: {c};" for k, c in COLORES.items()]
    for n in CAPAS + ["acento"]:
        v.append(f"  --{n}-tinte: {tinte(n)};")
    v.append(f"  --sans: {FUENTES['sans_css']};")
    v.append(f"  --mono: {FUENTES['mono_css']};")
    return ":root {\n" + "\n".join(v) + "\n}"
