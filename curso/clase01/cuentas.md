# Clase 1 · Tus cuentas (70 min)

Hoy creas tres cuentas: **GitHub**, **Snowflake** y **AWS**. Cada parte es un resumen. El detalle completo está en la [guía](../../docs/guia.md) (más detalle, opcional).

**Trae:** tu celular y una tarjeta de crédito o débito para la verificación de AWS. <!-- VERIFICAR: tarjeta y celular vienen de F2 pensum v5 (clase 1); la guía no lo dice -->

**Marcadores de ventana:** 🌐 GitHub · ☁️ Consola AWS · ❄️ Snowsight · 🧭 Navegador

---

## Parte 1 · GitHub (15 min)

🌐 **GitHub**

**Paso 0 · Crea tu cuenta:** entra a github.com > **Sign up** y confirma tu correo.

1. Entra a tu cuenta de GitHub con el correo verificado.
2. Abre el repositorio del curso: https://github.com/Diegomanzur10/bigdata-udem-2026
3. Pulsa **Fork** (arriba a la derecha) > **Create fork**. Verás `github.com/TU-USUARIO/bigdata-udem-2026`: esa es tu copia personal.
4. En tu fork, abre la pestaña **Actions**.
5. Pulsa **"I understand my workflows, go ahead and enable them"**.

