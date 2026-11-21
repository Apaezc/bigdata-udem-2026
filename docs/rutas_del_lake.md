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
<capa>     bronze | silver | gold | muestra
```

Tres consecuencias:

1. Un job con `--env dev` solo lee y escribe bajo `dev/`. Uno con `--env prod`, solo bajo `prod/`. No existe ninguna carpeta que los dos usen.
2. Las rutas se arman en un solo lugar: la función `ruta_lake` de `src/pipeline/settings.py`. Los archivos YAML de `config/` ya no llevan rutas, y ningún otro módulo escribe un `s3://` a mano.
3. Los prefijos `code/`, `dags/`, `logs/` y `tmp/` no son de ningún entorno. Son del propio lake: el código que ejecuta Glue, los DAGs, los logs de Spark y los temporales.

En local (tu Code Editor) los datos no están en S3 sino en el disco, en `~/bigdata/lake/`.

<a id="quien"></a>
## Quién lee y escribe qué

| Quién | Entorno | Lee | Escribe |
|---|---|---|---|
| `make muestra` (Glue `large` y `medium`) | prod | el crudo de las fuentes en internet y `prod/bronze/` | `prod/bronze/` (el año completo) y `prod/muestra/` |
| DAG `pipeline_taxi` en el Airflow del Code Editor, `computo = glue_*` | dev | las fuentes y `dev/bronze/`, `dev/silver/` | `dev/bronze/`, `dev/silver/` y `dev/gold/`; carga en `BIGDATA.DEV` |
| DAG `pipeline_taxi` en la VM de Airflow | prod | las fuentes y `prod/bronze/`, `prod/silver/` | `prod/bronze/`, `prod/silver/` y `prod/gold/`; carga en `BIGDATA.PROD` |
| `make run-local` y `computo = spark_local` | local | `~/bigdata/lake/muestra` (la baja una vez de `prod/muestra/` o del bucket público) | `~/bigdata/lake/silver` y `~/bigdata/lake/gold` |
| Athena (clase 7) | el de la tabla | lo que declara cada tabla | nada (solo resultados en `tmp/athena/`) |
| Snowflake (`COPY INTO`) | dev o prod | `dev/gold/` o `prod/gold/` (los stages de `infra/snowflake`) | nada en S3 |

Las carpetas que cuelgan de cada entorno:

```text
s3://<LAKE>/
  dev/                                     solo lo toca dev
    bronze/
      _crudo/<fuente>/mes=AAAA-MM/<archivo>   el archivo tal como se descargó
      fhvhv/mes=AAAA-MM/lote=<id>/            Parquet con metadatos
      clima/mes=AAAA-MM/lote=<id>/
      taxi_zones/lote=<id>/
    silver/fhvhv_trips/pickup_date=AAAA-MM-DD/
    gold/daily_zone_metrics/mes=AAAA-MM/
    muestra/<fuente>/...                      misma forma que bronze, sin _crudo/
  prod/                                    solo lo toca prod (misma forma que dev)
    bronze/  silver/  gold/  muestra/
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

Sin `ENTORNO` imprime los tres entornos. En un notebook es `pio.donde_estoy("dev")` (con `from pipeline import io as pio`). La salida es esta (la cuenta será la tuya):

```text
DÓNDE ESTOY | entorno: dev | los datos están en S3
Bucket del lake  : bigdata-lake-123456789012-us-east-2
Carpeta de dev   : s3://bigdata-lake-123456789012-us-east-2/dev
Este entorno solo lee y escribe bajo dev/. No toca prod/.

