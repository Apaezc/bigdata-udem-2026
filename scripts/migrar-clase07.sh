#!/usr/bin/env bash
# Pasa tu cuenta del diseño de las clases 1 a 6 al de la clase 7. Es idempotente: puedes repetirlo.
#   0. Revisión (cuenta, bucket, sin merge de git a medias)
#   1. S3: mueve SOLO el crudo de bronze/ (raíz) a prod/bronze/; borra muestra/ y los silver/gold viejos
#   2. Snowflake: DROP de BIGDATA.PROD.DAILY_ZONE_METRICS con el rol de dev
#   3. Infraestructura: make snowflake (esquemas, roles, tablas de control, secreto de prod)
#   4. Spark: make jars-s3a
#   5. Airflow del Code Editor: reinicio
#   6. Comprobación: make doctor y make rutas
# Uso: cd ~/bigdata && make migrar-clase07
# MIGRAR_CONFIRMADO=<cuenta> salta la pregunta (solo para el ensayo del instructor).
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

requerir aws jq make
cd "$ROOT_DIR" || exit 1

# --- 0. Revisión ---------------------------------------------------------------------------------
msg "Paso 0 de 6: revisión"
exigir_cuenta
LAKE="$(lake_bucket)"
echo "  Bucket del lake: s3://$LAKE/"

if [[ -f "$ROOT_DIR/.git/MERGE_HEAD" ]]; then
  echo "Tienes un merge de git a medias. Termínalo antes de migrar:" >&2
  echo "  cd ~/bigdata" >&2
  echo "  git status                       # mira qué archivos tienen conflicto" >&2
  echo "  git checkout --theirs <archivo>  # para los de la casa (src/, airflow/, scripts/, tests/, Makefile)" >&2
  echo "  git add -A && git commit -m \"Trae la clase 7 de la casa\"" >&2
  echo "Detalle: curso/clase07/README.md (sección «Paso 2 · Traer el código nuevo a tu fork»)." >&2
  exit 1
fi

echo
echo "Esto va a hacer, en la cuenta $CUENTA_AWS:"
echo "  1. mover el crudo de s3://$LAKE/bronze/ a s3://$LAKE/prod/bronze/ (los lotes viejos no se tocan)"
echo "     y borrar s3://$LAKE/muestra/"
echo "  2. borrar la tabla vieja BIGDATA.PROD.DAILY_ZONE_METRICS en Snowflake"
echo "  3. correr 'make snowflake' (te va a pedir el 'yes' de Terraform)"
echo "  4. bajar los jars de Spark (make jars-s3a) y reiniciar el Airflow del Code Editor"
if [[ "${MIGRAR_CONFIRMADO:-}" == "$CUENTA_AWS" ]]; then
  msg "Confirmado por MIGRAR_CONFIRMADO."
else
  confirmar "Para seguir, escribe el número de esta cuenta de AWS." "$CUENTA_AWS"
fi

# --- 1. S3 ---------------------------------------------------------------------------------------
msg "Paso 1 de 6: S3"
if s3_tiene_objetos "$LAKE" "bronze/"; then
  echo "  Moviendo el crudo: s3://$LAKE/bronze/  ->  s3://$LAKE/prod/bronze/   (puede tardar varios minutos)"
  aws s3 mv "s3://$LAKE/bronze/" "s3://$LAKE/prod/bronze/" --recursive --exclude '*/lote=*' --only-show-errors
  echo "  Los lotes viejos (lote=...) se quedaron en s3://$LAKE/bronze/ sin usar; puedes borrarlos después del curso."
else
  echo "  No hay s3://$LAKE/bronze/ en la raíz: nada que mover."
fi

if s3_tiene_objetos "$LAKE" "muestra/"; then
  echo "  Borrando s3://$LAKE/muestra/ (la muestra ya no existe)"
  aws s3 rm "s3://$LAKE/muestra/" --recursive --only-show-errors
else
  echo "  No hay s3://$LAKE/muestra/: nada que borrar."
fi

