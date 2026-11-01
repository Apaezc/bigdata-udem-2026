#!/usr/bin/env bash
# Carga en tu fork los secrets que necesitan los workflows (CI y Deploy), leyendo los outputs del
# stack de bootstrap: AWS_ROLE_ARN y TF_STATE_BUCKET. No hay que copiar nada a mano.
# Requiere gh autenticado con permiso sobre el fork (gh auth login). Se puede repetir sin problema.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

requerir aws gh git

if ! gh auth status >/dev/null 2>&1; then
  error "gh no está autenticado. Corre:\n  gh auth login --hostname github.com --git-protocol https --web\n(abre el enlace que muestra, pega el código y autoriza) y luego 'make secrets'."
fi

ORIGEN="$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null || true)"
REPO="$(sed -E 's#(\.git)?$##; s#^.*github\.com[:/]##' <<< "$ORIGEN")"
[[ "$REPO" == */* ]] || error "No se pudo leer el repo de 'git remote get-url origin' ($ORIGEN). Clona tu fork."

ROLE_ARN="$(stack_output GitHubActionsRoleArn)"
STATE_BUCKET="$(stack_output TfStateBucket)"
[[ -n "$ROLE_ARN" && "$ROLE_ARN" != None ]] \
  || error "No se encontró el stack ${BOOTSTRAP_STACK:-${PREFIX}-bootstrap} en $AWS_REGION (¿lanzaste el bootstrap?)."

msg "Cargando secrets en $REPO"
gh secret set AWS_ROLE_ARN --repo "$REPO" --body "$ROLE_ARN"
gh secret set TF_STATE_BUCKET --repo "$REPO" --body "$STATE_BUCKET"
msg "Secrets listos: AWS_ROLE_ARN y TF_STATE_BUCKET ($(gh secret list --repo "$REPO" | wc -l | tr -d ' ') en total)."
