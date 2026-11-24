# Clase 8 · Qué completas en tu pipeline y cómo lo llevas a prod

Martes 24 de noviembre de 2026 · 109 min · 51 slides.

- `deck/`: `slides.json` (la fuente), `guion.md` (guion del orador), `index.html`, `slides.pdf` y `slides.pptx`.
  Se regeneran con `cd ~/bigdata/curso && python3 _deck/build.py clase08/deck`.
- Primera parte (slides 1 a 21): qué debe revisar, completar, modificar y crear cada equipo.
- Segunda parte (slides 22 a 51): del dev a prod, con las cifras medidas en el ensayo del 24 de noviembre
  (mes 2024-01, `glue_medium`, `todos`): bronze 19.663.930; silver 19.650.023; gold 744 filas y
  19.650.023 viajes; Snowflake con las mismas 744 filas.
  Incluye (slides 40 a 44) dónde se elige el cómputo, la comparación `glue_small`/`glue_medium`/`glue_large` y la
  duplicación en prod: tras reprocesar sin deduplicar, `SUM(VIAJES)` en Snowflake pasa de 19.650.023 a 157.200.184 (×8).

Antes de empezar, todo el equipo corre `cd ~/bigdata && git switch main && git pull && make migrar-clase07`.
