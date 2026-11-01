#!/usr/bin/env bash
# Muestra la configuración de infra/aws guardada en S3 (config/aws.tfvars).
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

requerir aws
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

msg "Configuración de AWS: $(config_uri)"
config_pull "$TMP"
cat "$TMP"
