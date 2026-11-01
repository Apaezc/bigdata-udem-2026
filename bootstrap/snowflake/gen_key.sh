#!/usr/bin/env bash
# Genera el par de llaves RSA (PKCS8, sin passphrase) del usuario de servicio de Terraform.
#
# Uso: bootstrap/snowflake/gen_key.sh [NOMBRE_USUARIO]   (por defecto TERRAFORM_SVC)
#
# Las llaves quedan fuera del repo, en ~/.snowflake/keys/:
#   <usuario>_rsa_key.p8   privada (no compartir, no versionar)
#   <usuario>_rsa_key.pub  pública
# Imprime la clave pública en una línea y el ALTER USER correspondiente.
set -euo pipefail

USER_NAME="${1:-TERRAFORM_SVC}"

if [[ ! "${USER_NAME}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
  echo "Nombre de usuario inválido: ${USER_NAME}. Usar solo letras, números y guion bajo." >&2
  exit 1
fi

KEY_DIR="${HOME}/.snowflake/keys"
BASE="$(printf '%s' "${USER_NAME}" | tr '[:upper:]' '[:lower:]')"
PRIV="${KEY_DIR}/${BASE}_rsa_key.p8"
PUB="${KEY_DIR}/${BASE}_rsa_key.pub"

if [[ -e "${PRIV}" ]]; then
  echo "Ya existe ${PRIV}. No se sobrescribe." >&2
  printf '%s\n' "Para ver la clave pública: grep -v -- '-----' ${PUB} | tr -d '\\n'" >&2
  exit 1
fi

mkdir -p "${KEY_DIR}"
chmod 700 "${KEY_DIR}"
umask 077

openssl genrsa 2048 2>/dev/null | openssl pkcs8 -topk8 -inform PEM -out "${PRIV}" -nocrypt
chmod 600 "${PRIV}"
openssl rsa -in "${PRIV}" -pubout -out "${PUB}" 2>/dev/null

PUB_LINE="$(grep -v -- '-----' "${PUB}" | tr -d '\n')"
FINGERPRINT="SHA256:$(openssl pkey -pubin -in "${PUB}" -outform DER | openssl dgst -sha256 -binary | openssl enc -base64)"

echo "Llave privada: ${PRIV}"
echo "Llave pública: ${PUB}"
echo "Fingerprint:   ${FINGERPRINT}  (debe coincidir con RSA_PUBLIC_KEY_FP en DESC USER)"
echo
echo "1) Clave pública (una línea). Pegarla en RSA_PUBLIC_KEY de bootstrap/snowflake/01_admin.sql:"
echo "${PUB_LINE}"
echo
echo "2) Si el usuario ya existe, ejecutar en Snowsight como ACCOUNTADMIN:"
echo "ALTER USER ${USER_NAME} SET RSA_PUBLIC_KEY = '${PUB_LINE}';"