CAPA     TABLA               DÓNDE  RUTA COMPLETA                                                         CARPETAS DENTRO DE LA TABLA
bronze   fhvhv               S3     s3://bigdata-lake-123456789012-us-east-2/dev/bronze/fhvhv             mes=AAAA-MM/lote=<id>/
bronze   clima               S3     s3://bigdata-lake-123456789012-us-east-2/dev/bronze/clima             mes=AAAA-MM/lote=<id>/
bronze   taxi_zones          S3     s3://bigdata-lake-123456789012-us-east-2/dev/bronze/taxi_zones        lote=<id>/
bronze   _crudo              S3     s3://bigdata-lake-123456789012-us-east-2/dev/bronze/_crudo            <fuente>/mes=AAAA-MM/<archivo>
silver   fhvhv_trips         S3     s3://bigdata-lake-123456789012-us-east-2/dev/silver/fhvhv_trips       pickup_date=AAAA-MM-DD/
gold     daily_zone_metrics  S3     s3://bigdata-lake-123456789012-us-east-2/dev/gold/daily_zone_metrics  mes=AAAA-MM/
muestra  fhvhv               S3     s3://bigdata-lake-123456789012-us-east-2/dev/muestra/fhvhv            mes=AAAA-MM/lote=<id>/
muestra  clima               S3     s3://bigdata-lake-123456789012-us-east-2/dev/muestra/clima            mes=AAAA-MM/lote=<id>/
muestra  taxi_zones          S3     s3://bigdata-lake-123456789012-us-east-2/dev/muestra/taxi_zones       lote=<id>/

Del lake, no de un entorno: code/, dags/, logs/, tmp/
```

**2. Cada lectura y escritura dice su ruta completa.** Las funciones de la casa (`pio.leer_*`, `pio.escribir_*`, `pio.borrar_particiones`, `pio.publicar`, `pio.copiar`, `pio.borrar`, `pio.tamano_mb`) escriben una línea con el verbo y la ruta antes de actuar. En un notebook aparece en la salida de la celda; en una corrida de Glue o de Airflow, en el log de la tarea:

```text
LEE      s3://bigdata-lake-123456789012-us-east-2/dev/bronze/fhvhv/mes=2024-01/lote=20261120T150102Z_a3f9c1  (viajes)
ESCRIBE  s3://bigdata-lake-123456789012-us-east-2/dev/silver/fhvhv_trips  (silver, meses 2024-01)
BORRA    s3://bigdata-lake-123456789012-us-east-2/dev/gold/daily_zone_metrics/mes=2024-01*
```

Además, cada corrida de `pipeline.run` empieza imprimiendo la tabla del paso anterior.

**3. Lo que hay hoy en el bucket.** `make estado` lista, por entorno y capa, si la carpeta tiene datos. `make doctor` y `make deploy` avisan si en la raíz del bucket quedan carpetas del diseño anterior:

```bash
cd ~/bigdata
make estado
```

```text
==> Rutas del lake (una carpeta por entorno y capa)
  Bucket del lake: bigdata-lake-123456789012-us-east-2
  s3://bigdata-lake-123456789012-us-east-2/dev/bronze/  con datos
  s3://bigdata-lake-123456789012-us-east-2/dev/muestra/  vacía
  ...
