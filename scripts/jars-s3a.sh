#!/usr/bin/env bash
# Baja una sola vez los dos jars que Spark necesita para leer y escribir en S3 desde el Code Editor
# (~280 MB en total) y los deja en ~/.spark-jars/ (o en $PIPELINE_JARS_DIR). No usa spark.jars.packages.
#   hadoop-aws-3.3.4.jar             (el Hadoop que trae pyspark 3.5.6)
#   aws-java-sdk-bundle-1.12.262.jar (el SDK que ese hadoop-aws espera)
# Origen principal: copia del curso en el bucket público (más rápido y parejo para 30 cuentas a la
# vez); respaldo: Maven Central. En los dos casos se verifica el SHA-1 que publica Maven Central.
# Es idempotente: si el jar ya está y el SHA-1 coincide, no lo baja otra vez.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

requerir curl

DESTINO="${PIPELINE_JARS_DIR:-$HOME/.spark-jars}"
ORIGEN_CURSO="${JARS_ORIGEN_CURSO:-https://bigdata-udem-2026-publico.s3.us-east-2.amazonaws.com/paquete/jars}"
MAVEN="https://repo1.maven.org/maven2"
JARS=(
  "hadoop-aws-3.3.4.jar|org/apache/hadoop/hadoop-aws/3.3.4"
  "aws-java-sdk-bundle-1.12.262.jar|com/amazonaws/aws-java-sdk-bundle/1.12.262"
)

sha1_de() {
  if command -v sha1sum >/dev/null 2>&1; then sha1sum "$1" | awk '{print $1}'; else shasum -a 1 "$1" | awk '{print $1}'; fi
}

mkdir -p "$DESTINO"
msg "Jars de S3A en $DESTINO"

for item in "${JARS[@]}"; do
  jar="${item%%|*}"
  ruta_maven="${item##*|}"
  archivo="$DESTINO/$jar"
  esperado="$(curl -fsSL "$MAVEN/$ruta_maven/$jar.sha1" | awk '{print $1}')" \
    || error "No pude leer el SHA-1 de $jar en Maven Central. Revisa la conexión a internet y repite 'cd ~/bigdata && make jars-s3a'."
  [[ -n "$esperado" ]] || error "Maven Central devolvió un SHA-1 vacío para $jar."

  if [[ -f "$archivo" && "$(sha1_de "$archivo")" == "$esperado" ]]; then
    echo "  OK (ya estaba): $archivo"
    continue
  fi

  parcial="$archivo.parte"
  rm -f "$parcial"
  msg "Bajando $jar"
  if curl -fL --retry 3 -o "$parcial" "$ORIGEN_CURSO/$jar" 2>/dev/null; then
    echo "  Origen: $ORIGEN_CURSO/$jar"
  else
    aviso "No encontré la copia del curso; bajo de Maven Central."
    curl -fL --retry 3 -o "$parcial" "$MAVEN/$ruta_maven/$jar" \
      || { rm -f "$parcial"; error "No pude bajar $jar. Revisa la conexión y repite 'cd ~/bigdata && make jars-s3a'."; }
    echo "  Origen: $MAVEN/$ruta_maven/$jar"
  fi
  if [[ "$(sha1_de "$parcial")" != "$esperado" ]]; then
    rm -f "$parcial"
    error "El SHA-1 de $jar no coincide (esperado $esperado). Repite 'cd ~/bigdata && make jars-s3a'; si sigue igual, avisa al instructor."
  fi
  mv "$parcial" "$archivo"
  echo "  OK: $archivo"
done

msg "Listo. Spark ya puede leer y escribir en s3:// desde el Code Editor."
echo "Siguiente:  cd ~/bigdata && make correr PASO=bronze"
