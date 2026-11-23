# Clase 7 · Los 40 títulos de la versión corta

Léelos de corrido: juntos cuentan la clase entera.

1. Big Data e Ingeniería de Datos
2. ¿Cómo construyo un pipeline en dev, lo llevo a prod sin duplicar nada y sé cuánto cómputo necesita?
3. Hoy construimos y probamos un pipeline en dev; en la clase 8 lo llevamos a prod
4. Antes de construir, cinco cosas de las clases 5 y 6 cambian
5. Antes de seguir, compruebas que tu migración quedó bien
6. Dev y prod no comparten carpetas ni esquemas, y dónde corres decide el entorno
7. Para correr solo cambias pipeline.yaml, y el entorno no aparece porque es automático
8. Ese mismo paso corre desde un notebook, con make o en Airflow, y solo cambia dónde se calcula
9. Para medir sin restos, empezamos limpios con resetear_entorno, que borra solo dev
10. Enciendes Airflow, lanzas resetear_entorno para listar y luego para borrar dev
11. Con dev limpio, construimos las funciones en el Notebook 1, con 1 000 viajes
12. Copias el notebook y apagas Airflow para ejecutar las Celdas 1 a 8
13. Para no duplicar, cada paso consulta una tabla de control, y la puerta tiene tres casos
14. La puerta se construye con debe_ingestar y con registrar_ingesta, que anota solo después de escribir
15. Bronze corre dos veces: registra y salta
16. Silver limpia, gold agrupa por fecha, barrio y franja y divide las sumas, y Snowflake recibe la tabla
17. La Celda 35 dice qué cambiaste frente a los .py y la 36 corre las pruebas del equipo
18. Abre bronze.py y silver.py: es la misma función del notebook
19. Copias tu cambio al .py, corres make test y reseteas dev antes de las tareas del DAG
20. Si el pipeline corre dos veces y todo sale en verde, ¿cómo sé que no duplicó nada?
21. Ahora corremos las tareas del DAG una por una, con Athena entre cada una
22. Preparas la terminal y lanzas una sola tarea con airflow tasks test, cada vez con otra fecha
23. Corres tres tareas y lees cada cierre
24. Para ver qué dejó cada tarea, declaras siete tablas en Athena
25. El primer punto de control muestra un lote de 1 000 filas, pero sin huella ni lote
26. Antes del DAG completo, ejecutas en Snowsight el CREATE TABLE: el código nunca crea la tabla
27. Con el DAG completo tres tareas saltan, y tras resetear las cuatro registran
28. Reprocesar exige todo el DAG marcado, porque la puerta protege cada capa
29. En gold, 1 000 viajes reales aparecen como 8 000, y Snowflake carga esa cifra inflada
30. Sin deduplicar, cada reproceso multiplica silver por N y gold por N al cubo
31. Sin huella ni siquiera podemos detectar el duplicado, y por eso los metadatos van primero
32. La tabla de control guarda cada corrida: se concilia con el último registro
33. Ahora continuamos con make correr y el dimensionamiento: cuánto cómputo necesita el pipeline
34. Con make -n ves lo que hará make correr, lo corres con glue_small y mides el tiempo
35. Primera parte: con 1 000 y 100 000 filas, ¿conviene Glue?
36. Segunda parte: con todos los viajes, ¿ayudan más workers?
37. Qué mirar en la tabla: arranque, límite y workers
38. En la clase 8 llevamos esto a prod por PR, CI/CD y la VM, y lo validamos
39. Hoy construiste y comprobaste un pipeline en dev, y en el Taller tu equipo escribe cuatro piezas
40. Si alguien reprocesa un mes en prod, ¿qué función de tu equipo evita que silver se duplique?
