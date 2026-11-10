-- =====================================================================
-- LAB 4 · Del bucket público a una tabla de Snowflake (Big Data UdeM · Clase 4)
-- =====================================================================
--
-- OBJETIVO
--   Leer el resumen diario («gold») de los viajes de NYC que está en un bucket público de S3 sin
--   cargarlo, cargarlo a una tabla de Snowflake, contar para comprobar contra el origen y demostrar
--   que repetir la carga no duplica filas. Para quien termine: repetir en Athena, desde tu cuenta de
--   AWS, la consulta que hiciste en Snowflake (E7).
--
-- GLOSARIO (solo lo nuevo)
--   stage            objeto de Snowflake que apunta a una carpeta de archivos externa (aquí, S3).
--   formato de       cómo interpretar esos archivos (aquí, Parquet).
--     archivo
--   $1               la fila de un archivo Parquet como un objeto VARIANT; de él se extraen las
--                    columnas con $1:nombre::TIPO.
--   COPY INTO        copia los archivos de un stage a una tabla.
--   idempotente      repetir la operación deja el mismo estado.
--   metadatos de     lo que Snowflake recuerda de cada archivo cargado en una tabla (64 días).
--     carga
--
-- CÓMO COPIAR ESTE ARCHIVO A SNOWSIGHT (solo navegador, sin terminal)
--   1. En tu fork: carpeta curso > clase04 > lab4.sql.
--   2. Arriba a la derecha del contenido, el ícono de dos cuadritos es "Copy raw file"
--      (no el de la flecha hacia abajo).
--   3. En Snowsight: Projects > Worksheets > botón + (SQL Worksheet). Si tu Snowsight muestra
--      "Workspaces", usa + > SQL File.
--   4. Pega todo (Ctrl/Cmd + V). No elijas rol ni warehouse: el Paso 0 los fija.
--   5. Si no ves el archivo: botón "Sync fork" > "Update branch".
--
-- CÓMO CORRER
--   Paso 0: selecciona de USE ROLE a USE SCHEMA CURSO.LAB4; y pulsa ▶.
--   Ejercicios: bloque a bloque con Cmd/Ctrl+Enter (corre la sentencia donde está el cursor).
--   Para correr varias sentencias seguidas, selecciónalas con el mouse y pulsa ▶.
--   Run All corre todo el archivo: en este archivo NO lo uses.
--
-- TIEMPO: 32 min de trabajo en clase. Orden: E1 a E6 (★, núcleo; la verificación exige los seis).
--   E7 (★★) es el reto de Athena y es opcional.
--
-- NIVELES
--   ★    núcleo: seis ejercicios; la verificación exige los seis
--   ★★   reto, si queda tiempo (necesita tu cuenta de AWS)
--
-- REGLA DEL LAB
--   COPY INTO se escribe una sola vez por tabla. Si necesitas volver a empezar, recrea la tabla
--   con CREATE OR REPLACE TABLE y carga una vez: recrear la tabla borra la memoria del COPY.
--   Nunca uses FORCE = TRUE aquí: carga los archivos de nuevo y duplica las filas.
--
-- DICCIONARIO RÁPIDO (tabla DAILY_ZONE_METRICS: una fila por fecha, zona y empresa)
--   FECHA DATE · ZONA VARCHAR (nombre de la zona) · EMPRESA VARCHAR (Uber o Lyft) · VIAJES NUMBER
--   INGRESO_TOTAL FLOAT · PROPINA_PROMEDIO FLOAT · DISTANCIA_PROMEDIO FLOAT · LLUVIA_MM FLOAT
--   Los archivos son Parquet, en 3 carpetas (mes=2024-01, mes=2024-02, mes=2024-03), 2 por carpeta:
--   s3://bigdata-udem-2026-publico/paquete/gold/daily_zone_metrics/
--   Conteos de control: 2024-01 15909 filas y 19650023 viajes; 2024-02 14889 y 19344724;
--   2024-03 15917 y 21273719. Total: 46715 filas.
--
-- TIPOS DE LAS COLUMNAS
--   EJ2: FECHA DATE, ZONA VARCHAR, EMPRESA VARCHAR, VIAJES NUMBER.
--   EJ4: MES es texto con formato YYYY-MM (por ejemplo 2024-01).
--
-- =====================================================================
-- CÓMO ESCRIBIR CADA EJERCICIO (la misma plantilla en las vistas EJ2, EJ4, EJ5, EJ6 y EJ7)
-- =====================================================================
-- Escribes solo en el lugar del marcador (la línea SELECT NULL AS PENDIENTE):
--
--   ANTES (así llega el archivo):
--     CREATE OR REPLACE VIEW EJ4 AS
--     -- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
--     SELECT NULL AS PENDIENTE
--     -- ▲▲ hasta aquí ▲▲
--     ;
--     SELECT * FROM EJ4;  -- mira tu resultado
--
--   DESPUÉS (reemplazas el marcador por tu SELECT, sin ; al final del SELECT):
--     CREATE OR REPLACE VIEW EJ4 AS
--     -- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
--     SELECT 'x' AS MES, COUNT(*) AS FILAS
--     FROM DAILY_ZONE_METRICS
--     -- ▲▲ hasta aquí ▲▲
--     ;
--     SELECT * FROM EJ4;  -- mira tu resultado
--
-- Ejecuta los dos bloques con Cmd/Ctrl+Enter. Debes ver "View EJ4 successfully created" y
-- luego tu resultado. Si ves un mensaje rojo, el CREATE falló: lee el mensaje y consulta la
-- tabla de errores comunes al final. Los nombres de las columnas de salida son parte del
-- ejercicio y deben coincidir (mayúsculas o minúsculas no importan). Cada columna calculada
-- (COUNT, SUM, TO_CHAR...) necesita AS NOMBRE; si no, la vista falla con
-- "Missing column specification".
--
-- Una vista es una consulta guardada con nombre: no guarda datos, guarda la consulta; por eso la
-- verificación puede leer EJ2, EJ4... sin preguntarte nada. Los objetos de E1 (el stage) y E3 (la
-- tabla) no son vistas: los creas con las sentencias de cada ejercicio, y la verificación los
-- busca por su nombre.
-- =====================================================================


