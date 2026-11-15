# Memo · ¿Uber y Lyft se reparten el mercado o una domina? (Taller 1)

Equipo: Manuela Restrepo, Ana Maria Montealegre, Julian Olaya, Andrea Paez · Anfitrión: Andrea Páez · Caso: A · Competencia entre plataformas · Fecha: 15 de noviembre de 2026

## Pregunta y decisión

¿Hay una plataforma que concentre los viajes en las zonas de NYC, y eso cambia de enero a marzo de 2024? La respuesta ayuda a la autoridad de movilidad a decidir dónde vigilar la competencia, por ejemplo las tarifas o la calidad del servicio en las zonas donde una sola empresa hace casi todos los viajes.

## Hallazgos

1. **Uber hace casi tres de cada cuatro viajes, y eso no cambia.** De los 60,3 millones de viajes del trimestre, Uber hizo el 73,7 % y Lyft el 26,3 %. Mes a mes la cuota de Uber fue 73,4 %, 74,4 % y 73,4 %. El mercado está concentrado, pero estable: ninguna empresa le está quitando clientes a la otra de forma rápida.
2. **En la mayoría de las zonas el dominio es aún mayor.** De las 250 zonas con al menos 1 000 viajes al mes, Uber tuvo más del 70 % de los viajes en 211 en marzo (194 en enero y 224 en febrero). Lyft solo pasa del 70 % en una zona. La cuota de una zona se mueve en promedio entre 1 y 1,5 puntos de un mes a otro. El cambio más grande fue en Marine Park/Floyd Bennett Field, en Brooklyn, donde Uber pasó de 69,4 % a 74,4 %.
3. **Compiten en los mismos lugares.** Las tres zonas con más viajes son las mismas para las dos empresas: JFK, LaGuardia y East Village. En cada una, Uber hace entre 2,6 y 3,3 veces los viajes de Lyft.
4. **Uber cobra más por viaje, pero Lyft recibe más propina.** El ingreso por viaje (lo que paga el pasajero) fue de 31,12 USD en Uber y 29,99 USD en Lyft. La propina promedio fue de 1,06 USD en Uber y 1,18 USD en Lyft. Esto no prueba que una empresa dé mejor servicio: puede deberse al tipo de viajes que hace cada una.

## Supuestos y definiciones

- **Cuota de mercado:** viajes de la empresa ÷ viajes de las dos empresas en esa zona y mes. La medimos en viajes, no en ingresos (en ingresos Uber tiene el 74,5 %, casi lo mismo).
- **Mercado:** solo Uber y Lyft. Los taxis amarillos y verdes no están en los datos.
- **Zona relevante:** 1 000 viajes o más en el mes. En zonas muy pequeñas, que una empresa tenga el 100 % puede deberse a pocos viajes.
- **Mes:** mes calendario de la fecha de recogida. Marzo tiene 10 % más viajes que febrero, pero también 2 días más: por día la subida es solo de 2,9 %. Por eso comparamos porcentajes y no totales.
- **Fuente:** leímos directo del resumen diario (`DAILY_ZONE_METRICS`), como pide el caso A. Comprobamos que tiene 46 715 filas y 60 268 466 viajes, igual que el paquete y que la estrella del equipo. Ese resumen ya excluye los viajes con distancia, tarifa o duración fuera de rango.
- **Zona:** zona donde empieza el viaje, por su nombre. El catálogo de zonas tiene 265 filas pero 262 nombres ("Corona" aparece dos veces y "Governor's Island/Ellis Island/Liberty Island" tres). En la estrella dejamos una fila por nombre; las repetidas tienen el mismo distrito y tipo de zona, así que no se pierde información.

## Trampa evitada

**Trampa 2, promediar promedios.** La propina viene como un promedio por día, zona y empresa. Si promediábamos esos promedios, un grupo de 10 viajes pesaba lo mismo que uno de 10 000. Con ese error habríamos reportado una propina de 1,00 USD en Lyft y 0,89 USD en Uber, cerca de 15 % menos que el valor real (1,18 y 1,06 USD). Lo evitamos multiplicando cada promedio por sus viajes, sumando y dividiendo por el total de viajes (promedio ponderado).

## Límites

Son solo tres meses de invierno de 2024: no alcanza para hablar de una tendencia de largo plazo. Sabemos que Uber domina, pero no por qué (precios, número de conductores, promociones). Que haya concentración no significa que haya abuso: para eso habría que mirar tarifas y tiempos de espera, que no están en estos datos.
