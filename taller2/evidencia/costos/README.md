Evidencias de costos de Snowflake y tiempos de ejecución de Glue.

##Validación local de tests/test_carga.py
**Fecha:** 28/11/2026
**Comando:**
PYTHONPATH=src .venv/bin/python -m pytest tests/test_carga.py -q
**Resultado:**
15 passed in 0.59s
**Estado:** Todas las pruebas de carga Snowflake aprobadas.

## Validación local de tests/test_carga.py
**Fecha:** 28/11/2026
**Comando:**
```bash
PYTHONPATH=src .venv/bin/python -m pytest tests/test_carga.py -q
```
**Resultado:**
```text
15 passed in 0.59s
```

**Estado:** Todas las pruebas de carga Snowflake aprobadas.

---

## Validación completa del proyecto
**Fecha:** 28/11/2026
**Entorno:** Cuenta personal de AWS – SageMaker Code Editor.
**Comando:**
```bash
PYTHONPATH=src .venv/bin/python -m pytest -q
```
**Resultado:**
```text
421 passed, 1 skipped in 239.81s (0:03:59)
```

**Estado:** Todas las pruebas ejecutadas fueron aprobadas. Una prueba fue omitida (skipped). No se presentaron fallos.