-- =====================================================================
-- PASO 0 · PREPARACIÓN (ya resuelto: no lo cambies)
-- QUÉ HACER: selecciona con el mouse desde USE ROLE hasta USE SCHEMA CURSO.LAB4; y pulsa ▶.
-- Es idempotente: puedes correrlo más de una vez.
-- =====================================================================

USE ROLE ACCOUNTADMIN;

-- WAREHOUSE: el cómputo que ejecuta las consultas; se factura por segundo mientras está
-- encendido. AUTO_SUSPEND = 60 lo apaga tras 60 s sin uso y AUTO_RESUME lo enciende al consultar.
CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH
  WAREHOUSE_SIZE = XSMALL
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;
-- Si COMPUTE_WH ya existía (trial), se deja con suspensión a los 60 s.
ALTER WAREHOUSE COMPUTE_WH SET AUTO_SUSPEND = 60;
ALTER WAREHOUSE COMPUTE_WH SET AUTO_RESUME = TRUE;

USE WAREHOUSE COMPUTE_WH;

-- TU BASE DE TRABAJO: CURSO es la base de datos y LAB4 el esquema donde se guardan tus objetos.
CREATE DATABASE IF NOT EXISTS CURSO;
CREATE SCHEMA IF NOT EXISTS CURSO.LAB4;
USE SCHEMA CURSO.LAB4;


