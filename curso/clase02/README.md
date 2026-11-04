# Clase 2 · Cómo se lee big data y SQL en Snowflake (mié 4 nov)

Orden de trabajo en clase. Cada actividad tiene tres archivos: el enunciado, la verificación y la solución. Procedimiento para llevar el código de GitHub a Snowsight (Copy raw file y pegar en una hoja): ver [`../clase01/cuentas.md`](../clase01/cuentas.md).

## 1. Lab 1 · Primer SQL en Snowsight (TPC-H SF1)

1. **Lab** ([`lab1.sql`](lab1.sql)): pégalo en una hoja. Paso 0: selecciónalo y pulsa ▶. Ejercicios: bloque a bloque con Cmd/Ctrl+Enter.
2. **Verificación** ([`lab1_verificacion.sql`](lab1_verificacion.sql)): pégala en otra hoja y pulsa **Run All**. Meta: RESUMEN = OK y "6 de 6".
3. **Solución** ([`lab1_solucion.sql`](lab1_solucion.sql)): para contrastar después de intentarlo.

## 2. Lab 2 · Agregaciones y JOIN (TPC-H SF1, esquema `CURSO.LAB2`)

1. **Lab** ([`lab2.sql`](lab2.sql)): pégalo en una hoja. Paso 0: selecciona de `USE ROLE` a `USE SCHEMA CURSO.LAB2;` y pulsa ▶ (incluye `ALTER WAREHOUSE COMPUTE_WH SET AUTO_SUSPEND = 60`). Resuelve EJ1 a EJ6 (★), luego EJ7 y EJ8 (★★, el JOIN que duplica y su corrección). EJ9 y EJ10 son opcionales. Tiempo: 24 min.
2. **Verificación** ([`lab2_verificacion.sql`](lab2_verificacion.sql)): otra hoja, **Run All**. Meta: RESUMEN = OK y "6 de 6".
3. **Solución** ([`lab2_solucion.sql`](lab2_solucion.sql)): después de intentarlo.

## 3. Mini-caso · Negocio sobre TPC-H SF10 y lectura del Query Profile (esquema `CURSO.CASO`)

1. **Caso** ([`caso.sql`](caso.sql)): Paso 0 (selecciona hasta `ALTER SESSION SET USE_CACHED_RESULT = FALSE;`) y pulsa ▶. En clase: Q1 y Q4, y la lectura del perfil de Q4 (`SELECT * FROM Q4;` y abrir Query Profile). Después de clase: Q2 y Q3.
2. **Verificación** ([`caso_verificacion.sql`](caso_verificacion.sql)): otra hoja, **Run All**. Meta: RESUMEN = OK y "4 de 4". La lectura del perfil no se verifica.
3. **Solución y rúbrica** ([`caso_solucion.sql`](caso_solucion.sql)): vistas Q1 a Q4 y cifras de referencia del perfil de Q4.

## Errores comunes

| Síntoma | Causa | Cómo evitarlo |
|---|---|---|
| `This session does not have a current database` o el esquema no existe | No se corrió el Paso 0 en esa hoja | Selecciona del primer `USE ROLE` hasta la última línea del Paso 0 y pulsa ▶ |
| La verificación dice PENDIENTE y sí escribiste tu SELECT | El `CREATE OR REPLACE VIEW` falló | Busca el mensaje rojo en la hoja del lab |
| REVISAR con columnas distintas | El alias de salida no coincide | Compara TUS_COLUMNAS con COLUMNAS_ESPERADAS |
| Run All en el lab | Corre los ejemplos y el marcador de todos los ejercicios | Usa Cmd/Ctrl+Enter bloque a bloque; Run All solo en la verificación |
| No ves un archivo en tu fork | El fork no está al día | Sync fork > Update branch |

## Presentación y guion de demos

- **Presentación** ([`deck/slides.pdf`](deck/slides.pdf)): cómo se lee big data y qué resuelve Snowflake; el orden de las slides sigue esta lista de actividades.
- **Versión para proyectar (30 slides)** ([`deck_corto/slides.pdf`](deck_corto/slides.pdf)): mismos bloques y horarios; el deck de 64 queda como material de lectura.
- **Guion de demos** ([`demos.sql`](demos.sql)): consultas de las demos en vivo del instructor, con el resultado esperado de cada una.