for capa in silver gold; do
  if ! s3_tiene_objetos "$LAKE" "$capa/"; then
    echo "  No hay s3://$LAKE/$capa/ en la raíz: nada que revisar."
    continue
  fi
  claves="$(aws s3api list-objects-v2 --bucket "$LAKE" --prefix "$capa/" \
    --query 'Contents[].Key' --output text 2>/dev/null | tr '\t' '\n')"
  con_datos="$(printf '%s\n' "$claves" | grep -vE '(/|^)(_SUCCESS|_LOTE_COMPLETO)$' || true)"
  if [[ -z "$con_datos" ]]; then
    echo "  s3://$LAKE/$capa/ solo tiene marcadores: lo borro."
    aws s3 rm "s3://$LAKE/$capa/" --recursive --only-show-errors
  else
    aviso "s3://$LAKE/$capa/ tiene datos del diseño anterior; no lo borro. Ya nadie lo lee (se puede borrar después del curso)."
  fi
done

# --- 2. Snowflake: tabla vieja ------------------------------------------------------------------
msg "Paso 2 de 6: Snowflake, tabla vieja"
PY="$ROOT_DIR/.venv/bin/python"
if [[ ! -x "$PY" ]]; then
  aviso "No existe .venv: salto el DROP de BIGDATA.PROD.DAILY_ZONE_METRICS. Corre 'cd ~/bigdata && make reparar-entorno' y repite este comando."
else
  # Con el rol de dev (secreto <PREFIX>/snowflake), nunca con connections.toml (ACCOUNTADMIN).
  if SECRETO="$SECRETO_SNOWFLAKE" "$PY" - <<'PYEOF'
import json, os, subprocess, sys
import boto3
import snowflake.connector
from cryptography.hazmat.primitives import serialization

secreto = os.environ["SECRETO"]
try:
    texto = boto3.client("secretsmanager").get_secret_value(SecretId=secreto)["SecretString"]
    c = json.loads(texto)
    extra = c["extra"]
    llave = serialization.load_pem_private_key(extra["private_key_content"].encode(), password=None)
    der = llave.private_bytes(
        serialization.Encoding.DER,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    )
    con = snowflake.connector.connect(
        user=c["login"], account=extra["account"], warehouse=extra["warehouse"],
        database=extra["database"], role=extra["role"], private_key=der,
    )
except Exception as e:  # noqa: BLE001
    print(f"No pude conectarme a Snowflake con el secreto {secreto}: {e}", file=sys.stderr)
    sys.exit(2)
try:
    con.cursor().execute("DROP TABLE IF EXISTS BIGDATA.PROD.DAILY_ZONE_METRICS")
    print("  DROP TABLE IF EXISTS BIGDATA.PROD.DAILY_ZONE_METRICS: listo (rol " + extra["role"] + ")")
finally:
    con.close()
PYEOF
  then
    :
  else
    aviso "No se pudo borrar BIGDATA.PROD.DAILY_ZONE_METRICS (normal si nunca existió en tu cuenta, o si el rol de dev no la ve). No hace daño: la tabla vieja no se usa. Sigue con la migración; no hace falta avisar a nadie."
  fi
fi

# --- 3. Infraestructura -------------------------------------------------------------------------
msg "Paso 3 de 6: infraestructura (make snowflake)"
echo "  Terraform te va a mostrar un plan y a pedir 'yes'. Mira la línea del resumen:"
echo "    Plan: N to add, N to change, 0 to destroy."
echo "  Si dice cualquier número distinto de 0 en 'destroy', escribe 'no' y avisa al instructor: no lo juzgues tú."
make snowflake

# --- 4. Spark -----------------------------------------------------------------------------------
msg "Paso 4 de 6: jars de Spark para S3"
make jars-s3a

# --- 5. Airflow del Code Editor -----------------------------------------------------------------
msg "Paso 5 de 6: Airflow del Code Editor"
make airflow-local-down
make airflow-local

# --- 6. Comprobación ----------------------------------------------------------------------------
msg "Paso 6 de 6: comprobación"
make doctor
make rutas
echo
echo "Raíz del bucket (debe verse code/ dags/ logs/ prod/; dev/ y tmp/ aparecen cuando corras algo):"
aws s3 ls "s3://$LAKE/"
echo
msg "Migración terminada."
echo "Siguiente:  sigue con la clase: resetear_entorno dev"