-- =====================================================================
-- EJERCICIO 1 ★ · Un formato de archivo y un stage sobre el bucket público
-- =====================================================================
-- DEFINICIÓN:
--   Un FORMATO DE ARCHIVO le dice a Snowflake cómo leer los archivos: TYPE = PARQUET para Parquet,
--   un formato de columnas con tipos que viene dentro del archivo. Un STAGE es el objeto que
--   apunta a una carpeta de archivos: con URL = 's3://bucket/carpeta/' apunta a S3, y con
--   FILE_FORMAT = nombre usa ese formato. Crear el stage no copia nada: solo guarda la dirección.
--   Un bucket público se lee sin credenciales, así que el stage no lleva claves.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter; es un stage interno, sin S3):
CREATE OR REPLACE FILE FORMAT EJEMPLO_CSV TYPE = CSV SKIP_HEADER = 1;
CREATE OR REPLACE STAGE EJEMPLO_STAGE FILE_FORMAT = EJEMPLO_CSV;
SHOW STAGES LIKE 'EJEMPLO_STAGE';
-- Debes ver en el ejemplo: "Stage area EJEMPLO_STAGE successfully created." y una fila con
-- name = EJEMPLO_STAGE y type = INTERNAL. El tuyo será de tipo EXTERNAL porque lleva una URL de S3.
--
-- TU TURNO:
--   Crea el formato de archivo PARQUET_PUB con TYPE = PARQUET.
--   Crea el stage LAKE_PUBLICO con
--     URL = 's3://bigdata-udem-2026-publico/paquete/gold/daily_zone_metrics/'
--   (la URL termina en «/») y con ese formato.
--   Escribe las dos sentencias, cada una con punto y coma, entre las marcas.

-- ▼▼ escribe aquí tus dos sentencias CREATE ▼▼

-- ▲▲ hasta aquí ▲▲

SHOW STAGES LIKE 'LAKE_PUBLICO';  -- mira tu stage

-- ✅ Debes ver: "Stage area LAKE_PUBLICO successfully created." al crear el stage, y en SHOW STAGES
--    una fila con name = LAKE_PUBLICO, type = EXTERNAL y la url del paquete.


-- =====================================================================
-- EJERCICIO 2 ★ · Leer los archivos en el lugar con $1
-- =====================================================================
-- DEFINICIÓN:
--   Con un stage puedes consultar los archivos sin cargarlos: SELECT $1 FROM @stage. Cada fila
--   del Parquet llega como un objeto VARIANT en $1. Para sacar una columna: $1:nombre::TIPO. El
--   nombre del campo va en minúsculas, igual que en el archivo. PATTERN es una expresión regular
--   sobre la ruta del archivo: '.*mes=2024-01/.*[.]parquet' deja solo la carpeta de enero.
--   Leer así no crea ninguna copia: cada consulta vuelve a leer S3.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter; simula una fila con PARSE_JSON):
SELECT V:fecha::DATE AS FECHA, V:zona::VARCHAR AS ZONA, V:viajes::NUMBER AS VIAJES
FROM (SELECT PARSE_JSON('{"fecha": "2024-01-10", "zona": "Union Sq", "viajes": 5149}') AS V);
-- Debes ver en el ejemplo: 1 fila: 2024-01-10, Union Sq, 5149.
--
-- Primero lista los archivos del stage y mira la forma de $1 (necesitas el stage del ejercicio 1):
LIST @LAKE_PUBLICO;
SELECT $1 FROM @LAKE_PUBLICO (PATTERN => '.*mes=2024-01/.*[.]parquet') LIMIT 5;
-- Debes ver: LIST con 6 archivos .parquet (2 por carpeta). El SELECT, 5 objetos con las 8 claves:
-- distancia_promedio, empresa, fecha, ingreso_total, lluvia_mm, propina_promedio, viajes, zona.
--
-- TU TURNO:
--   Vista EJ2 con los viajes de enero leídos del stage (sin cargar nada): una fila por fila del
--   archivo, extrayendo cada columna de $1 y convirtiéndola de tipo.
--   Usa el PATTERN de enero de arriba.
--   Columnas de salida (en este orden): FECHA (DATE), ZONA (VARCHAR), EMPRESA (VARCHAR), VIAJES (NUMBER)

CREATE OR REPLACE VIEW EJ2 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ2 LIMIT 5;  -- mira tu resultado (la vista tiene 15909 filas)
-- Para contar, cuando EJ2 ya esté resuelto: SELECT COUNT(*) AS FILAS, SUM(VIAJES) AS VIAJES FROM EJ2;

-- ✅ Debes ver: 5 filas de enero con FECHA, ZONA, EMPRESA y VIAJES. El conteo da 15909 filas y 19650023 viajes.


