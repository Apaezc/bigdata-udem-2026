# Clase 1 · Ingeniería de datos y arquitectura (mar 3 nov)

**Pregunta que atraviesa el curso:** ¿la lluvia cambia los viajes en NYC?
Hoy vemos qué sistema hace falta para responderla bien: qué es la ingeniería de datos, el data warehouse, el data lake y el lakehouse, la arquitectura medallion y la arquitectura del curso. En los intermedios creas tus cuentas.

## Material

1. **Presentación:** [`deck/slides.pdf`](deck/slides.pdf) (también en PowerPoint: [`deck/slides.pptx`](deck/slides.pptx), con notas del orador).
2. **Cuentas** ([`cuentas.md`](cuentas.md)): se crean en tres paradas durante la clase.
   - GitHub (fork del repositorio) y trial de Snowflake (AWS, US East Ohio).
   - Cuenta de AWS (registro *advanced*, MFA, región us-east-2) y tu semáforo de AWS.
3. **Formulario** ([`formulario.md`](formulario.md)): al cierre registras tu fork, tu región de Snowflake y tu semáforo. El enlace se comparte en el canal del curso.

El primer laboratorio de SQL está en [`../clase02/`](../clase02/) y se hace en la clase 2.

## Antes de empezar

- Ten a mano tu celular y una tarjeta de crédito o débito para la verificación de AWS.
- Si tu cuenta de AWS queda en verificación, no pasa nada: las clases 1 a 4 solo necesitan Snowflake.

## Si algo falla

- Errores de cuentas: tabla en [`cuentas.md`](cuentas.md).
- Más detalle: [docs/problemas.md](../../docs/problemas.md).

## Para el instructor

La presentación se genera desde `deck/slides.json` y `deck/diagramas/*.svg`:
`python3 curso/_deck/build.py curso/clase01/deck --clase 1` (requiere Google Chrome y `python-pptx`). El guion de cada slide está en sus notas del orador.