Más detalle (opcional): [Paso 3](../../docs/guia.md#paso-3)

**✅ Debes ver:** la pestaña **Actions** de tu fork con los workflows habilitados. <!-- VERIFICAR: la guía no define qué ver en el paso 3 -->

**❌ Si falla:** si no pulsas el botón del paso 5, los workflows de tu fork no corren. Revisa la tabla de errores comunes de abajo. Más detalle (opcional): [Paso 9](../../docs/guia.md#paso-9) (secrets).

---

## Parte 2 · Snowflake (20 min)

🧭 **Navegador**

1. Abre https://signup.snowflake.com/ y crea tu cuenta de prueba (*trial*).
2. Elige la nube **AWS**.
3. Elige la región **US East (Ohio)** (`us-east-2`).
4. Elige la edición **Enterprise**. <!-- VERIFICAR: edición Enterprise viene de F2 pensum v5; la guía paso 1 no la menciona -->
5. En el correo de activación pulsa el botón. Crea tu usuario y tu contraseña, guárdalos y guarda la URL de tu cuenta. <!-- VERIFICAR: activación por correo viene de F2 pensum v5; la guía no la menciona -->

❄️ **Snowsight**

6. Abre una hoja nueva: menú izquierdo **Projects > Worksheets** > botón **+** (SQL Worksheet). Si tu Snowsight muestra "Workspaces", usa **+ > SQL File**.
7. Pega `SELECT CURRENT_REGION();` en la hoja nueva y pulsa ▶ o Cmd/Ctrl+Enter. <!-- VERIFICAR: esta consulta no aparece en la guía; viene de F2 pensum v5 -->

Más detalle (opcional): [Paso 1](../../docs/guia.md#paso-1)

**✅ Debes ver:** `AWS_US_EAST_2` como resultado de `SELECT CURRENT_REGION();`. <!-- VERIFICAR: valor de F2 pensum v5; la guía solo lo muestra como salida de make setup -->

**❌ Si falla:** si la cuenta quedó en Azure, GCP u otra región, crea otra cuenta. Más detalle (opcional): [Snowflake fuera de AWS o de us-east-2](../../docs/problemas.md#p-sin-region-aws).

---

## Parte 3 · AWS (35 min)

☁️ **Consola AWS**

1. Abre el registro *advanced* de AWS: https://signin.aws.amazon.com/signup?request_type=register (no uses el registro de tipo *project*).
2. Completa el registro con tu correo, tu contraseña y tu tarjeta. AWS la pide para verificar identidad; el curso usa el plan gratuito y te enseña a apagar todo.
3. Completa la verificación por teléfono.
4. Activa MFA en tu usuario **root**.
5. Elige la región **US East (Ohio)** (`us-east-2`). Trabaja siempre en `us-east-2`.
6. Espera el correo de AWS que confirma la verificación.

**Qué significa cada término:**
- **root**: el usuario dueño de la cuenta.
- **MFA**: segundo factor de verificación: una app como Google Authenticator o Microsoft Authenticator genera un código extra al entrar.
- **región**: el centro de datos donde vive todo; `us-east-2` = Ohio.

Más detalle (opcional): [Paso 2.1](../../docs/guia.md#paso-2-1)

**✅ Debes ver:** tu cuenta creada, con MFA activo en root y la región `us-east-2`. <!-- VERIFICAR: la guía no define una señal de éxito para el paso 2.1 -->

**❌ Si falla:** consulta la tabla de errores comunes de abajo.

---

## Llevar el código de GitHub a Snowsight

Así llega el código del curso a tu hoja de Snowflake. Lo haces en el lab 1 (bloque 9).

1. 🌐 En tu fork, entra a `curso/clase02/lab1.sql` y pulsa **Copy raw file** (el ícono de dos cuadritos, arriba a la derecha del contenido, no la flecha hacia abajo). Si no ves el archivo: botón **Sync fork** > **Update branch**.
2. ❄️ En Snowsight: menú izquierdo **Projects > Worksheets** > botón **+** (SQL Worksheet). Si tu Snowsight muestra "Workspaces", usa **+ > SQL File**.
3. Pega todo (Ctrl+V o Cmd+V). No elijas rol ni warehouse: el Paso 0 del archivo lo hace por ti.
4. Selecciona desde `USE ROLE` hasta `USE SCHEMA CURSO.LAB1;` y pulsa ▶. No uses Run All en este archivo.
5. Corre los ejercicios bloque a bloque con Ctrl/Cmd+Enter.

---

## Errores comunes

| Problema | Qué hacer | Cómo evitarlo |
|---|---|---|
| Tarjeta rechazada en AWS | Usa otra tarjeta, o autoriza el cargo de AWS con tu banco. | Ten la tarjeta lista antes del paso 2 de AWS. Si sigue fallando, avisa al instructor y reintenta en la clase 2. |
| Falla la verificación por teléfono en AWS | Revisa que el número esté bien escrito y reintenta con el celular a mano. | Ten el celular a mano. Si sigue fallando, avisa al instructor y reintenta en la clase 2. |
| Trial creado en Azure, GCP u otra región | Crea otra cuenta de Snowflake eligiendo **AWS** y **US East (Ohio)**. | Elige **AWS** y **US East (Ohio)** en el paso 2 de Snowflake. Más detalle (opcional): [problemas](../../docs/problemas.md#p-sin-region-aws). |
| No llega el correo de activación de Snowflake | Revisa la carpeta de spam y promociones. | Usa un correo al que tengas acceso. Si no llega, avisa al instructor. |
| AWS dice que la cuenta está en verificación | Espera el correo de AWS. No intentes CloudShell todavía. | Más detalle (opcional): [problemas](../../docs/problemas.md#p-cloudshell-verificacion). |
| Fork sin Actions habilitado | Pulsa **"I understand my workflows, go ahead and enable them"** en la pestaña **Actions** de tu fork. | Hazlo justo después de crear el fork. Más detalle (opcional): [Paso 3](../../docs/guia.md#paso-3). |

---

## Cuotas: se piden después

**Hoy solo si tu cuenta de AWS ya está verificada (bloque 7). Si no, se hace en la clase 2.**

Hoy casi nunca se pueden pedir las cuotas. La cuenta de AWS queda en verificación y CloudShell aparece bloqueado. Por eso las cuotas se piden en la **clase 2** o apenas llegue el correo de verificación de AWS.

- Más detalle (opcional): [Paso 2.2 · Revisa las cuotas](../../docs/guia.md#paso-2-2)
- Más detalle (opcional): [Paso 2.3 · Pide las cuotas que falten](../../docs/guia.md#paso-2-3)

Si AWS te avisa que tu cuenta está verificada, pide las cuotas. Son unos 5 minutos.

---

## Después de clase: tu semáforo de AWS

Tu instructor revisa tu color en el formulario de la clase 1 (bloque 11). Este es tu estado y qué sigue.

| Color | Estado | Qué sigue |
|---|---|---|
| Rojo | Cuenta creada, en verificación | Nada en AWS. Sigue con el lab de SQL. |
| Amarillo | Cuenta verificada; cuotas por pedir o pendientes | Revisa el estado de las cuotas en [Paso 2.3](../../docs/guia.md#paso-2-3) (más detalle, opcional). Si sigue pendiente, responde en el caso de soporte. |
| Verde claro | Cuotas aprobadas y bootstrap hecho | Sigue con los [pasos 5 a 9](../../docs/guia.md#paso-5) de la guía (más detalle, opcional). |
| Verde | Pasos 5 a 12 completos | Haz los retos ★★. |

**Regla:** si no tienes tu bloque de AWS listo, no pierdes contenido.

**Aclara:** primero termina los 6 ★ del lab; luego los ★★.
