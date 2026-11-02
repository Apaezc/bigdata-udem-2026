#!/usr/bin/env bash
# Configura la conexión por defecto de Snowflake CLI (snow) con autenticación por llave (SNOWFLAKE_JWT):
#   - genera la llave privada en ~/.snowflake/keys/<usuario>_key.p8 (chmod 600) si no existe;
#   - escribe la sección [default] en ~/.snowflake/connections.toml sin tocar las demás;
#   - imprime el ALTER USER que registra la clave pública en Snowsight y espera Enter;
#   - vuelve a probar con 'snow connection test'.
# La llave privada nunca se imprime. Uso: make snowflake-conexion (requiere terminal interactiva).
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SF_DIR="$HOME/.snowflake"
SF_CONEXIONES="$SF_DIR/connections.toml"
SF_LLAVES="$SF_DIR/keys"
RE_CUENTA='^[A-Za-z0-9._-]+$'
RE_USUARIO='^[A-Za-z0-9._@-]+$'

bloque_default() {
  # Uso: bloque_default <cuenta> <login> <ruta-llave>. Imprime la sección [default].
  # Sin warehouse: BIGDATA_WH no existe hasta 'make snowflake' y snow fallaría al conectar.
  local cuenta="$1" usuario="$2" llave="$3"
  llave="${llave//\\/\\\\}"
  llave="${llave//\"/\\\"}"
  cat <<EOF
[default]
account = "$cuenta"
user = "$usuario"
authenticator = "SNOWFLAKE_JWT"
private_key_file = "$llave"
role = "ACCOUNTADMIN"
EOF
}

