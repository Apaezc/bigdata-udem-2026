# Clase 7 · Los 40 títulos de la versión corta

Léelos de corrido: juntos cuentan la clase entera.

1. Big Data e Ingeniería de Datos
2. ¿Cómo construyo un pipeline en dev, lo llevo a prod sin duplicar nada y sé cuánto cómputo necesita?
3. Hoy construimos un pipeline de cuatro pasos, lo probamos en dev y lo llevamos a prod
4. Antes de construir, cinco cosas de las clases 5 y 6 cambian
5. Antes de seguir, compruebas que tu migración quedó bien
6. Dev y prod no comparten carpetas ni esquemas, y el entorno lo decide dónde corres
7. Para correr solo cambias pipeline.yaml, y el entorno no aparece porque es automático
8. Ese mismo paso corre desde un notebook, con make o en Airflow, y solo cambia dónde se calcula
9. Para medir sin restos, empezamos limpios con resetear_entorno, que borra solo dev
10. Enciendes Airflow, lanzas resetear_entorno para listar y luego para borrar dev
11. Con dev limpio, construimos las funciones en el Notebook 1, con 1 000 viajes
12. Copias los notebooks y apagas Airflow para ejecutar las Celdas 1 a 7
13. Para no duplicar, cada paso consulta una tabla de control, y la puerta tiene tres casos
14. La puerta se construye con debe_ingestar y con registrar_ingesta, que anota solo después de escribir
15. Bronze corre dos veces: registra y salta
16. Silver limpia, gold agrupa por fecha, barrio y franja y divide las sumas, y Snowflake recibe la tabla
17. Como el notebook escribió de verdad, reseteas dev y pasamos al Notebook 2
18. En el Notebook 2, agregar_metadatos y deduplicar viven en los .py y hoy no hacen nada
19. Cierras el Notebook 2 y corres make test
20. Si el pipeline corre dos veces y todo sale en verde, ¿cómo sé que no duplicó nada?
21. Ahora corremos las tareas del DAG una por una, con Athena entre cada una
22. Preparas la terminal y lanzas una sola tarea con airflow tasks test, cada vez con otra fecha
23. Corres tres tareas y lees cada cierre
24. Para ver qué dejó cada tarea, declaras siete tablas en Athena
25. El primer punto de control muestra un lote de 1 000 filas, pero sin huella ni lote
26. Con el DAG completo sin reprocesar, tres tareas saltan y solo carga Snowflake
27. Reseteas dev y corres todo una vez: con un lote, todo cuadra
28. Reprocesar exige todo el DAG marcado, porque la puerta protege cada capa
29. En gold, 1 000 viajes reales aparecen como 8 000, y Snowflake carga esa cifra inflada
30. Sin deduplicar, cada reproceso multiplica silver por N y gold por N al cubo
31. Sin huella ni siquiera podemos detectar el duplicado, y por eso los metadatos van primero
32. Ahora continuamos con make correr y el dimensionamiento: cuánto cómputo necesita el pipeline
33. Con make -n ves lo que hará make correr, lo corres con glue_small y mides el tiempo
34. Entre todos llenamos la tabla y vemos cuándo conviene Glue y cuándo sobran workers
35. Con todo probado en dev, subimos a prod por una escalera de siete peldaños: PR y CI/CD
36. Subes un cambio pequeño en una rama y lo llevas por pull request, CI y merge
37. Entras a Airflow de prod por el túnel y lanzas pipeline_taxi
38. Validas prod con Athena y Snowflake, y el INSERT desde BIGDATA_DEV falla por permisos
39. Hoy construiste, comprobaste y promoviste un pipeline, y en el Taller tu equipo escribe cuatro piezas
40. Si alguien reprocesa un mes en prod, ¿qué función de tu equipo evita que silver se duplique?
