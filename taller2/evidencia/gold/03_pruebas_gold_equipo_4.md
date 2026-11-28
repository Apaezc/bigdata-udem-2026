# Evidencia 03 – Pruebas de calidad de Gold

**Fecha:** 28 de noviembre de 2026

**Archivo validado:** `tests/test_gold.py`

## Objetivo

Comprobar que la transformación Gold del equipo 4 cumple las reglas de calidad y que los resultados se generan correctamente según la estructura definida en el contrato del taller.

## Comando ejecutado

```bash
PYTHONPATH=src .venv/bin/python -m pytest -q tests/test_gold.py
```

## Resultado obtenido

```text
....... [100%]
7 passed in 33.30s
```

## Validaciones realizadas

- Registro de los viajes en los rangos corto, medio y largo.
- Cálculo correcto de la cantidad de viajes por rango.
- Cálculo de la distancia total y los ingresos.
- Conservación de la información de lluvia.
- Conservación de viajes sin información climática.
- Validación de la estructura de salida de la tabla Gold.

## Conclusión

Las siete pruebas del archivo `tests/test_gold.py` finalizaron satisfactoriamente en el entorno personal de AWS SageMaker.

La validación confirma que la transformación Gold cumple las condiciones comprobadas por las pruebas automatizadas.