seccion_default() {
  # Imprime solo la sección [default] del archivo $1 (vacío si no existe).
  awk '
    /^[[:space:]]*\[/ { en = ($0 ~ /^[[:space:]]*\[default\][[:space:]]*(#.*)?$/) }
    en { print }
  ' "$1"
}

quitar_default() {
  # Imprime el archivo $1 sin su sección [default]; el resto de secciones se conserva.
  awk '
    /^[[:space:]]*\[/ { en = ($0 ~ /^[[:space:]]*\[default\][[:space:]]*(#.*)?$/) }
    !en { print }
  ' "$1"
}

escribir_conexion() {
  # Uso: escribir_conexion <cuenta> <usuario> <ruta-llave>. Escribe [default] en connections.toml.
  # Si ya hay una [default] distinta, pregunta antes de reemplazarla (con copia de seguridad).
  local cuenta="$1" usuario="$2" llave="$3" bloque actual tmp respuesta respaldo
  bloque="$(bloque_default "$cuenta" "$usuario" "$llave")"
  mkdir -p "$SF_DIR"
  tmp="$(mktemp "$SF_DIR/connections.XXXXXX")"

  if [[ -f "$SF_CONEXIONES" ]]; then
    actual="$(seccion_default "$SF_CONEXIONES")"
    if [[ "$actual" == "$bloque" ]]; then
      rm -f "$tmp"
      msg "La sección [default] de $SF_CONEXIONES ya tiene estos datos."
      return 0
    fi
    if [[ -n "$actual" ]]; then
      echo "Ya hay una sección [default] en $SF_CONEXIONES (no se muestra: puede contener credenciales)."
      read -r -p "¿Reemplazarla? Se guardará una copia de seguridad [s/N]: " respuesta
      if [[ ! "$respuesta" =~ ^[sSyY]$ ]]; then
        rm -f "$tmp"
        error "Cancelado: se conserva la sección [default] existente."
      fi
      respaldo="$SF_CONEXIONES.bak.$(date +%Y%m%d%H%M%S)"
      cp "$SF_CONEXIONES" "$respaldo"
      chmod 600 "$respaldo"
      msg "Copia de seguridad: $respaldo"
      quitar_default "$SF_CONEXIONES" > "$tmp"
    else
      cat "$SF_CONEXIONES" > "$tmp"
    fi
    if [[ -s "$tmp" ]]; then
      printf '\n' >> "$tmp"
    fi
  fi

  printf '%s\n' "$bloque" >> "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$SF_CONEXIONES"
  chmod 600 "$SF_CONEXIONES"
  msg "Sección [default] escrita en $SF_CONEXIONES"
}

generar_llave() {
  # Uso: generar_llave <ruta>. Crea una llave RSA 2048 PKCS8 sin passphrase con chmod 600.
  local llave="$1" tmp
  mkdir -p "$(dirname "$llave")"
  chmod 700 "$(dirname "$llave")"
  tmp="$llave.tmp.$$"
  umask 077
  if ! openssl genrsa 2048 2>/dev/null | openssl pkcs8 -topk8 -inform PEM -out "$tmp" -nocrypt 2>/dev/null; then
    rm -f "$tmp"
    error "No se pudo generar la llave con openssl."
  fi
  chmod 600 "$tmp"
  mv "$tmp" "$llave"
}

clave_publica_linea() {
  # Imprime la clave pública de la llave $1 en una sola línea, sin cabeceras BEGIN/END.
  # -passin pass: evita que openssl pida passphrase si la llave estuviera cifrada.
  openssl rsa -in "$1" -passin pass: -pubout 2>/dev/null </dev/null | grep -v -- '-----' | tr -d '\n'
}

pedir() {
  # Uso: pedir <texto> <regex>. Repite hasta que la respuesta cumpla la regex; imprime la respuesta sin espacios.
  local texto="$1" re="$2" valor=""
  while [[ ! "$valor" =~ $re ]]; do
    read -r -p "$texto" valor
    valor="$(tr -d '[:space:]' <<< "$valor")"
  done
  echo "$valor"
}

main() {
  requerir snow openssl

  msg "Probando la conexión por defecto de snow"
  if snow connection test >/dev/null 2>&1; then
    msg "La conexión por defecto de Snowflake ya funciona. No hay nada que configurar."
    return 0
  fi
  aviso "La conexión por defecto de snow no funciona todavía; se configura ahora."
  [[ -t 0 ]] || error "Ejecuta 'make snowflake-conexion' desde una terminal interactiva."

  echo
  echo "Para saber tus datos, en Snowsight abre una hoja (+ > SQL Worksheet), pega esto y pulsa Run All:"
  echo
  echo "  USE ROLE ACCOUNTADMIN;"
  echo "  SHOW USERS;"
  echo "  SELECT CURRENT_ORGANIZATION_NAME() || '-' || CURRENT_ACCOUNT_NAME() AS account_identifier,"
  echo "         \"name\" AS usuario, \"login_name\" AS login"
  echo "  FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE \"name\" = CURRENT_USER();"
  echo
  echo "Ejemplo: ACCOUNT_IDENTIFIER = ABCDEFG-XY12345 | USUARIO = jperez | LOGIN = JPEREZ@GMAIL.COM"
  echo "(USUARIO y LOGIN pueden ser distintos: se piden los dos.)"
  local cuenta usuario login llave pub
  cuenta="$(pedir "Account identifier (ORGNAME-ACCOUNTNAME): " "$RE_CUENTA")"
  usuario="$(pedir "USUARIO (columna USUARIO): " "$RE_USUARIO")"
  login="$(pedir "LOGIN (columna LOGIN): " "$RE_USUARIO")"
  llave="$SF_LLAVES/${usuario}_key.p8"

  if [[ -e "$llave" ]]; then
    msg "Se usa la llave existente $llave (no se sobrescribe)."
  else
    msg "Generando la llave privada en $llave"
    generar_llave "$llave"
  fi

  # La conexión (JWT) usa el login; el ALTER USER, el nombre del usuario.
  escribir_conexion "$cuenta" "$login" "$llave"

  pub="$(clave_publica_linea "$llave")" && [[ -n "$pub" ]] \
    || error "No se pudo leer la clave pública de $llave (¿llave cifrada o dañada?)."

  echo
  echo "Último paso: en Snowsight, en una hoja (+ > SQL Worksheet), pega estas dos líneas juntas y"
  echo "ejecútalas con 'Run All' (flecha junto a ▶):"
  echo
  echo "USE ROLE ACCOUNTADMIN;"
  echo "ALTER USER \"$usuario\" SET RSA_PUBLIC_KEY='$pub';"
  echo
  read -r -p "Cuando la hayas ejecutado, pulsa Enter para probar la conexión... " _pausa

  msg "Probando con snow connection test"
  if snow connection test; then
    msg "Conexión configurada. Siguiente paso: make setup"
  else
    error "snow connection test sigue fallando. Revisa el account identifier, el usuario y que el ALTER USER se ejecutó como ACCOUNTADMIN; luego repite 'make snowflake-conexion'."
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
