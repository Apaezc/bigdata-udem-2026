# Apagar y encender (día a día)

Esta página es para cada sesión: al terminar, [apagas](#apagar); al volver, [enciendes](#encender).

<a id="antes-de-apagar"></a>
## Antes de apagar

Lo que cuesta mientras está encendido es el **Code Editor** y la **VM de Airflow de prod** (cifras en [Tiempo y costo](guia.md#tiempo-y-costo)). Glue y Snowflake solo cobran mientras corren un job o una consulta y se detienen solos.

> [!NOTE]
> Tus archivos (`~/bigdata`, `~/.snowflake`, `.env`) se conservan: viven en el disco del Space, no en la instancia.

<a id="apagar"></a>
## Apagar

Al terminar cada sesión apaga en este orden. Los pasos 1 a 3 van en la terminal del Code Editor; el 4, en la consola de AWS.

<a id="apagar-1"></a>
### 1 · Airflow de prod (VM)

💻 **Terminal del Code Editor**

1. Si tienes el túnel abierto, ciérralo con **Ctrl+C** en esa terminal.
2. Ejecuta: <!-- AUTOR: confirmar si `make airflow-off` va en la misma terminal del túnel tras Ctrl+C o en una nueva (duda F30) -->
   ```bash
   cd ~/bigdata
   make airflow-off
   ```

**✅ Debes ver:**
```text
==> Apagando instancia i-0123456789abcdef0 (estado actual: running)
==> Instancia apagada.
```

> [!NOTE]
> Si ya estaba apagada verás `==> La instancia ... ya está apagada.`. Aunque lo olvides, se apaga sola a las 23:00 (hora de Bogotá).

<a id="apagar-2"></a>
### 2 · Airflow de dev

💻 **Terminal del Code Editor**

1. Ejecuta:
   ```bash
   cd ~/bigdata
   make airflow-local-down
   ```

**✅ Debes ver:** `==> Airflow local y nginx detenidos.`

<a id="apagar-3"></a>
### 3 · Comprueba que no quede nada corriendo

💻 **Terminal del Code Editor**

1. Ejecuta:
   ```bash
   cd ~/bigdata
   make estado
   ```

**✅ Debes ver:** (fechas, montos y créditos serán los tuyos), con todo apagado:
```text
==> Airflow
  Estado:        stopped                       <- debe decir stopped
  Acceso:        make airflow-tunel (túnel SSM desde el Code Editor)
==> Últimos 3 job runs de Glue
  bigdata-medium     SUCCEEDED    2026-11-02T05:52:53+00:00   <- ninguno en RUNNING
  bigdata-medium     SUCCEEDED    2026-11-02T05:51:04+00:00
  bigdata-small      SUCCEEDED    2026-11-02T05:50:11+00:00
==> Warehouse de Snowflake
  BIGDATA_WH: estado=SUSPENDED tamaño=X-Small auto_suspend=60s   <- SUSPENDED
==> Costos y créditos
  Plan: FREE (ACTIVE)  créditos restantes: 196.58 USD
  Budget                       Límite    Unidad     Gasto real   Previsto
  bigdata-mensual              50.0       USD        0.812        None
  bigdata-total                50.0       USD        0.812        None
```

**❌ Si falla:** el warehouse dice `STARTED` → [espera un minuto](problemas.md#p-warehouse-started).

<a id="apagar-4"></a>
### 4 · Code Editor (lo último)

☁️ **Consola AWS** (pestaña **Studio**, no la del Code Editor)

> [!IMPORTANT]
> Hazlo al final: al apagar el Space se cierra tu terminal.

1. En el menú izquierdo, abre **Code Editor**.
2. En la lista de Spaces, en la fila `dev`, pulsa **Stop**.

**✅ Debes ver:** el estado pasa a `Stopping` y luego a `Stopped` (~1 min).

> [!NOTE]
> Si lo olvidas, se apaga solo tras 60 minutos de inactividad.

<a id="encender"></a>
## Encender

<a id="encender-1"></a>
### 1 · Abre el Code Editor

☁️ **Consola AWS**

1. Abre **Amazon SageMaker AI > Domains** > tu dominio > **User profiles** > `estudiante` > **Launch > Studio**.

☁️ **Consola AWS** (pestaña **Studio**)

2. Abre **Code Editor** > Space `dev` > **Run space** (~2 min) > **Open**.

💻 **Terminal del Code Editor**

3. Abre una terminal: **Terminal > New Terminal**. <!-- AUTOR: ✅ de Encender 1: qué debe ver al abrir el Code Editor (no está en el original) -->

**❌ Si falla:** el explorador de la izquierda dice `No folder opened` → [abre la carpeta](problemas.md#p-explorador-sin-carpeta).

<a id="encender-2"></a>
### 2 · Trae los últimos cambios del repo

💻 **Terminal del Code Editor**

1. Ejecuta: <!-- AUTOR: qué hacer si `git pull` reporta cambios locales o un conflicto (duda 15 de la propuesta) -->
   ```bash
   cd ~/bigdata
   git pull
   ```

<a id="encender-3"></a>
### 3 · Airflow de dev (cuando lo necesites)

💻 **Terminal del Code Editor**

1. Ejecuta:
   ```bash
   cd ~/bigdata
   make airflow-local
   ```

**✅ Debes ver:** al final, `UI: https://...studio.us-east-2.sagemaker.aws/codeeditor/default/ports/8080/`, usuario `admin` y la contraseña.

> [!NOTE]
> Tarda ~1 min. La instalación solo ocurre la primera vez y tarda unos minutos.

<a id="encender-4"></a>
### 4 · Airflow de prod (cuando lo necesites)

💻 **Terminal del Code Editor**

> [!IMPORTANT]
> No puede estar encendido a la vez que el de dev: los dos usan el puerto 8080.

1. Ejecuta:
   ```bash
   cd ~/bigdata
   make airflow-local-down
   make airflow-on
   make airflow-password
   make airflow-tunel
   ```
2. Espera 2 minutos.
3. Abre la URL que imprime `make airflow-tunel`. Deja esa terminal abierta: el túnel la ocupa. Para seguir trabajando, abre otra con **Terminal > New Terminal**.

**✅ Debes ver:** `make airflow-on` termina con `==> Airflow de prod encendido (Airflow tarda ~2 min en responder).` `make airflow-password` imprime `Usuario:    admin` y `Contraseña: <...>`.

**❌ Si falla:** la página da error → [recárgala al minuto](problemas.md#p-airflow-pagina-error).

> [!NOTE]
> Un merge a `main` que cambie `airflow/` o `src/` también enciende la VM de prod (Deploy).

<a id="errores-al-encender"></a>
## Errores al apagar y encender

Cada mensaje tiene su entrada completa, con causa y solución, en los [problemas frecuentes](problemas.md).

| Mensaje | Entrada |
|---|---|
| `El puerto 8080 está ocupado (¿Airflow de dev encendido?)` | [p-puerto-8080](problemas.md#p-puerto-8080) |
| `La instancia está 'stopped'. Ejecuta 'make airflow-on' primero.` | [p-vm-stopped](problemas.md#p-vm-stopped) |
| `No existe la instancia bigdata-airflow` | [p-vm-inexistente](problemas.md#p-vm-inexistente) |
| `AccessDenied` al encender la VM o lanzar Glue | [p-accessdenied-presupuesto](problemas.md#p-accessdenied-presupuesto) |
