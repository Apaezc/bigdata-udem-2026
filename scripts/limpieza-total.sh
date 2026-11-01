#!/usr/bin/env bash
# SOLO INSTRUCTOR: deja la cuenta AWS y Snowflake como nuevas después de 'make destroy' y antes de
# reconstruir desde cero (validación V9). No forma parte del flujo del estudiante.
#
# Pasos (cada uno es idempotente: si el recurso no existe, lo dice y sigue):
#   1) Muestra cuenta y región y pide confirmación escrita: 'limpiar <prefijo> <cuenta>'.
#   2) Snowflake: usuarios TERRAFORM_SVC y AIRFLOW_SVC, rol TERRAFORM_ROLE y resource monitor
#      BIGDATA_RM (antes ALTER ACCOUNT UNSET RESOURCE_MONITOR). Si siguen existiendo BIGDATA o
#      BIGDATA_WH, solo avisa. Nunca borra el usuario con el que se conecta.
#   3) AWS: EFS retenidos del dominio de SageMaker (mount targets, luego el EFS) y los security
#      groups NFS que queden sin uso. Después revisa el bucket de state: si existe, avisa y ofrece
#      vaciarlo y borrarlo con una confirmación extra.
#   4) Opcional, con confirmación propia: validación previa (bucket bigdata-validacion-<cuenta>-use2,
#      job Glue bigdata-val-smoke, rol IAM bigdata-val-glue, warehouse BIGDATA_VAL_WH y presupuesto
#      bigdata-validacion).
#   5) Opcional, con confirmación propia: secrets AWS_ROLE_ARN y TF_STATE_BUCKET del fork
#      (gh secret delete), para probar 'make secrets' desde cero.
#
# Nunca toca: s3://bigdata-udem-2026-publico, el presupuesto "My Monthly Cost Budget" ni el
# usuario de Snowflake personal.
#
# Variables opcionales:
#   SNOWFLAKE_DEFAULT_CONNECTION_NAME  conexión de 'snow' (si no se define, la por defecto).
#   EFS_IDS                            IDs de EFS separados por espacios. Si no se define, se
#                                      buscan los EFS con la etiqueta ManagedByAmazonSageMakerResource.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

requerir aws jq snow

CUENTA="$(account_id)"
PUBLICO_BUCKET="bigdata-udem-2026-publico"
PRESUPUESTO_PROTEGIDO="My Monthly Cost Budget"
ESTADO_BUCKET="${PREFIX}-tfstate-${CUENTA}-${AWS_REGION}"
VAL_BUCKET="bigdata-validacion-${CUENTA}-use2"
VAL_JOB="bigdata-val-smoke"
VAL_ROL="bigdata-val-glue"
VAL_WH="BIGDATA_VAL_WH"
VAL_PRESUPUESTO="bigdata-validacion"
USUARIO_SF=""
ROL_SF=""
RESTOS_BIGDATA=0

# ---------- utilidades ----------

si_confirma() {
  # Uso: si_confirma "<texto>" "<palabra>". Devuelve 1 (sin terminar el script) si no se escribe la palabra.
  local texto="$1" palabra="$2" respuesta=""
  if [[ ! -t 0 ]]; then
    aviso "Sin terminal interactiva: se omite el paso opcional."
    return 1
  fi
  echo "$texto"
  read -r -p "Escribe '$palabra' para hacer este paso (Enter para omitirlo): " respuesta || true
  [[ "$respuesta" == "$palabra" ]]
}

sfq() {
  # Ejecuta 'snow sql' con la conexión de SNOWFLAKE_DEFAULT_CONNECTION_NAME si está definida.
  if [[ -n "${SNOWFLAKE_DEFAULT_CONNECTION_NAME:-}" ]]; then
    snow sql -c "$SNOWFLAKE_DEFAULT_CONNECTION_NAME" "$@"
  else
    snow sql "$@"
  fi
}

sf_existe() {
  # Uso: sf_existe "SHOW ... LIKE '<nombre>'". Devuelve 0 si la consulta trae alguna fila.
  local salida
  salida="$(sfq -q "$1" --format json)" \
    || error "No se pudo consultar Snowflake (prueba 'snow connection test')."
  [[ "$(jq 'length' <<< "${salida:-[]}")" -gt 0 ]]
}