-- =====================================================================
-- EJERCICIO 3 ★ · Crear la tabla y cargarla con un solo COPY INTO
-- =====================================================================
-- DEFINICIÓN:
--   COPY INTO tabla FROM @stage copia los archivos del stage a una tabla de Snowflake; desde ese
--   momento los datos viven dentro de Snowflake (en su propio formato) y las consultas ya no
--   leen S3. PATTERN elige los archivos por su ruta. MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
--   asocia las columnas del Parquet con las de la tabla por nombre (no por posición) y sin
--   distinguir mayúsculas; sin esa opción, un Parquet no se carga a una tabla de 8 columnas. El
--   resultado de COPY INTO trae una fila por archivo con su estado (LOADED) y las filas cargadas.
--
-- EJEMPLO DE SALIDA (las primeras columnas del resultado de un COPY INTO; el orden de las filas varía):
--   file                                  | status | rows_parsed | rows_loaded | errors_seen
--   ...mes=2024-01/part-00000-....parquet | LOADED | 6692        | 6692        | 0
--   ...mes=2024-01/part-00001-....parquet | LOADED | 9217        | 9217        | 0
--   ...(otras 4 filas, una por archivo)   | LOADED | ...         | ...         | 0
--
-- TU TURNO:
--   Crea la tabla DAILY_ZONE_METRICS con estas 8 columnas, en este orden:
--     FECHA DATE, ZONA VARCHAR, EMPRESA VARCHAR, VIAJES NUMBER(38,0), INGRESO_TOTAL FLOAT,
--     PROPINA_PROMEDIO FLOAT, DISTANCIA_PROMEDIO FLOAT, LLUVIA_MM FLOAT
--   Cárgala con UN solo COPY INTO desde @LAKE_PUBLICO que tome todos los archivos .parquet
--   (PATTERN = '.*[.]parquet') y asocie las columnas por nombre.
--   Usa CREATE OR REPLACE TABLE para que puedas rehacerlo. Escribe las dos sentencias entre las marcas.

-- ▼▼ escribe aquí el CREATE OR REPLACE TABLE y el COPY INTO ▼▼

-- ▲▲ hasta aquí ▲▲

SELECT COUNT(*) AS FILAS FROM DAILY_ZONE_METRICS;  -- mira tu resultado

-- ✅ Debes ver: el COPY INTO devuelve 6 filas con status LOADED (una por archivo) y en total 46715
--    filas cargadas; el conteo final da 46715.


-- =====================================================================
-- EJERCICIO 4 ★ · Conteos de control contra el origen
-- =====================================================================
-- DEFINICIÓN:
--   Cargar sin contar no comprueba nada: el conteo de control compara lo que hay en la tabla con lo que
--   dice el origen. Aquí el origen publica filas y viajes por mes. TO_CHAR(FECHA, 'YYYY-MM') da el
--   mes como texto (2024-01), y GROUP BY 1 agrupa por la primera columna del SELECT.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter):
SELECT TO_CHAR(DATEADD('day', SEQ4(), '2024-01-30'::DATE), 'YYYY-MM') AS MES, COUNT(*) AS DIAS
FROM TABLE(GENERATOR(ROWCOUNT => 4))
GROUP BY 1
ORDER BY 1;
-- Debes ver en el ejemplo: 2 filas: 2024-01 con 2 días (30 y 31 de enero) y 2024-02 con 2 días.
--
-- TU TURNO:
--   Vista EJ4 con los conteos de control por mes de la tabla DAILY_ZONE_METRICS que cargaste.
--   MES es el texto YYYY-MM; FILAS, el número de filas; VIAJES, la suma de VIAJES. Ordena por MES.
--   Columnas de salida (en este orden): MES, FILAS, VIAJES

CREATE OR REPLACE VIEW EJ4 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ4;  -- mira tu resultado

-- ✅ Debes ver: 3 filas: 2024-01 con 15909 filas y 19650023 viajes; 2024-02 con 14889 y 19344724;
--    2024-03 con 15917 y 21273719. Coinciden con los conteos de control de la cabecera.


