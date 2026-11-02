#!/usr/bin/env bash
# SOLO INSTRUCTOR: publica (o retira) la plantilla de bootstrap para el enlace "Launch Stack".
#   publicar-bootstrap.sh            publica una versión nueva y fija el enlace del workflow a ella
#   publicar-bootstrap.sh --retirar  borra todas las versiones (fuera de la semana de inscripción)
# Protecciones: solo lectura y solo bootstrap/*, solo usuarios AUTENTICADOS de AWS (sin descargas
# anónimas desde internet), versionado y enlace fijado a una versión (un cambio posterior no
# altera los enlaces ya generados). Bucket: PUBLICO_BUCKET (por defecto bigdata-udem-2026-publico).
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

requerir aws jq
BUCKET="${PUBLICO_BUCKET:-bigdata-udem-2026-publico}"
CLAVE="bootstrap/bootstrap.yaml"
PLANTILLA="$ROOT_DIR/bootstrap/cloudformation/bootstrap.yaml"
WORKFLOW="$ROOT_DIR/.github/workflows/enlace-bootstrap.yml"
BASE_URL="https://$BUCKET.s3.$AWS_REGION.amazonaws.com/$CLAVE"

if [[ "${1:-}" == "--retirar" ]]; then
  aws s3api list-object-versions --bucket "$BUCKET" --prefix bootstrap/ --output json \
    | jq -c '[(.Versions // [])[], (.DeleteMarkers // [])[] | {Key, VersionId}]
             | select(length > 0) | {Objects: ., Quiet: true}' \
    | while read -r lote; do aws s3api delete-objects --bucket "$BUCKET" --delete "$lote" >/dev/null; done
  msg "Plantilla retirada de s3://$BUCKET/bootstrap/ (todas las versiones). Los enlaces dejan de funcionar."
  exit 0
fi

aws cloudformation validate-template --template-body "file://$PLANTILLA" >/dev/null \
  || error "La plantilla no es válida."

if ! aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
  msg "Creando bucket $BUCKET"
  aws s3api create-bucket --bucket "$BUCKET" --region "$AWS_REGION" \
    --create-bucket-configuration "LocationConstraint=$AWS_REGION" >/dev/null
fi
aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=false,RestrictPublicBuckets=false
# Lectura solo para principales AUTENTICADOS de cualquier cuenta (aws:PrincipalArn no existe en
# peticiones anónimas, así que la condición las excluye).
aws s3api put-bucket-policy --bucket "$BUCKET" --policy "$(jq -nc --arg b "$BUCKET" '{
  Version: "2012-10-17",
  Statement: [{
    Sid: "LecturaAutenticadaBootstrap", Effect: "Allow", Principal: {AWS: "*"},
    Action: ["s3:GetObject", "s3:GetObjectVersion"],
    Resource: "arn:aws:s3:::\($b)/bootstrap/*",
    Condition: {StringLike: {"aws:PrincipalArn": "arn:aws:*"}}
  }]}')"

VERSION="$(aws s3api put-object --bucket "$BUCKET" --key "$CLAVE" --body "$PLANTILLA" \
  --content-type text/yaml --query VersionId --output text)"
URL="$BASE_URL?versionId=$VERSION"

# Comprobaciones: CloudFormation lee la versión fijada con credenciales; sin credenciales, no.
aws cloudformation validate-template --template-url "$URL" >/dev/null \
  || error "CloudFormation no pudo leer $URL"
codigo="$(curl -s -o /dev/null -w '%{http_code}' "$URL")"
[[ "$codigo" == 403 ]] || aviso "La descarga anónima devolvió $codigo (se esperaba 403)."

# Fija el enlace del workflow a esta versión.
sed -i.bak -E "s#(BOOTSTRAP_TEMPLATE_URL \\|\\| ')[^']*(')#\\1$URL\\2#" "$WORKFLOW" && rm -f "$WORKFLOW.bak"
msg "Publicada versión $VERSION"
echo "URL fijada en $WORKFLOW:"
echo "  $URL"
echo "Haz commit de ese cambio (PR a main) para que los forks usen esta versión."