sf_usuario_conectado() {
  local fila
  fila="$(sfq -q "SELECT CURRENT_USER() AS U, CURRENT_ROLE() AS R" --format json)" \
    || error "No se pudo consultar Snowflake (prueba 'snow connection test')."
  USUARIO_SF="$(jq -r '.[0].U' <<< "$fila")"
  ROL_SF="$(jq -r '.[0].R' <<< "$fila")"
}

vaciar_y_borrar_bucket() {
  # Borra todas las versiones y marcadores de borrado, y después el bucket. Idempotente.
  local bucket="$1" lote cuantos salida
  [[ "$bucket" != "$PUBLICO_BUCKET" ]] || error "Protegido: $bucket no se toca nunca."
  if ! aws s3api head-bucket --bucket "$bucket" >/dev/null 2>&1; then
    msg "Bucket $bucket: no existe; se omite."
    return 0
  fi
  msg "Vaciando y borrando s3://$bucket (incluye versiones y marcadores de borrado)"
  while :; do
    lote="$(aws s3api list-object-versions --bucket "$bucket" --max-items 500 --output json \
      | jq -c '{Objects: ([(.Versions // [])[], (.DeleteMarkers // [])[]] | map({Key: .Key, VersionId: .VersionId})), Quiet: true}')"
    cuantos="$(jq '.Objects | length' <<< "$lote")"
    [[ "$cuantos" != "0" ]] || break
    salida="$(aws s3api delete-objects --bucket "$bucket" --delete "$lote")"
    jq -e '(.Errors // []) | length == 0' <<< "$salida" >/dev/null \
      || error "Errores al borrar objetos de $bucket: $salida"
  done
  aws s3api delete-bucket --bucket "$bucket"
  msg "Bucket $bucket borrado."
}

esperar_sin_mount_targets() {
  # Espera hasta 10 min a que el EFS no tenga mount targets. Devuelve 1 si no se vacía.
  local fs="$1" _
  for _ in $(seq 1 40); do
    if [[ -z "$(aws efs describe-mount-targets --file-system-id "$fs" --output json \
      | jq -r '.MountTargets[].MountTargetId')" ]]; then
      return 0
    fi
    sleep 15
  done
  return 1
}

# ---------- paso 2: Snowflake ----------

sf_borrar_usuario() {
  local u="$1"
  case "$u" in
    TERRAFORM_SVC|AIRFLOW_SVC) ;;
    *) error "Usuario no permitido para esta limpieza: $u" ;;
  esac
  if [[ "$u" == "$USUARIO_SF" ]]; then
    aviso "Se omite $u: es el usuario con el que se conecta este script."
    return 0
  fi
  if ! sf_existe "SHOW USERS LIKE '$u'"; then
    msg "Usuario Snowflake $u: no existe; se omite."
    return 0
  fi
  msg "Borrando usuario Snowflake $u"
  sfq -q "DROP USER IF EXISTS $u" >/dev/null || aviso "No se pudo borrar el usuario $u (revisa el error de arriba)."
}

sf_borrar_rol() {
  local r="TERRAFORM_ROLE"
  if [[ "$ROL_SF" == "$r" ]]; then
    aviso "Se omite $r: es el rol activo de la sesión de este script."
    return 0
  fi
  if ! sf_existe "SHOW ROLES LIKE '$r'"; then
    msg "Rol Snowflake $r: no existe; se omite."
    return 0
  fi
  if [[ "$RESTOS_BIGDATA" == "1" ]]; then
    aviso "Se omite $r: $r es dueño de BIGDATA/BIGDATA_WH, que aún existen. Repite cuando 'make destroy' los haya borrado."
    return 0
  fi
  msg "Borrando rol Snowflake $r"
  sfq -q "DROP ROLE IF EXISTS $r" >/dev/null || aviso "No se pudo borrar el rol $r (revisa el error de arriba)."
}

