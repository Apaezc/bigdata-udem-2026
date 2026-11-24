"""Genera guion.md (el guion del orador) a partir de slides.json.

Uso:  cd ~/bigdata/curso/clase08/deck && python3 generar_guion.py

Cada slide trae su título, su duración, la hora relativa de inicio y las notas del orador.
"""

import json
from pathlib import Path

AQUI = Path(__file__).parent
slides = json.loads((AQUI / "slides.json").read_text(encoding="utf-8"))["slides"]
total = sum(s.get("min", 1) for s in slides)

partes = [
    "# Clase 8 · Guion del orador",
    "",
    f"Martes 24 de noviembre de 2026 · {total} min · {len(slides)} slides.",
    "",
    "Cada slide trae el título en pantalla, su duración, la hora relativa de inicio y qué decir. "
    "Las cifras de la primera parte (bronze 1000/265/31, silver 1000 y gold de 5 filas; tras "
    "reprocesar sin deduplicar, silver 2000/530/62 y gold lee 8000) son las del ensayo de la clase 7; "
    "las de «bien hecho» son la consecuencia esperada y se confirman en clase. Las de la segunda "
    "parte (bronze 19.663.930; silver 19.650.023, con 13.907 descartados; gold 744 filas y "
    "19.650.023 viajes; Snowflake 744 filas) y los tiempos (checks ~2 min, make actualizar-vm ~8 min "
    "la primera vez y ~1 min después, un job de Glue de gold ~16 min de reloj con 76 s de ejecución) "
    "son las medidas del ensayo en prod del 24 de noviembre, mes 2024-01.",
    "",
]
acumulado = 0
for i, s in enumerate(slides, start=1):
    titulo = s.get("titulo") or s.get("pregunta") or s.get("etiqueta") or f"Slide {i}"
    minutos = s.get("min", 1)
    partes += [
        f"## {i}. {titulo}",
        "",
        f"*{minutos} min · inicia en {acumulado // 60}:{acumulado % 60:02d}*",
        "",
        s.get("notas", ""),
        "",
    ]
    acumulado += minutos
(AQUI / "guion.md").write_text("\n".join(partes), encoding="utf-8")
print(f"guion.md: {len(slides)} slides, {total} min")