-- =====================================================================
-- EJERCICIO 5 ★ · Repetir el COPY INTO no duplica
-- =====================================================================
-- DEFINICIÓN:
--   Una operación es IDEMPOTENTE si repetirla deja el mismo estado. Snowflake guarda, por tabla, los
--   METADATOS DE CARGA de cada archivo que ya cargó (nombre, tamaño y ETag, la huella del contenido)
--   durante 64 días. Si repites el COPY INTO, los archivos que ya están se omiten.
--   FORCE = TRUE desactiva esa memoria y recarga todo: duplica las filas.
--   COPY_HISTORY es la función que lista las cargas de una tabla: TABLE_NAME elige la tabla y
--   START_TIME, desde cuándo. Una carga idempotente se comprueba contando filas, no solo leyendo el mensaje.
--
-- EJEMPLO DE SALIDA (mira el historial de tu carga del ejercicio 3; ejecútalo con Cmd/Ctrl+Enter
-- cuando la tabla ya exista):
SELECT FILE_NAME, STATUS, ROW_COUNT
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
       TABLE_NAME => 'DAILY_ZONE_METRICS',
       START_TIME => DATEADD('hour', -24, CURRENT_TIMESTAMP())))
ORDER BY FILE_NAME;
-- Debes ver en el ejemplo: 6 filas con STATUS = Loaded, una por archivo, con 46715 filas en total.
--
-- TU TURNO:
--   1) Repite exactamente el COPY INTO del ejercicio 3, sin FORCE. No recrees la tabla. Anota el mensaje.
--   2) Vista EJ5 con dos números: FILAS, las filas de DAILY_ZONE_METRICS, y ARCHIVOS_CARGADOS, la cantidad de
--      archivos distintos (FILE_NAME) que registra COPY_HISTORY para esa tabla en las últimas 24 horas.
--   Columnas de salida (en este orden): FILAS, ARCHIVOS_CARGADOS

-- ▼▼ escribe aquí el mismo COPY INTO del ejercicio 3 (y solo ese) ▼▼

-- ▲▲ hasta aquí ▲▲

CREATE OR REPLACE VIEW EJ5 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ5;  -- mira tu resultado

-- ✅ Debes ver: el COPY INTO responde "Copy executed with 0 files processed." y la vista, 1 fila:
--    46715 filas y 6 archivos cargados.


-- =====================================================================
-- EJERCICIO 6 ★ · Dos tablas auxiliares y sus controles
-- =====================================================================
-- DEFINICIÓN:
--   Una dimensión describe aquello por lo que se mide: aquí, las zonas de NYC (DIM_ZONA, con su
--   distrito) y los festivos federales de 2024 (FESTIVOS_2024). Un nombre de zona puede repetirse en
--   dos identificadores (LOCATION_ID): unir por nombre duplicaría filas, por eso se cuentan los repetidos.
--
-- CÓMO CARGARLAS (sin terminal): en tu fork abre datos > dim_zona.sql y pulsa "Copy raw file".
--   Abre una hoja nueva de Snowsight y escribe estas tres líneas:
--     USE ROLE ACCOUNTADMIN;
--     USE WAREHOUSE COMPUTE_WH;
--     USE SCHEMA CURSO.LAB4;
--   Pega debajo el contenido de dim_zona.sql y, después, el de festivos_2024.sql (Copy raw file de
--   datos > festivos_2024.sql). Pulsa Run All en esa hoja. Los archivos se pueden correr más de una vez.
--
-- EJEMPLO RESUELTO (ejecútalo con Cmd/Ctrl+Enter, ya con las dos tablas cargadas):
SELECT 'zonas' AS CONTROL, COUNT(*) AS VALOR FROM DIM_ZONA
UNION ALL
SELECT 'zonas_manhattan', COUNT(*) FROM DIM_ZONA WHERE BOROUGH = 'Manhattan';
-- Debes ver en el ejemplo: 2 filas: zonas = 265 y zonas_manhattan = 69.
--
-- TU TURNO:
--   Vista EJ6 con tres controles, en este orden y con estos textos en CONTROL:
--     zonas              filas de DIM_ZONA
--     festivos           filas de FESTIVOS_2024
--     nombres_repetidos  cuántos nombres de ZONA aparecen más de una vez en DIM_ZONA
--   Columnas de salida (en este orden): CONTROL, VALOR