sf_borrar_resource_monitor() {
  # El monitor del template está a nivel cuenta; ALTER ACCOUNT UNSET lo desasigna antes del DROP.
  if ! sf_existe "SHOW RESOURCE MONITORS LIKE 'BIGDATA_RM'"; then
    msg "Resource monitor BIGDATA_RM: no existe; se omite."
    return 0
  fi
  msg "Quitando BIGDATA_RM de la cuenta (ALTER ACCOUNT UNSET RESOURCE_MONITOR) y borrándolo"
  sfq -q "ALTER ACCOUNT UNSET RESOURCE_MONITOR" >/dev/null \
    || aviso "No se pudo desasignar el resource monitor de la cuenta."
  sfq -q "DROP RESOURCE MONITOR IF EXISTS BIGDATA_RM" >/dev/null \
    || aviso "No se pudo borrar BIGDATA_RM (¿sigue asignado a un warehouse?)."
}

paso_snowflake() {
  msg "Paso 2: Snowflake"
  sf_usuario_conectado
  msg "Conectado como $USUARIO_SF (rol $ROL_SF). Ese usuario no se borra nunca."

  if sf_existe "SHOW DATABASES LIKE 'BIGDATA'"; then
    aviso "Sigue existiendo la base BIGDATA. No se borra aquí: revisa que 'make destroy' terminó."
    RESTOS_BIGDATA=1
  fi
  if sf_existe "SHOW WAREHOUSES LIKE 'BIGDATA_WH'"; then
    aviso "Sigue existiendo el warehouse BIGDATA_WH. No se borra aquí: revisa que 'make destroy' terminó."
    RESTOS_BIGDATA=1
  fi

  sf_borrar_usuario TERRAFORM_SVC
  sf_borrar_usuario AIRFLOW_SVC
  sf_borrar_rol
  sf_borrar_resource_monitor
}

# ---------- paso 3: AWS (EFS de SageMaker, security groups NFS, bucket de state) ----------

borrar_efs() {
  local fs="$1" mt m
  if ! aws efs describe-file-systems --file-system-id "$fs" >/dev/null 2>&1; then
    msg "EFS $fs: no existe; se omite."
    return 0
  fi
  msg "Borrando EFS $fs (primero sus mount targets)"
  mt="$(aws efs describe-mount-targets --file-system-id "$fs" --output json \
    | jq -r '.MountTargets[].MountTargetId')"
  for m in $mt; do
    msg "  mount target $m"
    aws efs delete-mount-target --mount-target-id "$m" || aviso "No se pudo borrar el mount target $m."
  done
  if ! esperar_sin_mount_targets "$fs"; then
    aviso "Siguen los mount targets de $fs tras 10 min: no se borra el EFS. Revisa la consola y repite."
    return 0
  fi
  aws efs delete-file-system --file-system-id "$fs" || aviso "No se pudo borrar el EFS $fs."
}

borrar_sg_con_reintentos() {
  # Reintenta porque las ENI liberan el SG con un retraso tras borrar los mount targets.
  local sg="$1"
  for _ in 1 2 3 4 5 6; do
    if aws ec2 delete-security-group --group-id "$sg" >/dev/null; then
      msg "Security group $sg borrado."
      return 0
    fi
    sleep 20
  done
  aviso "No se pudo borrar el security group $sg (¿sigue en uso?). Revisa 'aws ec2 describe-network-interfaces'."
}

borrar_security_groups_nfs() {
  local ids sg usados libres="" ingreso salida
  ids="$(aws ec2 describe-security-groups \
    --filters 'Name=group-name,Values=security-group-for-inbound-nfs-*,security-group-for-outbound-nfs-*' \
    --output json | jq -r '.SecurityGroups[].GroupId')"
  if [[ -z "$ids" ]]; then
    msg "No hay security groups NFS de SageMaker; se omite."
    return 0
  fi
  for sg in $ids; do
    usados="$(aws ec2 describe-network-interfaces --filters "Name=group-id,Values=$sg" --output json \
      | jq '.NetworkInterfaces | length')"
    if [[ "$usados" == "0" ]]; then
      libres="$libres $sg"
    else
      aviso "Security group $sg en uso por $usados interfaz(ces): se omite."
    fi
  done
  if [[ -z "$libres" ]]; then
    return 0
  fi
  # Primero se quitan las reglas: las dos SG NFS se referencian entre sí.
  for sg in $libres; do
    msg "Quitando reglas del security group $sg"
    ingreso="$(aws ec2 describe-security-groups --group-ids "$sg" --output json \
      | jq -c '.SecurityGroups[0].IpPermissions')"
    if [[ "$ingreso" != "[]" ]]; then
      aws ec2 revoke-security-group-ingress --group-id "$sg" --ip-permissions "$ingreso" >/dev/null
    fi
    salida="$(aws ec2 describe-security-groups --group-ids "$sg" --output json \
      | jq -c '.SecurityGroups[0].IpPermissionsEgress')"
    if [[ "$salida" != "[]" ]]; then
      aws ec2 revoke-security-group-egress --group-id "$sg" --ip-permissions "$salida" >/dev/null
    fi
  done
  for sg in $libres; do
    borrar_sg_con_reintentos "$sg"
  done
}

