"""Caja de herramientas de la casa: un archivo por trabajo. Este paquete no tiene código.

Cada herramienta se importa desde el archivo donde vive:

    from pipeline.herramientas.rutas import ruta_lake
    from pipeline.herramientas.corrida import Corrida

Los archivos (ninguno importa pyspark al cargarse, para que la VM de Airflow los pueda usar):

    rutas.py     entornos, capas, tablas, meses y la única función que arma rutas del lake
    archivos.py  leer, escribir, mover, listar y borrar archivos en s3:// o file://, en voz alta
    crudo.py     bajar cada fuente una sola vez y dejarla intacta en bronze/_crudo
    capas.py     leer el crudo, y leer y escribir bronze, silver y gold
    control.py   la tabla de control del entorno: la puerta y el registro
    corrida.py   qué es una corrida (entorno, pipeline.yaml, Corrida, Resultado), su banner y cierre
    glue.py      lanzar un paso en Glue, esperar al job y escribir su cierre
    bodega.py    todo lo que habla con Snowflake: conexión, crear tabla y cargar gold
    athena.py    comparar el esquema de gold en el catálogo de Glue con la tabla de Snowflake
    reseteo.py   borrar un entorno completo (S3, tablas y tabla de control)
    equipo.py    ayudas del cuaderno para usar y probar las funciones del equipo

Reglas: ningún archivo de esta caja importa bronze, silver, gold ni carga (evita ciclos), y todo
lo que lee, escribe, consulta o borra dice en voz alta dónde (anunciar).
"""
