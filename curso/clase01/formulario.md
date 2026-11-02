# Formulario de perfil · Clase 1

Para cargar en Google Forms. Bloque 11 de la clase (15 min). Es formativo: no es una nota. Sirve para armar equipos (clase 4) y para el semáforo de AWS.

## Configuración en Google Forms

- Título: **Perfil del curso Big Data · Clase 1**.
- Descripción: "Responde en 5 minutos. Tus respuestas sirven para armar equipos. No es una nota."
- Recopilar correo: **sí**.
- Permitir editar respuestas: **sí** (para que corrijan el usuario de GitHub o la URL del fork).
- Todas las preguntas son de respuesta obligatoria, salvo donde se indique.

Leyenda de cada pregunta: **tipo** de pregunta en Forms, y **obligatoria** (Sí / No).

---

## Sección A · Datos básicos

**P1. Nombre completo**
- Tipo: respuesta corta.
- Obligatoria: Sí.

**P2. Correo de contacto**
- Tipo: respuesta corta. Validación: formato de correo.
- Obligatoria: Sí.
- Nota: puede ser distinto del correo de Snowflake.

**P3. Usuario de GitHub**
- Tipo: respuesta corta.
- Obligatoria: Sí.
- Descripción: "Solo el usuario, sin @ ni espacios. Ejemplo: `mi-usuario`."

**P4. URL de tu fork de `bigdata-udem-2026`**
- Tipo: respuesta corta. Validación: texto que empieza con `https://github.com/` y contiene `bigdata-udem-2026`.
- Obligatoria: Sí.
- Descripción: "Copia la dirección de la barra del navegador en la página de tu fork."

**P5. Resultado de `SELECT CURRENT_REGION();`**
- Tipo: respuesta corta.
- Obligatoria: Sí.
- Descripción: "Lo que te devolvió Snowflake al ejecutar la consulta. Debería decir `AWS_US_EAST_2`. Si dice otra cosa, escribe lo que salió tal cual."

---

## Sección B · Autoevaluación (0 a 3)

Escala común para las preguntas P6 a P9. Cada pregunta es de opción múltiple, una sola respuesta, obligatoria.

- **0** = Nunca lo he usado.
- **1** = Lo he visto o copiado, pero no lo hago solo.
- **2** = Lo hago con ejemplos o documentación a la mano.
- **3** = Lo hago sin ayuda y sé buscar el error cuando falla.

**P6. SQL**
- Tipo: opción múltiple. Obligatoria: Sí.
- Descripción: "Ejemplos de cada nivel: 1 = copiaste un SELECT y lo ejecutaste. 2 = escribes SELECT con WHERE, GROUP BY y JOIN con un ejemplo a la mano. 3 = escribes JOINs, subconsultas o funciones de ventana sin ayuda."
- Opciones:
  - 0 · Nunca lo he usado.
  - 1 · Lo he visto o copiado, pero no lo hago solo.
  - 2 · Lo hago con ejemplos o documentación a la mano.
  - 3 · Lo hago sin ayuda y sé buscar el error cuando falla.

**P7. Python**
- Tipo: opción múltiple. Obligatoria: Sí.
- Descripción: "Ejemplos: 1 = ejecutaste un script que alguien te pasó. 2 = escribes funciones simples con un ejemplo a la mano. 3 = escribes funciones, listas, diccionarios y tablas (pandas) sin ayuda."
- Opciones: las mismas cuatro de la escala común.

**P8. Terminal (línea de comandos)**
- Tipo: opción múltiple. Obligatoria: Sí.
- Descripción: "Ejemplos: 1 = abriste la terminal y usaste `cd` y `ls`. 2 = instalas paquetes y ejecutas scripts con guía. 3 = usas variables de entorno, `make` o scripts sin ayuda. No se usa en las clases 1 a 4."
- Opciones: las mismas cuatro de la escala común.

**P9. Git y GitHub**
- Tipo: opción múltiple. Obligatoria: Sí.
- Descripción: "Ejemplos: 1 = subiste o editaste un archivo desde la web de GitHub. 2 = clonas, haces commit y push con guía. 3 = trabajas con ramas, Pull Requests y resuelves conflictos."
- Opciones: las mismas cuatro de la escala común.

---

## Sección C · Rol preferido en los talleres

**P10. ¿Qué rol te gustaría hacer en los talleres?**
- Tipo: opción múltiple. Obligatoria: Sí.
- Descripción: "Los roles rotan entre el Taller 1 y el Taller 2. Todos los roles se hacen en pareja: uno técnico y uno no técnico."
- Opciones:
  - **Analista de negocio / cumplimiento**: hace las preguntas, define los términos, valida resultados, escribe el memo y presenta. Rol natural para perfiles legales.
  - **Modelador SQL**: diseña la estrella, escribe consultas y cuida que el grano sea coherente.
  - **Ingeniero de datos**: carga datos, escribe el código y las pruebas.
  - **Operador cloud y calidad**: cuida la cuenta del anfitrión, la integración continua (CI), los costos y la evidencia.

---

## Sección D · Disponibilidad fuera de clase

**P11. ¿Cuándo puedes trabajar fuera de clase? (marca todas las que apliquen)**
- Tipo: casillas (selección múltiple). Obligatoria: Sí.
- Opciones:
  - Entre semana, en la mañana.
  - Entre semana, en la tarde.
  - Entre semana, en la noche.
  - Fin de semana.
  - No puedo fuera de clase (solo en clase).

**P12. ¿Cuántas horas por semana podrías dedicar a los talleres?**
- Tipo: opción múltiple. Obligatoria: Sí.
- Opciones:
  - Menos de 2 horas.
  - De 2 a 4 horas.
  - De 4 a 6 horas.
  - Más de 6 horas.
- Descripción: "Es una estimación. Los talleres piden como máximo unas 3 horas de equipo en el T1 y 6 en el T2."

---

## Sección E · Semáforo de AWS

**P13. ¿En qué color estás con AWS hoy?**
- Tipo: opción múltiple. Obligatoria: Sí.
- Descripción: "Elige el color que describe hoy tu cuenta. El semáforo cambia; nadie se queda fuera del contenido."
- Opciones:
  - **Rojo**: cuenta creada, en verificación. Hoy no haces nada en AWS. Sigues con el lab de SQL.
  - **Amarillo**: cuenta verificada; cuotas por pedir o pendientes. Revisas el estado de las cuotas. Si sigue pendiente, abres o actualizas el caso de soporte con la plantilla.
  - **Verde claro**: cuotas aprobadas, bootstrap hecho. Sigues con los pasos 5 a 9 en el bloque de AWS.
  - **Verde**: pasos 5 a 12 completos (`make doctor` y `make estado` en verde). Ayudas a otra persona o haces retos ★★.
- Nota para el instructor: si la persona no creó la cuenta de AWS, debe elegir **Rojo**. Anota el motivo en P14.

**P14. Si no creaste tu cuenta de AWS o no eres verde, ¿qué te está frenando?**
- Tipo: párrafo. Obligatoria: No.
- Descripción: "Por ejemplo: la tarjeta fue rechazada, no te llega el código de verificación, o todavía no empezaste."

---

## Nota de cierre en el formulario

Mensaje al enviar: "Gracias. Si cambias algo, puedes editar tu respuesta con el mismo enlace."
