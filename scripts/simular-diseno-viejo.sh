#!/usr/bin/env bash
# SOLO PARA EL ENSAYO DEL INSTRUCTOR: deja una cuenta de prueba con el diseño anterior (clases 1 a 6)
# para ensayar 'make migrar-clase07'. Copia s3://<lake>/prod/bronze/ a s3://<lake>/bronze/ (el crudo y
# los lotes en la raíz) y crea s3://<lake>/muestra/ con un archivo de ejemplo. No borra nada.
# Uso: cd ~/bigdata && bash scripts/simular-diseno-viejo.sh
# Pide escribir el número de la cuenta; no corre sin terminal (salvo SIMULAR_CONFIRMADO=<cuenta>).
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

requerir aws
exigir_cuenta
LAKE="$(lake_bucket)"

s3_tiene_objetos "$LAKE" "prod/bronze/" \
  || error "No hay datos en s3://$LAKE/prod/bronze/ para copiar. Corre antes bronze en prod en la cuenta de prueba."

echo "Esto va a COPIAR (sin borrar nada):"
echo "  s3://$LAKE/prod/bronze/  ->  s3://$LAKE/bronze/"
echo "  un archivo de ejemplo    ->  s3://$LAKE/muestra/"
echo "Úsalo solo en la cuenta de prueba del instructor."
if [[ "${SIMULAR_CONFIRMADO:-}" == "$CUENTA_AWS" ]]; then
  msg "Confirmado por SIMULAR_CONFIRMADO."
else
  confirmar "Para seguir, escribe el número de esta cuenta de AWS." "$CUENTA_AWS"
fi

msg "Copiando prod/bronze/ a la raíz bronze/"
aws s3 cp "s3://$LAKE/prod/bronze/" "s3://$LAKE/bronze/" --recursive --only-show-errors

msg "Creando muestra/ de ejemplo"
echo "muestra del diseño anterior (ensayo de migrar-clase07)" \
  | aws s3 cp - "s3://$LAKE/muestra/fhvhv/ejemplo.txt" --only-show-errors

msg "Cuenta lista con el diseño viejo:"
echo "  s3://$LAKE/bronze/"
echo "  s3://$LAKE/muestra/"
echo "Siguiente:  cd ~/bigdata && make migrar-clase07"