CREATE OR REPLACE VIEW EJ6 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ6;  -- mira tu resultado

-- ✅ Debes ver: 3 filas: zonas = 265; festivos = 11; nombres_repetidos = 2.


-- =====================================================================
-- EJERCICIO 7 ★★ · Reto: lo mismo en Athena, en tu cuenta de AWS
-- =====================================================================
-- DEFINICIÓN:
--   Athena es el servicio de AWS que consulta archivos de S3 con SQL, sin servidor: declaras una tabla
--   externa (una entrada en el catálogo que apunta a los archivos) y pagas por los bytes que lee
--   la consulta ("Data scanned"). Aquí lees los mismos archivos que Snowflake, sin copiarlos.
--   Se factura el mayor entre 10 MB y lo escaneado, redondeado hacia arriba al megabyte.
--
-- ANTES DE EMPEZAR (en tu cuenta de AWS)
--   Consola AWS > región us-east-2 (Ohio) > Athena > Query editor > workgroup bigdata-wg
--   (lo creó el paso 10 de la guía). En la región equivocada no aparecen ni el workgroup ni la base.
--
-- PASOS (el SQL completo, para que no dependas de la slide)
-- 1) Corre esta sentencia en Athena (una sola):
--    CREATE EXTERNAL TABLE IF NOT EXISTS bigdata_lake.gold_publico (
--      fecha date, zona string, empresa string, viajes bigint,
--      ingreso_total double, propina_promedio double,
--      distancia_promedio double, lluvia_mm double)
--    PARTITIONED BY (mes string)
--    STORED AS PARQUET
--    LOCATION 's3://bigdata-udem-2026-publico/paquete/gold/daily_zone_metrics/';
-- 2) Registra las particiones y comprueba que son 3:
--    MSCK REPAIR TABLE bigdata_lake.gold_publico;
--    SHOW PARTITIONS bigdata_lake.gold_publico;
-- 3) Cuenta las filas (debe dar 46715) y lee "Data scanned" bajo el editor:
--    SELECT COUNT(*) AS filas FROM bigdata_lake.gold_publico;
-- 4) Escribe en la vista EJ7 las filas, los KB de Data scanned y los MB facturados
--    (el mayor entre 10 y los KB / 1024 redondeados hacia arriba).
-- 5) Limpieza: DROP TABLE bigdata_lake.gold_publico;   (no borra archivos)
--
-- TU TURNO:
--   Vista EJ7 con los tres valores que leíste en Athena para la consulta del paso 3, escritos como
--   números: FILAS_ATHENA (las filas), KB_ESCANEADOS (el Data scanned, en KB) y MB_FACTURADOS.
--   Columnas de salida (en este orden): FILAS_ATHENA, KB_ESCANEADOS, MB_FACTURADOS

CREATE OR REPLACE VIEW EJ7 AS
-- ▼▼ BORRA la línea de abajo y escribe aquí tu SELECT (sin punto y coma) ▼▼
SELECT NULL AS PENDIENTE
-- ▲▲ hasta aquí ▲▲
;
SELECT * FROM EJ7;  -- mira tu resultado

-- ✅ Debes ver: 1 fila con FILAS_ATHENA = 46715 y MB_FACTURADOS = 10 (mientras KB_ESCANEADOS sea
--    menor que 10240). Si no tienes cuenta de AWS lista, PENDIENTE en E7 es normal.


-- =====================================================================
-- PASO FINAL · Corre la verificación
-- =====================================================================
-- 1. Copia lab4_verificacion.sql igual que copiaste este archivo.
-- 2. En Snowsight abre OTRA hoja nueva (+ SQL Worksheet o + > SQL File), pega todo y pulsa Run All.
-- 3. Busca la tabla final: EJERCICIO, NIVEL, RESULTADO, PISTA.
--
-- Una fila por ejercicio:
--   OK         = correcto.
--   REVISAR    = el objeto existe pero no coincide. Lee la PISTA y compara TUS_COLUMNAS con
--                COLUMNAS_ESPERADAS.
--   PENDIENTE  = el objeto no existe (E1, E3) o la vista todavía tiene el marcador
--                SELECT NULL AS PENDIENTE (E2, E4, E5, E6, E7).
-- La última fila es el resumen: cuántos de los 6 ★ están en OK. META: RESUMEN = OK y "6 de 6".
-- PENDIENTE en E7 es normal si no llegaste al reto. Si dice PENDIENTE pero escribiste tu SELECT,
-- el CREATE falló: busca el mensaje rojo.


