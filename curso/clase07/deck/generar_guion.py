"""Genera guion.md (el guion del orador) a partir de slides.json.

Uso:  cd ~/bigdata/curso/clase07/deck && python3 generar_guion.py

Cada slide trae su título, su duración, la hora relativa de inicio y las notas del orador.
"""

import json
from pathlib import Path

AQUI = Path(__file__).parent
datos = json.loads((AQUI / "slides.json").read_text(encoding="utf-8"))
slides = datos["slides"]
total = sum(s.get("min", 1) for s in slides)

partes = [
    "# Clase 7 · Guion del orador",
    "",
    f"Lunes 23 de noviembre de 2026 · {total} min con descanso de 20 min · {len(slides)} slides.",
    "",
    "Cada slide trae el título en pantalla, su duración, la hora relativa de inicio y qué decir. "
    "Las cifras en dev (code_editor, límite 1000, mes 2024-01) son las del ensayo del 22 y 23 de noviembre, "
    "registradas en `validacion/contenido/clase07_medidas.md`; las celdas de Glue del dimensionamiento "
    "quedan pendientes de medir.",
    "",
]
acumulado = 0
for i, s in enumerate(slides, start=1):
    titulo = s.get("titulo") or s.get("pregunta") or s.get("etiqueta") or f"Slide {i}"
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
    acumulado += minutos
(AQUI / "guion.md").write_text("\n".join(partes), encoding="utf-8")
print(f"guion.md: {len(slides)} slides, {total} min")