```

<a id="cambio"></a>
## Qué cambió: antes y ahora

| Antes | Ahora | Quién la escribe |
|---|---|---|
| `bronze/_crudo/...` y `bronze/<fuente>/.../lote=<id>/` (compartido) | `prod/bronze/...` y `dev/bronze/...`, una por entorno | prod: `make muestra` y el DAG de la VM. dev: el DAG del Code Editor |
| `muestra/` | `prod/muestra/` | `make muestra` |
| `dev/silver/`, `dev/gold/` | igual: `dev/silver/`, `dev/gold/` | dev |
| `prod/silver/`, `prod/gold/` | igual: `prod/silver/`, `prod/gold/` | prod |
| `silver/` y `gold/` en la raíz (vacías) | desaparecen | (las creaba Terraform; ya no) |
| `code/`, `dags/`, `logs/`, `tmp/` | igual | `make deploy`, Glue, Athena |

Lo que no cambia: las carpetas `dev/silver`, `dev/gold`, `prod/silver` y `prod/gold` ya cumplían la regla, así que los stages de Snowflake (`BIGDATA.DEV.LAKE_GOLD` y `BIGDATA.PROD.LAKE_GOLD`) y `copy_gold.sql` siguen funcionando sin tocarlos.

Lo que sí cambia en la infraestructura al hacer `make deploy`:

- El rol de Glue (`<prefix>-glue-exec`) ya solo accede a `dev/`, `prod/`, `code/`, `tmp/` y `logs/`. Pierde el acceso a `bronze/`, `muestra/`, `silver/` y `gold/` de la raíz.
- Terraform deja de manejar los marcadores vacíos `bronze/`, `silver/` y `gold/` de la raíz (sin borrarlos, para que `make deploy` no se detenga por la guardia de destrucción) y crea `dev/` y `prod/`.

<a id="migrar"></a>
## Migrar un bucket del diseño anterior

Un bucket "del diseño anterior" tiene `bronze/` y `muestra/` en la raíz. Hay dos caminos. En los dos, el primer paso es el mismo, y va antes de tocar S3: actualizar el código que ejecuta Glue.

```bash
cd ~/bigdata
git pull
make deploy
```

`make deploy` sube el código nuevo (`code/pipeline.zip`) y actualiza el rol de Glue. Sin este paso, Glue sigue ejecutando el código viejo, que escribe en las carpetas de antes, y lo que muevas o regeneres no coincide con lo que Glue lee.

**Camino A: regenerar (recomendado en la cuenta de pruebas).** Borra lo viejo y vuelve a correr `make muestra`. El tiempo y el costo son los del [Paso 12 de la guía](guia.md#paso-12): descarga otra vez los ~5.4 GB del año.

```bash
cd ~/bigdata
LAKE="bigdata-lake-$(aws sts get-caller-identity --query Account --output text)-us-east-2"
aws s3 rm "s3://$LAKE/bronze/" --recursive --only-show-errors
aws s3 rm "s3://$LAKE/muestra/" --recursive --only-show-errors
aws s3 rm "s3://$LAKE/silver/" --recursive --only-show-errors
aws s3 rm "s3://$LAKE/gold/" --recursive --only-show-errors
make muestra
```

`aws s3 rm` con `--recursive` solo borra las claves que empiezan con ese prefijo: `s3://$LAKE/gold/` no toca `dev/gold/` ni `prod/gold/`. Si quieres empezar de cero también en silver y gold de los entornos, agrega `aws s3 rm "s3://$LAKE/dev/" --recursive` y lo mismo con `prod/`.

**Camino B: mover (conserva los datos y no vuelve a descargar nada).** `aws s3 mv` entre dos rutas de S3 copia del lado del servidor y borra el original, así que no pasa por tu máquina. El bronze pesa unos 31 GB, así que puede tardar varios minutos.

