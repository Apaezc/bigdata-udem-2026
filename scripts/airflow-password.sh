#!/usr/bin/env bash
# Muestra las credenciales de administrador de Airflow guardadas en Secrets Manager.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

requerir aws jq
SECRETO="${PREFIX}/airflow-admin"
VALOR="$(aws secretsmanager get-secret-value --secret-id "$SECRETO" \
  --query SecretString --output text 2>/dev/null)" \
  || error "No se pudo leer el secreto $SECRETO."

if jq -e 'type == "object"' >/dev/null 2>&1 <<< "$VALOR"; then
  USUARIO="$(jq -r '.username // .user // "admin"' <<< "$VALOR")"
  CLAVE="$(jq -r '.password // empty' <<< "$VALOR")"
  [[ -n "$CLAVE" ]] || error "El secreto $SECRETO no contiene el campo 'password'."
else
  USUARIO="admin"
  CLAVE="$VALOR"
fi

echo "Usuario:    $USUARIO"
echo "Contraseña: $CLAVE"
