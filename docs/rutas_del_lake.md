# Dónde queda cada dato: las rutas del lake

Un solo bucket guarda los datos de dev y de prod. Antes compartían la carpeta `bronze/`: una corrida de bronze en dev creaba un lote nuevo, y la siguiente corrida de silver en prod leía ese lote sin que nadie lo hubiera decidido. Este documento explica la regla que lo corrige, cómo ver en cada momento en qué bucket y carpeta estás leyendo o escribiendo, y qué hacer si tu bucket viene del diseño anterior.

- [La regla](#regla)
- [Quién lee y escribe qué](#quien)
- [Cómo ver dónde estás](#ver)
- [Qué cambió: antes y ahora](#cambio)
- [Migrar un bucket del diseño anterior](#migrar)
- [Errores comunes](#errores)
- [Por qué está diseñado así](#diseno)

<a id="regla"></a>
## La regla

```text
s3://<LAKE>/<entorno>/<capa>/<tabla>/mes=AAAA-MM/...

<LAKE>     bigdata-lake-<CUENTA>-us-east-2   (lo imprime make deploy como lake_bucket)
<entorno>  dev | prod
<capa>     bronze | silver | gold
```

Tres consecuencias:

1. Un paso de dev solo lee y escribe bajo `dev/`. Uno de prod, solo bajo `prod/`. No existe ninguna carpeta que los dos usen. **El entorno no se elige:** lo que corres desde el Code Editor es siempre dev; prod lo fija solo el despliegue en la VM.
2. Las rutas se arman en un solo lugar: la función `ruta_lake` de `src/pipeline/herramientas/rutas.py`. Los archivos YAML de `config/` ya no llevan rutas, y ningún otro módulo escribe un `s3://` a mano.
3. Los prefijos `code/`, `dags/`, `logs/` y `tmp/` no son de ningún entorno. Son del propio lake: el código que ejecuta Glue, los DAGs, los logs de Spark y los temporales.

Ya no existe el entorno `local` sobre el disco ni la muestra: el Code Editor corre Spark (`computo = code_editor`) leyendo y escribiendo en `s3://<LAKE>/dev/`.

<a id="quien"></a>
## Quién lee y escribe qué

| Quién | Entorno | Lee | Escribe |
|---|---|---|---|
| `make correr`, el notebook, o el DAG `pipeline_taxi` del Airflow del Code Editor, con cualquier `computo` | dev | las fuentes y `dev/bronze/`, `dev/silver/`, `dev/gold/` | `dev/bronze/`, `dev/silver/` y `dev/gold/`; anota en `BIGDATA.CONTROL_DEV.WATERMARK` y carga en `BIGDATA.DEV` |
| DAG `pipeline_taxi` en la VM de Airflow (solo después del PR y del CI/CD) | prod | las fuentes y `prod/bronze/`, `prod/silver/`, `prod/gold/` | `prod/bronze/`, `prod/silver/` y `prod/gold/`; anota en `BIGDATA.CONTROL_PROD.WATERMARK` y carga en `BIGDATA.PROD` |
| DAG `resetear_entorno` | el de ese Airflow | nada | borra todo bajo `<entorno>/`, la tabla de control y las tablas de Snowflake de ese entorno |
| Athena | el de la tabla | lo que declara cada tabla | nada (solo resultados en `tmp/athena/`) |
| Snowflake (`COPY INTO`) | dev o prod | `dev/gold/` o `prod/gold/` (los stages de `infra/snowflake`) | nada en S3 |

Las carpetas que cuelgan de cada entorno:

```text
s3://<LAKE>/
  dev/                                     solo lo toca dev
    bronze/
      _crudo/<fuente>/mes=AAAA-MM/<archivo>   el archivo tal como se descargó
      fhvhv/mes=AAAA-MM/lote=<id>/            Parquet, un lote por ingesta
      clima/mes=AAAA-MM/lote=<id>/
      taxi_zones/lote=<id>/
    silver/fhvhv/mes=AAAA-MM/                 espejo de bronze: una tabla por fuente
    silver/clima/mes=AAAA-MM/
    silver/taxi_zones/
    gold/<tabla>/mes=AAAA-MM/                 una carpeta por tabla de gold
  prod/                                    solo lo toca prod (misma forma que dev)
    bronze/  silver/  gold/
  code/  dags/  logs/  tmp/                del lake, de ningún entorno
```

<a id="ver"></a>
## Cómo ver dónde estás

Hay tres formas, de la más general a la más puntual.

**1. La tabla de un entorno.** Imprime el bucket y la carpeta de cada capa y tabla:

```bash
cd ~/bigdata
make rutas ENTORNO=dev
```

Sin `ENTORNO` imprime los dos entornos. En un notebook es `donde_estoy("dev")` (con `from pipeline.herramientas.rutas import donde_estoy`). Es solo informativo: no cambia con qué entorno corres. La salida es esta (la cuenta será la tuya):

```text
DÓNDE ESTOY | entorno: dev | los datos están en S3
Bucket del lake  : bigdata-lake-123456789012-us-east-2
Carpeta de dev   : s3://bigdata-lake-123456789012-us-east-2/dev
Este entorno solo lee y escribe bajo dev/. No toca prod/.

CAPA    RUTA COMPLETA                                               CARPETAS DENTRO DE LA CAPA
bronze  s3://bigdata-lake-123456789012-us-east-2/dev/bronze         <tabla>/mes=AAAA-MM/lote=<id>/   (taxi_zones: lote=<id>/)
bronze  s3://bigdata-lake-123456789012-us-east-2/dev/bronze/_crudo  <fuente>/mes=AAAA-MM/<archivo>   (el archivo crudo)
silver  s3://bigdata-lake-123456789012-us-east-2/dev/silver         <tabla>/mes=AAAA-MM/   (taxi_zones: sin mes)
gold    s3://bigdata-lake-123456789012-us-east-2/dev/gold           <tabla>/mes=AAAA-MM/

Del lake, no de un entorno: code/, dags/, logs/, tmp/
```

**2. Cada lectura y escritura dice su ruta completa.** Las funciones de la casa (`traer_crudo_*`, `leer_crudo`, `leer_capa`, `escribir_bronze`, `escribir_capa`, `cargar_gold` y la tabla de control) escriben una línea con el verbo y la ruta antes de actuar. En un notebook aparece en la salida de la celda; en una corrida de Glue o de Airflow, en el log de la tarea:

```text
LEE      s3://bigdata-lake-123456789012-us-east-2/dev/bronze/fhvhv/mes=2024-01/lote=20261120T150102Z_a3f9c1  (bronze de fhvhv)
ESCRIBE  s3://bigdata-lake-123456789012-us-east-2/dev/silver/fhvhv/mes=2024-01  (silver de fhvhv)
REGISTRA BIGDATA.CONTROL_DEV.WATERMARK  (tabla=fhvhv mes=2024-01)
```

Además, cada corrida empieza con un encabezado que dice el entorno, el cómputo, el paso, el mes, el límite, qué lee, qué escribe y qué tabla de control usa.

**3. Lo que hay hoy en el bucket.** `make estado` lista, por entorno y capa, si la carpeta tiene datos. `make doctor` y `make deploy` avisan si en la raíz del bucket quedan carpetas del diseño anterior:

```bash
cd ~/bigdata
make estado
```

```text
==> Rutas del lake (una carpeta por entorno y capa)
  Bucket del lake: bigdata-lake-123456789012-us-east-2
  s3://bigdata-lake-123456789012-us-east-2/dev/bronze/  con datos
  ...
```

<a id="cambio"></a>
## Qué cambió: antes y ahora

| Antes | Ahora | Quién la escribe |
|---|---|---|
| `bronze/_crudo/...` y `bronze/<fuente>/.../lote=<id>/` (compartido) | `prod/bronze/...` y `dev/bronze/...`, una por entorno | prod: el DAG de la VM. dev: lo que corres desde el Code Editor |
| `muestra/` | desaparece (ya no hay muestra) | — |
| silver `fhvhv_trips/pickup_date=...` | silver `fhvhv/mes=...`, `clima/mes=...` y `taxi_zones/` (espejo de bronze) | dev o prod |
| gold `daily_zone_metrics/mes=...` | gold `<tabla>/mes=...` (la de la casa es `tarifa_por_milla_barrio`; cada equipo suma las suyas) | dev o prod |
| `silver/` y `gold/` en la raíz (vacías) | desaparecen | (las creaba Terraform; ya no) |
| `code/`, `dags/`, `logs/`, `tmp/` | igual | `make deploy`, el CI/CD, Glue y Athena |

Lo que no cambia: las carpetas `dev/gold` y `prod/gold` ya cumplían la regla, así que los stages de Snowflake (`BIGDATA.DEV.LAKE_GOLD` y `BIGDATA.PROD.LAKE_GOLD`) y la carga de gold (`cargar_gold`) siguen funcionando sin tocarlos.

Lo que sí cambia en la infraestructura al hacer `make deploy`:

- El rol de Glue (`<prefix>-glue-exec`) ya solo accede a `dev/`, `prod/`, `code/`, `tmp/` y `logs/`. Pierde el acceso a `bronze/`, `muestra/`, `silver/` y `gold/` de la raíz.
- Terraform deja de manejar los marcadores vacíos `bronze/`, `silver/` y `gold/` de la raíz (sin borrarlos, para que `make deploy` no se detenga por la guardia de destrucción) y crea `dev/` y `prod/`.

<a id="migrar"></a>
## Migrar un bucket del diseño anterior

Un bucket "del diseño anterior" tiene `bronze/` y `muestra/` en la raíz. **Lo normal es que no lo hagas a mano:** `make migrar-clase07` mueve el crudo a `prod/bronze/`, borra `muestra/`, crea los esquemas de Snowflake y deja el Code Editor listo (paso a paso, con la salida esperada, en [curso/clase07/README.md](../curso/clase07/README.md)). Lo que sigue son los comandos que usa por debajo, para quien quiere hacerlo a mano. Hay dos caminos. En los dos, el primer paso es el mismo, y va antes de tocar S3: actualizar el código.

```bash
cd ~/bigdata
git pull
make deploy
```

`make deploy` sube el código nuevo (`code/pipeline.zip`) y actualiza el rol de Glue. Sin este paso, Glue sigue ejecutando el código viejo, que escribe en las carpetas de antes, y lo que muevas o regeneres no coincide con lo que Glue lee.

**Camino A: regenerar (solo en una cuenta de pruebas).** Borra lo viejo y deja que bronze vuelva a descargar el crudo del mes la primera vez que corra (`make correr PASO=bronze`).

```bash
cd ~/bigdata
LAKE="bigdata-lake-$(aws sts get-caller-identity --query Account --output text)-us-east-2"
aws s3 rm "s3://$LAKE/bronze/" --recursive --only-show-errors
aws s3 rm "s3://$LAKE/muestra/" --recursive --only-show-errors
aws s3 rm "s3://$LAKE/silver/" --recursive --only-show-errors
aws s3 rm "s3://$LAKE/gold/" --recursive --only-show-errors
```

`aws s3 rm` con `--recursive` solo borra las claves que empiezan con ese prefijo: `s3://$LAKE/gold/` no toca `dev/gold/` ni `prod/gold/`. Si quieres empezar de cero también en silver y gold de los entornos, agrega `aws s3 rm "s3://$LAKE/dev/" --recursive` y lo mismo con `prod/`.

**Camino B: mover (conserva los datos y no vuelve a descargar nada).** `aws s3 mv` entre dos rutas de S3 copia del lado del servidor y borra el original, así que no pasa por tu máquina. Con `--exclude '*/lote=*'` mueve **solo el crudo** (unos 5.4 GB): los lotes viejos se quedan sin usar en la raíz y se pueden borrar después del curso. Es lo que hace `make migrar-clase07`.

```bash
cd ~/bigdata
LAKE="bigdata-lake-$(aws sts get-caller-identity --query Account --output text)-us-east-2"
aws s3 mv "s3://$LAKE/bronze/" "s3://$LAKE/prod/bronze/" --recursive --exclude '*/lote=*' --only-show-errors
aws s3 rm "s3://$LAKE/muestra/" --recursive --only-show-errors
aws s3 rm "s3://$LAKE/silver/" --recursive --only-show-errors
aws s3 rm "s3://$LAKE/gold/" --recursive --only-show-errors
```

Los dos últimos comandos borran los marcadores vacíos de la raíz. Si en `silver/` o `gold/` hubiera datos tuyos (de las sesiones de SQL, no del pipeline), no los ejecutes: mira antes con `aws s3 ls "s3://$LAKE/silver/" --recursive`.

**Comprobar** que la raíz quedó solo con carpetas del lake y de los entornos:

```bash
cd ~/bigdata
LAKE="bigdata-lake-$(aws sts get-caller-identity --query Account --output text)-us-east-2"
aws s3 ls "s3://$LAKE/"
make estado
```

```text
                           PRE code/
                           PRE dags/
                           PRE dev/
                           PRE logs/
                           PRE prod/
                           PRE tmp/
```

**Athena.** Las tablas de la clase 6 (`bronze_fhvhv`, `silver_fhvhv_trips`...) apuntan a las carpetas viejas y quedan vacías. La clase 7 trae tablas nuevas, con el entorno y la capa en el nombre (`prod_bronze_fhvhv`, `dev_silver_fhvhv`, `dev_gold_tarifa_por_milla_barrio`): ejecuta `curso/clase07/athena/01_tablas.sql` y, si quieres, borra las viejas con los `DROP TABLE` del bloque 8 de ese archivo.

**Snowflake.** `make migrar-clase07` (con `make snowflake`) crea los esquemas `DEV`, `PROD`, `CONTROL_DEV` y `CONTROL_PROD` y los roles `BIGDATA_DEV` y `BIGDATA_PROD`.

<a id="copiar-crudo-a-dev"></a>
### Opcional: que dev no descargue enero otra vez

La primera vez, el paso bronze de dev baja enero (~450 MB de viajes, el clima y las zonas) a `dev/bronze/_crudo/`. Si ya tienes el crudo en `prod/bronze/_crudo/`, puedes copiar solo esos archivos y dev los encuentra y no descarga nada:

```bash
cd ~/bigdata
LAKE="bigdata-lake-$(aws sts get-caller-identity --query Account --output text)-us-east-2"
aws s3 cp "s3://$LAKE/prod/bronze/_crudo/fhvhv/mes=2024-01/" "s3://$LAKE/dev/bronze/_crudo/fhvhv/mes=2024-01/" --recursive --only-show-errors
aws s3 cp "s3://$LAKE/prod/bronze/_crudo/clima/mes=2024-01/" "s3://$LAKE/dev/bronze/_crudo/clima/mes=2024-01/" --recursive --only-show-errors
aws s3 cp "s3://$LAKE/prod/bronze/_crudo/taxi_zones/" "s3://$LAKE/dev/bronze/_crudo/taxi_zones/" --recursive --only-show-errors
```

Es una copia puntual de archivos crudos que nunca cambian. No sustituye al paso bronze: ese sigue escribiendo el lote en Parquet en `dev/bronze/`.

<a id="errores"></a>
## Errores comunes

| Lo que ves | Causa | Qué hacer |
|---|---|---|
| `Falta la variable de entorno LAKE_BUCKET (nombre del bucket del lake) para armar las rutas de S3` | Se pidió una ruta de `dev` o `prod` y no hay bucket | En el Code Editor: `cd ~/bigdata && export LAKE_BUCKET=bigdata-lake-<CUENTA>-us-east-2`. En Glue lo pone Terraform (`--lake-bucket`) |
| `No hay ningún lote completo en s3://<LAKE>/dev/bronze/...` | Dev solo lee `dev/bronze/`, que está vacío hasta que dev corra su paso `bronze` | Corre `cd ~/bigdata && make correr PASO=bronze`. Ver [problemas.md](problemas.md#p-sin-lote-en-dev) |
| Un job de Glue falla con `AccessDenied` sobre `bronze/` o `muestra/` de la raíz | Un deploy a medias: el rol nuevo ya no accede a la raíz, pero el código que corre es el anterior | `cd ~/bigdata && git pull && make migrar-clase07` |
| Athena devuelve 0 filas | La tabla apunta a otro entorno, o ese entorno no ha corrido el paso | Corre el bloque 7 de `01_tablas.sql`: `"$path"` muestra de qué carpeta lee |
| `make doctor` avisa `Quedan carpetas del diseño anterior` | `bronze/`, `muestra/`, `silver/` o `gold/` siguen en la raíz | [Migrar](#migrar). No es un fallo |
| `La ruta ... no está dentro de ...: dev y prod no se mezclan` | Alguien armó una ruta a mano y salió de la carpeta de su entorno | Revisa el cambio: toda ruta debe salir de `ruta_lake` |

<a id="diseno"></a>
## Por qué está diseñado así

- **Entorno primero, capa después (`dev/bronze/`, no `bronze/dev/`).** Todo lo de un entorno queda bajo un solo prefijo. Sirve para ver de un vistazo qué ocupa dev, para borrarlo entero con un comando, y para escribir una política de IAM por entorno si algún día se separan los roles. También deja intactos `dev/silver`, `dev/gold`, `prod/silver` y `prod/gold`, que es lo que ya leen los stages de Snowflake.
- **Bronze duplicado entre dev y prod.** Cuesta almacenamiento (el crudo de un mes pesa ~450 MB) y una descarga la primera vez en dev. A cambio, nada que corra en dev puede cambiar la entrada de prod. Es el requisito del curso, y el costo es pequeño frente a un lote de prod que cambia sin que nadie lo decida.
- **Ya no hay muestra.** Dev puede correr con un `limite` de 1 000 o 100 000 filas por fuente (siempre las mismas, para que las corridas se puedan comparar), así que no hace falta una copia reducida de los datos.
- **Silver es el espejo de bronze y se organiza por `mes=`.** Una tabla por fuente, con el mismo nombre, sin join. La regla `mes=AAAA-MM` aplica ahora a bronze, silver y gold.
- **`gold/` y `silver/` de la raíz desaparecen del pipeline.** El stage `BIGDATA.GOLD.LAKE_GOLD` de Snowflake todavía apunta a `s3://<LAKE>/gold/` para las sesiones de SQL; no se toca aquí porque cambiarlo es un cambio de Terraform de Snowflake para cuentas ya desplegadas.
