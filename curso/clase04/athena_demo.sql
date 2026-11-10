-- =====================================================================
-- CLASE 4 · Guion de la demo de Athena (instructor; slides 10 a 13)
-- =====================================================================
--
-- QUÉ HACE
--   Declara una tabla externa de Athena sobre el gold Parquet del bucket público
--   s3://bigdata-udem-2026-publico/ (carpeta paquete/gold/daily_zone_metrics/), registra las
--   particiones, consulta y lee "Data scanned" y el costo.
--   Mensaje de ingeniería: Athena y Snowflake leen los mismos archivos; leer en el lugar frente
--   a cargar con COPY INTO (slides 14 a 16).
--
-- DÓNDE SE CORRE
--   Consola de AWS > región US East (Ohio), us-east-2 > Athena > Query editor. Athena corre una
--   sentencia a la vez: pega y ejecuta cada bloque numerado por separado, en orden.
--
-- PREPARACIÓN (antes de la clase, en tu cuenta de AWS)
--   1. Región us-east-2 (Ohio): la misma del bucket público y de tu lake. En otra región, el
--      workgroup y la base de la demo no aparecen.
--   2. Paso 10 de la guía hecho (make deploy): existen la base de Glue bigdata_lake y el
--      workgroup bigdata-wg, con resultados en s3://bigdata-lake-<cuenta>-us-east-2/tmp/athena/
--      y corte de 1 GB por consulta.
--   3. El bucket público da lectura a cualquier cuenta de AWS sobre el prefijo paquete/
--      (s3:ListBucket con prefijo, s3:GetObject y s3:GetBucketLocation). Ensaya la demo completa
--      desde tu cuenta antes de la clase. Si CREATE EXTERNAL TABLE o MSCK REPAIR dan
--      "Access Denied (Status Code: 403)", revisa esa política.
--   4. En el ensayo anota el Data scanned de Q1 y de Q2 y deja capturas de cada resultado.
--   5. Abre la página de precios (https://aws.amazon.com/athena/pricing/) y lee en pantalla el
--      precio por TB y el mínimo de 10 MB por consulta: los bytes se redondean hacia arriba al
--      megabyte, con un mínimo de 10 MB por consulta; no se cobran las sentencias DDL ni las de
--      gestión de particiones ni las consultas fallidas.
--
-- PASO A PASO
--   Dónde / Qué haces / Debes ver. Las sentencias de SQL están debajo, numeradas igual.
--
--   1. Consola AWS, esquina superior derecha: región US East (Ohio), us-east-2.
--      Debes ver: la región en el selector.
--   2. Servicios > Athena > Query editor. Debes ver: el editor abierto.
--   3. Editor, arriba a la derecha: Workgroup = bigdata-wg. Panel izquierdo: Data source =
--      AwsDataCatalog, Database = bigdata_lake (si no aparece, corre la sentencia 3b).
--      Debes ver: workgroup y base elegidos.
--   4. Solo si usas el workgroup primary: Settings > Manage > Query result location > Browse S3 >
--      s3://bigdata-lake-<cuenta>-us-east-2/tmp/athena/ > Save. bigdata-wg ya trae la ubicación
--      fijada por Terraform y no se edita desde el editor. Sin ubicación: "No output location
--      provided".
--   5. Pega la sentencia 5 (el DDL, una sola) y Run. Debes ver: "Query successful" y
--      gold_publico en Tables.
--   6. Sentencia 6. Debes ver: 0 (la tabla existe pero sin particiones).
--   7. Sentencias 7 y 7b. Debes ver: tres particiones: mes=2024-01, mes=2024-02, mes=2024-03.
--   8. Sentencia 8 (Q1). Debes ver: 3 filas: 15909 filas y 19650023 viajes (2024-01), 14889 y
--      19344724 (2024-02), 15917 y 21273719 (2024-03).
--   9. Barra bajo el editor: lee Data scanned (junto a Completed, Time in queue y Run time).
--      Debes ver: un valor de hasta 656331 bytes (641 KB), el peso de los 6 archivos. Anótalo.
--      Ensayo del 10 nov. 2026 (cuenta de pruebas, dueña del bucket): 643042 bytes (628 KB).
--  10. Sentencia 10 (Q2) y vuelve a leer Data scanned. Debes ver: 19650023 viajes y un Data
--      scanned menor, de a lo sumo 221971 bytes (217 KB), el peso de mes=2024-01.
--      Ensayo del 10 nov. 2026: 47844 bytes (47 KB). Un Data scanned de 0 en el conteo de 10b
--      (SELECT COUNT(*)) también se midió en el ensayo: es el valor del reto E7 del Lab 4.
--  11. Pantalla de precios. Calcula en voz alta: lo escaneado se factura como mínimo 10 MB;
--      10 MB / 1 TB x US$5 = US$0.00005. Q1 y Q2 cuestan lo mismo.
--  12. Limpieza: sentencia 12. Los archivos del bucket siguen ahí.
--
-- QUÉ DECIR EN CADA TRAMO (una frase)
--   Tabla externa: la entrada del catálogo apunta a archivos que Athena no administra.
--   Particiones: el catálogo no las descubre solo; MSCK REPAIR TABLE recorre las carpetas
--   clave=valor. Data scanned: los bytes que leyó; es lo que se factura. Q1 toca las 8 columnas
--   de las 3 carpetas y Q2 lee 1 de 8 columnas en 1 de 3 carpetas: por eso escanea menos, y no
--   por otra razón; el gold es chico, así que ambas pagan el mínimo.
--   Contraste: una consulta que leyera los 5.4 GB de un año de bronze costaría 5.4/1024 TB x
--   US$5 = US$0.026 (cálculo con el precio oficial; bronze no tiene tabla en Athena); en
--   bigdata-wg se cancela al pasar 1 GB.
--
-- LO QUE SE PROBÓ Y LO QUE NO
--   Probado el 10 nov. 2026 con AWS CLI en la cuenta de pruebas (us-east-2, workgroup bigdata-wg,
--   dos corridas completas con los mismos resultados): el DDL, SELECT COUNT(*) = 0 antes de las
--   particiones, MSCK REPAIR TABLE (registra 3 particiones), SHOW PARTITIONS, Q1, Q2, el conteo de
--   10b (46715 filas) y DROP TABLE; también la alternativa ALTER TABLE ... ADD PARTITION (3 particiones).
--   No probado: la prueba entre cuentas (la cuenta de pruebas es dueña del bucket público; queda para
--   el ensayo del instructor desde su cuenta) y los textos de la consola de AWS (rutas del editor).
--
-- ERRORES COMUNES EN LA DEMO
--   Mensaje o síntoma                         | Causa                                | Cómo evitarlo
--   El workgroup bigdata-wg o la base         | Región distinta de us-east-2 o       | Cambia la región a us-east-2;
--     bigdata_lake no aparecen                |   make deploy sin terminar           |   repite make deploy
--   No output location provided               | El workgroup no tiene ubicación de   | Usa bigdata-wg o fija la
--                                             |   resultados                         |   ubicación en primary
--   Access Denied (Service: Amazon S3;        | La política del bucket público no    | Revisa la política (ListBucket
--     Status Code: 403)                       |   permite listar o leer el prefijo   |   con prefijo, GetObject,
--                                             |                                      |   GetBucketLocation) y la ruta
--   SELECT COUNT(*) devuelve 0 tras el DDL    | Faltan las particiones               | MSCK REPAIR TABLE o ADD PARTITION
--   HIVE_BAD_DATA o tipos que no coinciden    | El DDL declara un tipo distinto al   | Usa los tipos del DDL (fecha
--                                             |   del Parquet                        |   date, viajes bigint, el
--                                             |                                      |   resto double)
--   Table already exists                      | Ensayo previo sin limpiar            | DROP TABLE o IF NOT EXISTS
--   La consulta se cancela por pasar 1 GB     | Escaneó más de 1 GB en bigdata-wg    | No ocurre con el gold; sí con
--                                             |                                      |   bronze: elige columnas y
--                                             |                                      |   particiones
-- =====================================================================


-- 3b (solo si la base no aparece)
CREATE DATABASE IF NOT EXISTS bigdata_lake;

-- 5 · Tabla externa (la carpeta termina en «/» y contiene mes=2024-01, mes=2024-02 y mes=2024-03)
CREATE EXTERNAL TABLE IF NOT EXISTS bigdata_lake.gold_publico (
  fecha date,
  zona string,
  empresa string,
  viajes bigint,
  ingreso_total double,
  propina_promedio double,
  distancia_promedio double,
  lluvia_mm double
)
PARTITIONED BY (mes string)
STORED AS PARQUET
LOCATION 's3://bigdata-udem-2026-publico/paquete/gold/daily_zone_metrics/';

-- 6 · Sin particiones registradas, la tabla da 0
SELECT COUNT(*) FROM bigdata_lake.gold_publico;

-- 7 · Registrar las particiones
MSCK REPAIR TABLE bigdata_lake.gold_publico;

-- 7b · Comprobar: 3 particiones
SHOW PARTITIONS bigdata_lake.gold_publico;

-- 7c · Alternativa a MSCK REPAIR, sin recorrer la carpeta (úsala solo si MSCK falla)
-- ALTER TABLE bigdata_lake.gold_publico ADD IF NOT EXISTS
--   PARTITION (mes = '2024-01') LOCATION 's3://bigdata-udem-2026-publico/paquete/gold/daily_zone_metrics/mes=2024-01/'
--   PARTITION (mes = '2024-02') LOCATION 's3://bigdata-udem-2026-publico/paquete/gold/daily_zone_metrics/mes=2024-02/'
--   PARTITION (mes = '2024-03') LOCATION 's3://bigdata-udem-2026-publico/paquete/gold/daily_zone_metrics/mes=2024-03/';

-- 8 · Q1: las 8 columnas, las 3 carpetas
SELECT mes,
       COUNT(*) AS filas,
       SUM(viajes) AS viajes,
       SUM(ingreso_total) AS ingreso,
       AVG(propina_promedio) AS propina,
       AVG(distancia_promedio) AS distancia,
       MAX(lluvia_mm) AS lluvia,
       COUNT(DISTINCT zona) AS zonas,
       COUNT(DISTINCT empresa) AS empresas,
       MIN(fecha) AS desde
FROM bigdata_lake.gold_publico
GROUP BY mes
ORDER BY mes;

-- 10 · Q2: una columna, una carpeta
SELECT SUM(viajes) AS viajes
FROM bigdata_lake.gold_publico
WHERE mes = '2024-01';

-- 10b · Para el reto E7 del Lab 4: contar todas las filas (debe dar 46715)
SELECT COUNT(*) AS filas FROM bigdata_lake.gold_publico;

-- 12 · Limpieza (no borra archivos del bucket)
DROP TABLE bigdata_lake.gold_publico;
