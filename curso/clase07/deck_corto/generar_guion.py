"""Genera guion.md (el guion del orador) y titulos.md (solo los títulos) de la versión corta.

Uso:  cd ~/bigdata/curso/clase07/deck_corto && python3 generar_guion.py

Cada slide trae su título, su duración, la hora relativa de inicio y las notas del orador.
titulos.md sirve para leer el hilo: los 40 títulos, de corrido, deben contar la clase entera.
"""

import json
from pathlib import Path

AQUI = Path(__file__).parent
datos = json.loads((AQUI / "slides.json").read_text(encoding="utf-8"))
slides = datos["slides"]
total = sum(s.get("min", 1) for s in slides)


def titulo_de(s, i):
    return s.get("titulo") or s.get("pregunta") or s.get("etiqueta") or f"Slide {i}"


partes = [
    "# Clase 7 · Guion del orador (versión corta)",
    "",
    f"Lunes 23 de noviembre de 2026 · {total} min con descanso de 20 min · {len(slides)} slides.",
    "",
    "Es la versión de 40 slides de `curso/clase07/deck/`: mismos temas, mismo orden y mismos diagramas, con las "
    "instrucciones condensadas (lo que no cabe en la slide está en estas notas). Cada título es una frase que "
    "continúa la anterior. Las cifras en dev (code_editor, límite 1000, mes 2024-01) son las del ensayo del 22 y 23 "
    "de noviembre, registradas en `validacion/contenido/clase07_medidas.md`; las celdas de Glue del dimensionamiento "
    "quedan pendientes de medir.",
    "",
]
titulos = [
    "# Clase 7 · Los 40 títulos de la versión corta",
    "",
    "Léelos de corrido: juntos cuentan la clase entera.",
    "",
]
acumulado = 0
for i, s in enumerate(slides, start=1):
    titulo = titulo_de(s, i)
    minutos = s.get("min", 1)
    inicio = f"{acumulado // 60}:{acumulado % 60:02d}"
    partes += [
        f"## {i}. {titulo}",
        "",
        f"*{minutos} min · inicia en {inicio}*",
        "",
        s.get("notas", ""),
        "",
    ]
    titulos.append(f"{i}. {titulo}")
    acumulado += minutos
(AQUI / "guion.md").write_text("\n".join(partes), encoding="utf-8")
(AQUI / "titulos.md").write_text("\n".join(titulos) + "\n", encoding="utf-8")
print(f"guion.md: {len(slides)} slides, {total} min · titulos.md")
