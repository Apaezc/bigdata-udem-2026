# Clase 8 · Qué completas en tu pipeline y cómo lo llevas a prod

Martes 24 de noviembre de 2026 · 94 min · 45 slides.

- `deck/`: `slides.json` (la fuente), `guion.md` (guion del orador), `index.html`, `slides.pdf` y `slides.pptx`.
  Se regeneran con `cd ~/bigdata/curso && python3 _deck/build.py clase08/deck`.
- Primera parte (slides 1 a 20): qué debe revisar, completar, modificar y crear cada equipo.
- Segunda parte (slides 21 a 45): del dev a prod, con las cifras medidas en el ensayo del 24 de noviembre
  (mes 2024-01, `glue_medium`, `todos`): bronze 19.663.930; silver 19.650.023; gold 744 filas y
  19.650.023 viajes; Snowflake con las mismas 744 filas.

Antes de empezar, todo el equipo corre `cd ~/bigdata && git switch main && git pull && make migrar-clase07`.