```bash
cd ~/bigdata
LAKE="bigdata-lake-$(aws sts get-caller-identity --query Account --output text)-us-east-2"
aws s3 mv "s3://$LAKE/bronze/" "s3://$LAKE/prod/bronze/" --recursive --only-show-errors
aws s3 mv "s3://$LAKE/muestra/" "s3://$LAKE/prod/muestra/" --recursive --only-show-errors
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

**Athena.** Las tablas de la clase 6 (`bronze_fhvhv`, `silver_fhvhv_trips`...) apuntan a las carpetas viejas y quedan vacías. La clase 7 trae tablas nuevas, con el entorno en el nombre (`prod_bronze_fhvhv`, `dev_silver_fhvhv_trips`): ejecuta `curso/clase07/athena/01_tablas.sql` y, si quieres, borra las viejas con los `DROP TABLE` del bloque 8 de ese archivo.

**Snowflake.** No hay nada que cambiar.

<a id="copiar-crudo-a-dev"></a>
### Opcional: que dev no descargue enero otra vez

La primera vez, la tarea `bronze` de dev baja enero (~450 MB de viajes, el clima y las zonas) a `dev/bronze/_crudo/`. Si ya tienes el año en `prod/bronze/`, puedes copiar solo esos archivos y dev los encuentra y no descarga nada:

```bash
cd ~/bigdata
LAKE="bigdata-lake-$(aws sts get-caller-identity --query Account --output text)-us-east-2"
aws s3 cp "s3://$LAKE/prod/bronze/_crudo/fhvhv/mes=2024-01/" "s3://$LAKE/dev/bronze/_crudo/fhvhv/mes=2024-01/" --recursive --only-show-errors
aws s3 cp "s3://$LAKE/prod/bronze/_crudo/clima/mes=2024-01/" "s3://$LAKE/dev/bronze/_crudo/clima/mes=2024-01/" --recursive --only-show-errors
aws s3 cp "s3://$LAKE/prod/bronze/_crudo/taxi_zones/" "s3://$LAKE/dev/bronze/_crudo/taxi_zones/" --recursive --only-show-errors
```

Es una copia puntual de archivos crudos que nunca cambian. No sustituye a la tarea `bronze`: esa sigue escribiendo el lote en Parquet con metadatos en `dev/bronze/`.

<a id="errores"></a>
## Errores comunes

| Lo que ves | Causa | Qué hacer |
|---|---|---|
| `Falta la variable de entorno LAKE_BUCKET (nombre del bucket del lake) para armar las rutas de S3` | Se pidió una ruta de `dev` o `prod` y no hay bucket | En el Code Editor: `cd ~/bigdata && export LAKE_BUCKET=bigdata-lake-<CUENTA>-us-east-2`. En Glue lo pone Terraform (`--lake-bucket`) |
| `No hay ningún lote completo en s3://<LAKE>/dev/bronze/...` | Dev solo lee `dev/bronze/`, que está vacío hasta que dev corra su paso `bronze` | Corre el DAG `pipeline_taxi` completo en dev. Ver [problemas.md](problemas.md#p-sin-lote-en-dev) |
| Un job de Glue falla con `AccessDenied` sobre `bronze/` o `muestra/` de la raíz | Un deploy a medias: el rol nuevo ya no accede a la raíz, pero `code/pipeline.zip` sigue siendo el código anterior | `cd ~/bigdata && git pull && make deploy` |
| Athena devuelve 0 filas | La tabla apunta a otro entorno, o ese entorno no ha corrido el paso | Corre el bloque 7 de `01_tablas.sql`: `"$path"` muestra de qué carpeta lee |
| `make doctor` avisa `Quedan carpetas del diseño anterior` | `bronze/`, `muestra/`, `silver/` o `gold/` siguen en la raíz | [Migrar](#migrar). No es un fallo |
| `La ruta ... no está dentro de ...: dev y prod no se mezclan` | Alguien cambió `settings.cargar` y una ruta del entorno salió de su carpeta | Revisa el cambio: toda ruta debe salir de `ruta_lake` |

<a id="diseno"></a>
## Por qué está diseñado así

- **Entorno primero, capa después (`dev/bronze/`, no `bronze/dev/`).** Todo lo de un entorno queda bajo un solo prefijo. Sirve para ver de un vistazo qué ocupa dev, para borrarlo entero con un comando, y para escribir una política de IAM por entorno si algún día se separan los roles. También deja intactos `dev/silver`, `dev/gold`, `prod/silver` y `prod/gold`, que es lo que ya leen los stages de Snowflake.
- **Bronze duplicado entre dev y prod.** Cuesta almacenamiento (el crudo del año pesa ~5.4 GB) y una descarga la primera vez en dev, que solo procesa enero. A cambio, nada que corra en dev puede cambiar la entrada de prod. Es el requisito del curso, y el costo es pequeño frente a un lote de prod que cambia sin que nadie lo decida.
- **La muestra vive en `prod/muestra/`.** `make muestra` corre con `--env prod`, porque parte del bronze del año completo, que está en `prod/bronze/`. La regla "un job escribe solo en su entorno" no tiene excepciones: el job de prod escribe en `prod/`. La única lectura que cruza es la de local, que no es un job de nube: baja la muestra una vez al disco y no escribe nada en S3. Si el curso prefiriera `dev/muestra/`, bastaría con que `make muestra` corriera el paso `muestra` con `--env dev` sobre un bronze de dev del año completo (cambiar `meses` de `dev.yaml` y `ENTORNO_DE_LA_MUESTRA` en `settings.py`).
- **Silver sigue particionado por `pickup_date`.** Cambiarlo a `mes=` es lógica de negocio de silver, no de rutas. La regla `mes=AAAA-MM` aplica a bronze, gold y muestra.
- **`gold/` y `silver/` de la raíz desaparecen del pipeline.** El stage `BIGDATA.GOLD.LAKE_GOLD` de Snowflake todavía apunta a `s3://<LAKE>/gold/` para las sesiones de SQL; no se toca aquí porque cambiarlo es un cambio de Terraform de Snowflake para cuentas ya desplegadas.