-- =====================================================================
-- QUÉ APRENDISTE
-- =====================================================================
-- - Un stage lee los archivos en el lugar (SELECT $1 FROM @stage) y COPY INTO los copia a una
--   tabla una sola vez: desde entonces la consulta lee la tabla, no S3.
-- - Snowflake recuerda los archivos que cargó en cada tabla (64 días): repetir el COPY INTO da
--   «0 files processed» y las filas no se duplican; FORCE = TRUE las duplica.
-- - Recrear la tabla borra esa memoria: el siguiente COPY INTO carga todo otra vez.
-- - Los conteos por mes se contrastan con el origen: 46715 filas en total.
--
-- Siguiente: descanso. Después, el Taller 1 usa esta tabla para contestar la pregunta de la lluvia;
-- la lluvia se repite en más de 500 filas por día, y eso cambia cómo se suma.


-- =====================================================================
-- ERRORES COMUNES
-- =====================================================================
-- Mensaje o síntoma                             | Causa                          | Cómo evitarlo
-- ---------------------------------------------|--------------------------------|---------------------------
-- LIST devuelve 0 filas ("No data")             | La ruta de la URL tiene un      | Copia la URL completa del
--                                              |   error de escritura           |   paquete; vuelve a crear
--                                              |                                |   el stage
-- Failure using stage area. Cause: [Access      | La URL apunta a un prefijo que | Verifica la URL carácter
--   Denied (Status Code: 403 ...)]              |   no es público               |   por carácter
-- E1 da REVISAR aunque LIST funciona            | La URL no es exactamente la    | Copia la URL completa del
--                                              |   del paquete (por ejemplo,    |   paquete, con la «/» final
--                                              |   sin la «/» final)            |
-- PARQUET file format can produce one and only  | Falta MATCH_BY_COLUMN_NAME en  | Añade MATCH_BY_COLUMN_NAME
--   one column of type variant, object, or      |   el COPY INTO                 |   = CASE_INSENSITIVE
--   array                                       |                                |
-- El COPY INTO carga 0 archivos la primera vez  | El PATTERN no coincide con los | Usa '.*[.]parquet'
--                                              |   nombres                      |
-- Todas las columnas de EJ2 salen NULL          | El nombre del campo lleva      | El campo va en minúsculas:
--                                              |   mayúsculas ($1:Fecha)        |   $1:fecha
-- Las filas de E5 son el doble                  | Segundo COPY INTO con          | CREATE OR REPLACE TABLE y
--                                              |   FORCE = TRUE, o dos cargas   |   un solo COPY INTO
--                                              |   tras recrear la tabla        |
-- Object 'LAKE_PUBLICO' does not exist          | No se corrió el Paso 0 en esa  | Selecciona de USE ROLE a
--                                              |   hoja o falta el ejercicio 1  |   USE SCHEMA CURSO.LAB4; y
--                                              |                                |   pulsa ▶
-- Missing column specification (al crear una    | Una columna calculada sin AS   | Pon AS NOMBRE en cada
--   vista)                                      |                                |   columna calculada
-- EJ6 falla con DIM_ZONA does not exist o       | No se corrieron los archivos   | Pega y corre dim_zona.sql y
--   FESTIVOS_2024 does not exist                |   de datos/ en esa hoja        |   festivos_2024.sql con el
--                                              |                                |   esquema CURSO.LAB4
-- La verificación dice PENDIENTE y sí escribiste| El CREATE falló                | Busca el mensaje rojo en la
--   tu SELECT                                   |                                |   hoja del lab
-- REVISAR con columnas distintas                | El alias de salida no coincide | Compara TUS_COLUMNAS con
--                                              |                                |   COLUMNAS_ESPERADAS
