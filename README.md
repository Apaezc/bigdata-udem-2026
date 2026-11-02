# bigdata-udem-2026

Template del curso de Big Data de la UdeM.

<a id="que-vas-a-construir"></a>
## Qué vas a construir

Un **pipeline** (serie de pasos que toma datos crudos, los limpia y los deja listos para analizar) de punta a punta con SQL, PySpark, AWS y Snowflake. Procesa los viajes de Uber/Lyft de NYC (~20 M filas por mes) y publica en Snowflake una tabla de métricas diarias por zona y empresa. Lo despliegas en tu propia cuenta con Terraform y GitHub Actions, en tres **entornos** (dónde corre el código) con el mismo código y distinta configuración: **local** (tu Code Editor, gratis), **dev** (pruebas en AWS) y **prod** (producción).

<a id="quickstart-del-estudiante"></a>
## Empieza aquí: guía paso a paso

Haz los 14 pasos en orden.

| Parte | Pasos |
|---|---|
| [Antes de empezar](docs/guia.md#antes-de-empezar) | Cuentas, ventanas, tiempo y costo |
| [Parte 1 · Cuentas](docs/guia.md#parte-1) | [1 Snowflake](docs/guia.md#paso-1) · [2 AWS y cuotas](docs/guia.md#paso-2) · [3 Fork y Actions](docs/guia.md#paso-3) |
| [Parte 2 · Entorno de trabajo](docs/guia.md#parte-2) | [4 Bootstrap](docs/guia.md#paso-4) · [5 Code Editor](docs/guia.md#paso-5) · [6 Clonar](docs/guia.md#paso-6) · [7 Conectar Snowflake](docs/guia.md#paso-7) · [8 `make setup`](docs/guia.md#paso-8) · [9 Secrets y doctor](docs/guia.md#paso-9) |
| [Parte 3 · Infraestructura y datos](docs/guia.md#parte-3) | [10 `make deploy`](docs/guia.md#paso-10) · [11 Snowflake](docs/guia.md#paso-11) · [12 Datos](docs/guia.md#paso-12) |
| [Parte 4 · Desarrollar y publicar](docs/guia.md#parte-4) | [13 Local y dev](docs/guia.md#paso-13) · [14 Prod con un PR](docs/guia.md#paso-14) |
| [Glosario](docs/guia.md#glosario) | 30 términos |

<a id="studioconsoleurl"></a>
**Atajo `StudioConsoleUrl`:** ver el [Paso 5](docs/guia.md#paso-5).

<a id="apagar-y-encender-día-a-día"></a>
## Cada sesión: apagar y encender (día a día)

Al terminar cada sesión apaga lo que cuesta dinero; al volver, enciéndelo. Ver [Cada sesión](docs/cada-sesion.md): [Apagar](docs/cada-sesion.md#apagar) · [Encender](docs/cada-sesion.md#encender).

<a id="troubleshooting"></a>
## Problemas frecuentes (troubleshooting)

Busca tu mensaje de error con Ctrl+F en [Problemas frecuentes](docs/problemas.md). Lo avanzado o de instructor está en [Avanzado](docs/problemas.md#avanzado).

## Referencia

No hace falta leerla para empezar.

<a id="targets-de-make"></a>
- [Targets de `make`](docs/referencia.md#make): qué hace cada comando y en qué paso se usa.

<a id="costos-y-apagado"></a>
- [Costos y apagado](docs/referencia.md#costos): presupuesto, cobros y apagado.
- [Arquitectura](docs/referencia.md#arquitectura) · [Configuración por estudiante](docs/referencia.md#configuracion) · [Estructura del repositorio](docs/referencia.md#estructura) · [Para el instructor](docs/referencia.md#instructor).
- Otros documentos: [CONTRATO.md](CONTRATO.md), [docs/bootstrap.md](docs/bootstrap.md), [airflow/README.md](airflow/README.md), [infra/snowflake/README.md](infra/snowflake/README.md).
