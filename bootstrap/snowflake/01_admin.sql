-- =============================================================================
-- 01_admin.sql: bootstrap de Snowflake para Terraform (infra/snowflake)
--
-- Ejecutar en Snowsight como ACCOUNTADMIN, una sola vez, con "Run All".
-- Antes de ejecutar, reemplazar '<PEGAR_CLAVE_PUBLICA>' (en CREATE USER) con la
-- línea que imprime bootstrap/snowflake/gen_key.sh. Snowflake rechaza una clave
-- inválida, así que no basta con dejar el placeholder.
-- Si el usuario ya existe, usar el ALTER USER que imprime gen_key.sh.
--
-- Nota: el script usa variables SET + IDENTIFIER($var) para nombres de rol y
-- usuario. Los nombres literales (BIGDATA_RM en ALTER ACCOUNT) van sin comillas.
-- =============================================================================


-- 0) Verificación de región. Debe empezar por AWS_ (mismo cloud que el bucket S3).
--    Ejemplo válido: AWS_US_EAST_2. Si no empieza por AWS_, crear otra cuenta trial.
SELECT CURRENT_REGION() AS region;


USE ROLE ACCOUNTADMIN;

SET role_tf = 'TERRAFORM_ROLE';
SET user_tf = 'TERRAFORM_SVC';
SET rm_name = 'BIGDATA_RM';


-- 1) Resource monitor de cuenta: 60 créditos, avisos al 50 % y 75 %, suspensión al 90 %
--    (deja terminar las consultas en curso) e inmediata al 100 %. Solo ACCOUNTADMIN puede crearlo.
CREATE RESOURCE MONITOR IF NOT EXISTS IDENTIFIER($rm_name)
  WITH CREDIT_QUOTA = 60
  FREQUENCY = MONTHLY
  START_TIMESTAMP = IMMEDIATELY
  TRIGGERS ON 50 PERCENT DO NOTIFY
           ON 75 PERCENT DO NOTIFY
           ON 90 PERCENT DO SUSPEND
           ON 100 PERCENT DO SUSPEND_IMMEDIATE;

-- Asignación a nivel cuenta (aplica a warehouses sin monitor propio).
ALTER ACCOUNT SET RESOURCE_MONITOR = BIGDATA_RM;


-- 2) Rol de Terraform con privilegios de creación a nivel cuenta.
CREATE ROLE IF NOT EXISTS IDENTIFIER($role_tf)
  COMMENT = 'Rol de Terraform para infra/snowflake (curso Big Data)';

GRANT CREATE WAREHOUSE   ON ACCOUNT TO ROLE IDENTIFIER($role_tf);
GRANT CREATE DATABASE    ON ACCOUNT TO ROLE IDENTIFIER($role_tf);
GRANT CREATE INTEGRATION ON ACCOUNT TO ROLE IDENTIFIER($role_tf);
GRANT CREATE ROLE        ON ACCOUNT TO ROLE IDENTIFIER($role_tf);
GRANT MANAGE GRANTS      ON ACCOUNT TO ROLE IDENTIFIER($role_tf);

-- Terraform NO asigna BIGDATA_RM al warehouse (requiere ACCOUNTADMIN): ver el paso 5.


-- 3) Usuario de servicio para Terraform (key-pair, sin contraseña).
--    RSA_PUBLIC_KEY: una sola línea, sin cabeceras BEGIN/END.
CREATE USER IF NOT EXISTS IDENTIFIER($user_tf)
  TYPE = SERVICE
  DEFAULT_ROLE = 'TERRAFORM_ROLE'
  RSA_PUBLIC_KEY = '<PEGAR_CLAVE_PUBLICA>'
  COMMENT = 'Usuario de servicio para Terraform (curso Big Data)';

-- DEFAULT_ROLE no concede el rol: hay que otorgarlo explícitamente.
GRANT ROLE IDENTIFIER($role_tf) TO USER IDENTIFIER($user_tf);


-- 4) El resource monitor ya aplica a TODOS los warehouses por el ALTER ACCOUNT del paso 1.
--    No se asigna al warehouse BIGDATA_WH: Snowflake lo rechaza ("currently set at the account level").
--    Este script es idempotente: no hace falta volver a ejecutarlo tras 'make apply'.


-- 5) Verificación final.
SHOW RESOURCE MONITORS LIKE 'BIGDATA_RM';
SHOW GRANTS TO ROLE TERRAFORM_ROLE;
-- RSA_PUBLIC_KEY_FP debe coincidir con el fingerprint que imprime gen_key.sh.
DESC USER TERRAFORM_SVC;