paso_efs() {
  local ids fs
  msg "Paso 3a: EFS retenidos de SageMaker"
  if [[ -n "${EFS_IDS:-}" ]]; then
    ids="$EFS_IDS"
  else
    ids="$(aws efs describe-file-systems --output json \
      | jq -r '.FileSystems[] | select(any(.Tags[]?; .Key == "ManagedByAmazonSageMakerResource")) | .FileSystemId')"
  fi
  if [[ -z "$ids" ]]; then
    msg "No hay EFS de SageMaker; se omite."
  else
    msg "EFS que se borrarán: $(tr '\n' ' ' <<< "$ids")"
    for fs in $ids; do
      borrar_efs "$fs"
    done
  fi
  borrar_security_groups_nfs
}

paso_bucket_estado() {
  msg "Paso 3b: bucket de state $ESTADO_BUCKET"
  if ! aws s3api head-bucket --bucket "$ESTADO_BUCKET" >/dev/null 2>&1; then
    msg "El bucket de state no existe. Correcto."
    return 0
  fi
  aviso "El bucket de state $ESTADO_BUCKET todavía existe. Borrarlo elimina el state de Terraform y config/aws.tfvars."
  if si_confirma "Se vaciará (todas las versiones y marcadores) y se borrará $ESTADO_BUCKET." "vaciar state"; then
    vaciar_y_borrar_bucket "$ESTADO_BUCKET"
  else
    aviso "Se conserva $ESTADO_BUCKET."
  fi
}

# ---------- paso 4: validación previa (opcional) ----------

borrar_job_glue() {
  local job="$1"
  if ! aws glue get-job --job-name "$job" >/dev/null 2>&1; then
    msg "Job Glue $job: no existe; se omite."
    return 0
  fi
  msg "Borrando job Glue $job"
  aws glue delete-job --job-name "$job" >/dev/null
}

borrar_rol_iam() {
  local rol="$1" p perfil
  if ! aws iam get-role --role-name "$rol" >/dev/null 2>&1; then
    msg "Rol IAM $rol: no existe; se omite."
    return 0
  fi
  msg "Borrando rol IAM $rol (primero desadjunta políticas y quita perfiles de instancia)"
  while IFS= read -r p; do
    if [[ -n "$p" ]]; then
      aws iam detach-role-policy --role-name "$rol" --policy-arn "$p"
    fi
  done < <(aws iam list-attached-role-policies --role-name "$rol" --output json | jq -r '.AttachedPolicies[].PolicyArn')
  while IFS= read -r p; do
    if [[ -n "$p" ]]; then
      aws iam delete-role-policy --role-name "$rol" --policy-name "$p"
    fi
  done < <(aws iam list-role-policies --role-name "$rol" --output json | jq -r '.PolicyNames[]')
  while IFS= read -r perfil; do
    if [[ -n "$perfil" ]]; then
      aws iam remove-role-from-instance-profile --instance-profile-name "$perfil" --role-name "$rol"
    fi
  done < <(aws iam list-instance-profiles-for-role --role-name "$rol" --output json | jq -r '.InstanceProfiles[].InstanceProfileName')
  aws iam delete-role --role-name "$rol"
}

borrar_warehouse_validacion() {
  if ! sf_existe "SHOW WAREHOUSES LIKE '$VAL_WH'"; then
    msg "Warehouse $VAL_WH: no existe; se omite."
    return 0
  fi
  aviso "Si el connections.toml del Mac usa $VAL_WH como warehouse, cámbialo antes de seguir."
  msg "Borrando warehouse $VAL_WH"
  sfq -q "DROP WAREHOUSE IF EXISTS $VAL_WH" >/dev/null || aviso "No se pudo borrar $VAL_WH."
}

