# Diagrama de la estrella · Taller 1

Equipo: <nombres>

Grano (el mismo de la primera línea de `01_estrella.sql`): <una fila por ... >

Reemplaza el diagrama de abajo por el de tu estrella: una tabla de hechos al centro y al menos dos
dimensiones, cada una con su clave. GitHub dibuja el bloque `mermaid` al abrir este archivo. Si
prefieres una imagen, súbela como `diagrama.png` a esta carpeta y deja aquí un enlace a ella.

```mermaid
erDiagram
    DIM_FECHA   ||--o{ FACT_VIAJES_DIA : "FECHA"
    DIM_ZONA    ||--o{ FACT_VIAJES_DIA : "ZONA_KEY"
    DIM_EMPRESA ||--o{ FACT_VIAJES_DIA : "EMPRESA_KEY"

    FACT_VIAJES_DIA {
        date    FECHA
        number  ZONA_KEY
        number  EMPRESA_KEY
        number  VIAJES
        float   INGRESO_TOTAL
    }
    DIM_FECHA {
        date    FECHA PK
    }
    DIM_ZONA {
        number  ZONA_KEY PK
    }
    DIM_EMPRESA {
        number  EMPRESA_KEY PK
    }
```

## Claves

| Dimensión | Clave | Por qué es única |
|---|---|---|
| DIM_FECHA | <...> | <...> |
| DIM_ZONA | <...> | <...> |
| DIM_EMPRESA | <...> | <...> |
