#!/usr/bin/env bash
# SOLO INSTRUCTOR: publica la plantilla de bootstrap en un bucket público de lectura para que el
# workflow "Enlace de bootstrap" de cada fork arme el enlace Launch Stack. Repetir tras cada cambio.
# Variables: PUBLICO_BUCKET (por defecto bigdata-udem-2026-publico), en us-east-2.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

requerir aws
BUCKET="${PUBLICO_BUCKET:-bigdata-udem-2026-publico}"
CLAVE="bootstrap/bootstrap.yaml"
PLANTILLA="$ROOT_DIR/bootstrap/cloudformation/bootstrap.yaml"

aws cloudformation validate-template --template-body "file://$PLANTILLA" >/dev/null \
  || error "La plantilla no es válida."

if ! aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  msg "Creando bucket público $BUCKET (solo lectura de bootstrap/*)"
  aws s3api create-bucket --bucket "$BUCKET" --region "$AWS_REGION" \
    --create-bucket-configuration "LocationConstraint=$AWS_REGION" >/dev/null
  aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=false,RestrictPublicBuckets=false
  aws s3api put-bucket-policy --bucket "$BUCKET" --policy "$(jq -nc --arg b "$BUCKET" '{
    Version: "2012-10-17",
    Statement: [{Sid: "LecturaPublicaBootstrap", Effect: "Allow", Principal: "*",
      Action: "s3:GetObject", Resource: "arn:aws:s3:::\($b)/bootstrap/*"}]}')"
fi

aws s3 cp "$PLANTILLA" "s3://$BUCKET/$CLAVE" --content-type text/yaml --only-show-errors
msg "Publicada: https://$BUCKET.s3.$AWS_REGION.amazonaws.com/$CLAVE"