borrar_presupuesto() {
  local b="$1"
  [[ "$b" != "$PRESUPUESTO_PROTEGIDO" ]] || error "Protegido: el presupuesto '$b' no se toca nunca."
  if ! aws budgets describe-budget --account-id "$CUENTA" --budget-name "$b" >/dev/null 2>&1; then
    msg "Presupuesto $b: no existe; se omite."
    return 0
  fi
  msg "Borrando presupuesto $b"
  aws budgets delete-budget --account-id "$CUENTA" --budget-name "$b"
}

paso_validacion() {
  msg "Paso 4 (opcional): validación previa"
  if ! si_confirma "Se borrarán: s3://$VAL_BUCKET (con su contenido), job Glue $VAL_JOB, rol IAM $VAL_ROL (desadjuntando sus políticas), warehouse $VAL_WH y presupuesto $VAL_PRESUPUESTO." "borrar validacion"; then
    msg "Paso 4 omitido."
    return 0
  fi
  vaciar_y_borrar_bucket "$VAL_BUCKET"
  borrar_job_glue "$VAL_JOB"
  borrar_rol_iam "$VAL_ROL"
  borrar_warehouse_validacion
  borrar_presupuesto "$VAL_PRESUPUESTO"
}

# ---------- paso 5: secrets de GitHub (opcional) ----------

paso_github() {
  msg "Paso 5 (opcional): secrets del fork"
  if ! si_confirma "Se borrarán los secrets AWS_ROLE_ARN y TF_STATE_BUCKET del fork (para probar 'make secrets' desde cero)." "borrar secrets"; then
    msg "Paso 5 omitido."
    return 0
  fi
  if ! command -v gh >/dev/null 2>&1; then
    aviso "No está 'gh' instalado: se omite el paso 5."
    return 0
  fi
  local url repo existentes s
  url="$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null)" || { aviso "El repo no tiene 'origin': se omite el paso 5."; return 0; }
  repo="$(sed -E 's#^(git@[^:]+:|ssh://git@[^/]+/|https?://[^/]+/)##; s#\.git$##' <<< "$url")"
  gh auth status >/dev/null 2>&1 || { aviso "gh no está autenticado (gh auth login): se omite el paso 5."; return 0; }
  existentes="$(gh secret list -R "$repo" | awk '{print $1}')" \
    || { aviso "No se pudo listar los secrets de $repo: se omite el paso 5."; return 0; }
  for s in AWS_ROLE_ARN TF_STATE_BUCKET; do
    if grep -qx "$s" <<< "$existentes"; then
      msg "Borrando secret $s de $repo"
      gh secret delete "$s" -R "$repo" || aviso "No se pudo borrar el secret $s."
    else
      msg "Secret $s: no existe en $repo; se omite."
    fi
  done
}

# ---------- flujo principal ----------

msg "Limpieza total para dejar la cuenta como nueva (solo instructor)"
echo "Cuenta AWS: $CUENTA"
echo "Región:     $AWS_REGION"
echo "Prefijo:    $PREFIX"
echo "Snowflake:  conexión ${SNOWFLAKE_DEFAULT_CONNECTION_NAME:-por defecto de snow}"
echo ""
echo "Se borrará (si existe):"
echo "  Snowflake: usuarios TERRAFORM_SVC y AIRFLOW_SVC, rol TERRAFORM_ROLE, resource monitor BIGDATA_RM"
echo "  AWS: EFS retenidos de SageMaker y sus security groups NFS sin uso"
echo "  AWS: bucket de state $ESTADO_BUCKET (solo si lo confirmas aparte)"
echo "  Opcional, con confirmación propia: validación previa y secrets AWS_ROLE_ARN y TF_STATE_BUCKET"
echo "Nunca se toca: s3://$PUBLICO_BUCKET, el presupuesto '$PRESUPUESTO_PROTEGIDO' ni tu usuario de Snowflake personal."
echo ""
confirmar "Vas a limpiar la cuenta $CUENTA (región $AWS_REGION)." "limpiar $PREFIX $CUENTA"

paso_snowflake
paso_efs
paso_bucket_estado
paso_validacion
paso_github

msg "Limpieza terminada. Verifica con 'make doctor' tras 'make destroy' y, en Snowflake, SHOW USERS / SHOW ROLES / SHOW RESOURCE MONITORS."
