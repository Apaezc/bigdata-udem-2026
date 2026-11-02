# Sistema de presentaciones (curso Big Data)

Una fuente por clase, tres salidas: `index.html`, `slides.pdf` y `slides.pptx` (+ `png/` para QA).

## Crear un deck
1. Crea `curso/claseNN/deck/slides.json` y, si usas diagramas, `curso/claseNN/deck/diagramas/*.svg`.
2. Ejecuta (desde cualquier carpeta; usa rutas completas):
   ```
   cd /Users/diegomanzur/Documents/udem/bigdata/bigdata-udem-2026/curso && python3 _deck/build.py clase01/deck
   ```
   Opciones: `--clase N` (si la ruta no contiene `claseNN`), `--sin-pdf`, `--sin-png`, `--sin-pptx`.
3. Revisa `png/slide-NN.png` y los avisos en stderr (límite de palabras por tipo, desbordes probables, sin notas).

`slides.json` es una lista de slides, o un objeto `{"clase": 1, "titulo": "...", "slides": [...]}`.
Campos comunes a todo tipo: `tipo`, `notas` (orador), `min` (duración), `aqui` (`"bronze"|"silver"|"gold"`: marca "estás aquí", arriba a la derecha).
En textos: `**negrita**` y `` `mono` ``.

## Tipos
| tipo | campos | límite palabras |
|---|---|---|
| `portada` | `titulo`, `subtitulo`, `meta` | 25 |
| `seccion` | `numero`, `etiqueta`, `pregunta` | 25 |
| `titulo_visual` | `titulo`, `diagrama` (ruta al SVG, relativa al deck), `alt`, `pie` | 32 |
| `dato_grande` | `cifra`, `contexto`, `fuente`, `capa` (opcional: color de la cifra) | 32 |
| `comparacion` | `titulo` + (`columnas`: 2-4 de `{titulo, items[], capa?}`) o (`tabla`: `{encabezados[], filas[[]]}`, máx. 6 filas) | 42 |
| `codigo` | `titulo`, `sql` (máx. 12 líneas, 78 car.), `resaltar` (líneas 1-based), `explicacion` | 45 (sin contar código) |
| `fila` | `titulo`, `tabla` (rótulo), `columnas`: `{nombre, valor, capa?, nota?}` (máx. 7) | 42 |
| `pregunta` | `pregunta`, `etiqueta`, `pista` (fondo acento, pantalla completa) | 28 |
| `pasos` | `titulo`, `ventana` (GitHub / Snowsight / Consola AWS), `pasos[]` (3-6 textos) | 42 |

Ejemplos de cada uno: `muestra/slides.json`.

```json
{"tipo": "fila", "titulo": "Una fila de bronze trae el desorden tal cual llegó", "tabla": "bronze.pedidos",
 "columnas": [{"nombre": "pedido_id", "valor": "A-10482"},
              {"nombre": "monto", "valor": "\"1,299.50\"", "capa": "silver", "nota": "Texto a número"}],
 "aqui": "bronze", "min": 3, "notas": "..."}
```

## Reglas de diseño
- Título de acción = frase completa que afirma algo (máx. ~18 palabras, 2 líneas).
- Colores de capa con significado fijo (bronze cobre, silver gris azulado, gold ocre); nunca los uses como decoración.
- Diagramas SVG: usa `viewBox` y la paleta de `tema.py`; texto de 22 px o más a tamaño 1:1 (ancho ideal 1120×440). Fuente `Helvetica Neue, Arial`.
- `tema.py` define colores/fuentes: HTML (variables CSS) y PPTX leen de ahí. Para cambiar la paleta edita solo ese archivo.

## Navegación del HTML
Flechas/espacio avanzan, `p` muestra notas del orador (modo presentador), `f` pantalla completa, `?solo=N` muestra solo la slide N, `#N` abre en la slide N. Imprimir a PDF desde el navegador da el mismo PDF (1280×720).

## Fuentes y PPTX
HTML: Inter → Helvetica Neue → Arial; código: JetBrains Mono → Menlo → Consolas. PPTX: Arial y Consolas (seguras en macOS/Windows). Los textos del PPTX son cuadros editables; los diagramas van como PNG a 2x; las notas van en las notas de PowerPoint.
Requisitos: Python 3 + python-pptx, Google Chrome en `/Applications/Google Chrome.app`.
