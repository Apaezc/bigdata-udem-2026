#!/usr/bin/env bash
# Diagnóstico del entorno: versiones, AWS, Snowflake, Terraform y estado OIDC.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

FALLOS=0
ok() { echo "[OK]     $*"; }
fallo() { echo "[FALLO]  $*"; FALLOS=$((FALLOS + 1)); }
info() { echo "[INFO]   $*"; }

msg "Herramientas y versiones"
for cmd in python3 java aws terraform snow jq zip; do
  if command -v "$cmd" >/dev/null 2>&1; then
    # En macOS /usr/bin/java existe aunque no haya JDK (sale con error): no abortar el diagnóstico.
    case "$cmd" in
      java) version="$(java -version 2>&1 | head -1)" || version="" ;;
      terraform) version="$(terraform version | head -1)" || version="" ;;
      python3) version="$(python3 --version 2>&1)" || version="" ;;
      *) version="$("$cmd" --version 2>&1 | head -1)" || version="" ;;
    esac
    if [[ "$cmd" == java && "$version" != *version* ]]; then
      fallo "java no funciona (¿falta instalar Java 17?): $version"
    else
      ok "$cmd: $version"
    fi
  else
    fallo "$cmd no instalado"
  fi
done
if command -v session-manager-plugin >/dev/null 2>&1; then
  ok "session-manager-plugin instalado"
else
  info "session-manager-plugin no instalado (solo para make airflow-tunel)"
fi

msg "Configuración"
info "PREFIX=$PREFIX  AWS_REGION=$AWS_REGION"

msg "AWS"
if CUENTA="$(account_id 2>/dev/null)" && [[ -n "$CUENTA" ]]; then
  ok "aws sts get-caller-identity: cuenta $CUENTA"
else
  fallo "aws sts get-caller-identity falló (revisa credenciales o perfil)"
  CUENTA=""
fi

if [[ -n "$CUENTA" ]]; then
  if aws s3api head-bucket --bucket "$(tfstate_bucket)" >/dev/null 2>&1; then
    ok "Bucket de estado de Terraform accesible"
  else
    fallo "Bucket de estado $(tfstate_bucket) no accesible (¿bootstrap desplegado?)"
  fi
fi

msg "Snowflake"
if snow connection test >/dev/null 2>&1; then
  ok "snow connection test"
else
  fallo "snow connection test falló (revisa ~/.snowflake/config.toml)"
fi

msg "Estado OIDC para GitHub Actions"
if [[ -n "$CUENTA" ]]; then
  OIDC_OUT="$(aws iam list-open-id-connect-providers --output text 2>&1 || true)"
  if grep -q 'token.actions.githubusercontent.com' <<< "$OIDC_OUT"; then
    ok "Proveedor OIDC de GitHub existe"
  elif grep -q 'AccessDenied' <<< "$OIDC_OUT"; then
    # El rol del Code Editor no puede listar proveedores OIDC; el CI lo comprueba de verdad.
    info "No se puede listar el proveedor OIDC con este rol (normal en Code Editor)"
  else
    fallo "No existe el proveedor OIDC de GitHub (ejecuta el stack de bootstrap)"
  fi
  if aws iam get-role --role-name "${PREFIX}-github-actions" >/dev/null 2>&1; then
    ok "Rol ${PREFIX}-github-actions existe"
  else
    fallo "No existe el rol ${PREFIX}-github-actions"
  fi
fi
info "Verifica también el secret AWS_ROLE_ARN del fork (Settings -> Secrets and variables -> Actions)."
info "Si OIDC falla en CI, ejecuta el workflow 'Debug OIDC' para ver el claim sub real."

echo
if (( FALLOS == 0 )); then
  msg "Diagnóstico sin fallos"
else
  error "Diagnóstico con $FALLOS fallo(s). Revisa los puntos marcados como FALLO."
fi
