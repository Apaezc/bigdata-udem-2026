# Uso desde infra/snowflake: make <target>   (o make -C infra/snowflake <target>)
# KEY: llave privada generada por bootstrap/snowflake/gen_key.sh.
# BACKEND: archivo con la config del backend S3 (copiar desde backend.hcl.example).

KEY     ?= $(HOME)/.snowflake/keys/terraform_svc_rsa_key.p8
BACKEND ?= backend.hcl

# AIRFLOW_SVC: usuario de servicio de Airflow. Su llave se genera sola la primera vez (gen_key.sh);
# la pública va a Terraform (TF_VAR_airflow_public_key) y la privada a Secrets Manager (scripts/snowflake.sh).
AIRFLOW_PRIV ?= $(HOME)/.snowflake/keys/airflow_svc_rsa_key.p8
AIRFLOW_PUB  ?= $(HOME)/.snowflake/keys/airflow_svc_rsa_key.pub
AIRFLOW_ENV   = TF_VAR_airflow_public_key="$$(grep -v -- '-----' "$(AIRFLOW_PUB)" | tr -d '\n')"

# AIRFLOW_PROD_SVC: usuario de la VM de prod (rol BIGDATA_PROD). Misma mecánica, otra llave
# (la privada va al secreto <prefix>/snowflake_prod).
AIRFLOW_PROD_PRIV ?= $(HOME)/.snowflake/keys/airflow_prod_svc_rsa_key.p8
AIRFLOW_PROD_PUB  ?= $(HOME)/.snowflake/keys/airflow_prod_svc_rsa_key.pub
AIRFLOW_PROD_ENV   = TF_VAR_airflow_prod_public_key="$$(grep -v -- '-----' "$(AIRFLOW_PROD_PUB)" | tr -d '\n')"

.PHONY: help airflow-key init fmt fmt-check validate plan apply outputs destroy

help: ## Lista los targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "%-12s %s\n", $$1, $$2}'

airflow-key: ## Genera las llaves de AIRFLOW_SVC y AIRFLOW_PROD_SVC si faltan (no sobrescribe)
	@test -f "$(AIRFLOW_PRIV)" || { echo "Generando la llave de AIRFLOW_SVC en $(AIRFLOW_PRIV)"; bash ../../bootstrap/snowflake/gen_key.sh AIRFLOW_SVC >/dev/null; }
	@test -f "$(AIRFLOW_PUB)" || openssl rsa -in "$(AIRFLOW_PRIV)" -pubout -out "$(AIRFLOW_PUB)" 2>/dev/null
	@test -f "$(AIRFLOW_PROD_PRIV)" || { echo "Generando la llave de AIRFLOW_PROD_SVC en $(AIRFLOW_PROD_PRIV)"; bash ../../bootstrap/snowflake/gen_key.sh AIRFLOW_PROD_SVC >/dev/null; }
	@test -f "$(AIRFLOW_PROD_PUB)" || openssl rsa -in "$(AIRFLOW_PROD_PRIV)" -pubout -out "$(AIRFLOW_PROD_PUB)" 2>/dev/null

init: ## terraform init con backend S3 (requiere backend.hcl)
	@test -f "$(BACKEND)" || { echo "Falta $(BACKEND). Copiar desde backend.hcl.example."; exit 1; }
	terraform init -reconfigure -backend-config=$(BACKEND)

fmt: ## terraform fmt -recursive
	terraform fmt -recursive

fmt-check: ## terraform fmt -check (CI)
	terraform fmt -check -recursive

validate: ## terraform validate (requiere init)
	terraform validate

plan: airflow-key ## terraform plan (requiere la llave privada)
	@test -f "$(KEY)" || { echo "Falta la llave $(KEY). Ejecutar bootstrap/snowflake/gen_key.sh."; exit 1; }
	TF_VAR_private_key="$$(cat "$(KEY)")" $(AIRFLOW_ENV) $(AIRFLOW_PROD_ENV) terraform plan

apply: airflow-key ## terraform apply (requiere la llave privada)
	@test -f "$(KEY)" || { echo "Falta la llave $(KEY). Ejecutar bootstrap/snowflake/gen_key.sh."; exit 1; }
	TF_VAR_private_key="$$(cat "$(KEY)")" $(AIRFLOW_ENV) $(AIRFLOW_PROD_ENV) terraform apply

outputs: ## Muestra outputs (storage_aws_*, airflow_conexion, airflow_prod_conexion)
	terraform output

destroy: ## Destruye este stack (requiere la llave privada y CONFIRMAR=si)
	@test "$(CONFIRMAR)" = "si" || { echo "Esto borra esquemas, roles y tablas de control de Snowflake. Repite con: make destroy CONFIRMAR=si"; exit 1; }
	@test -f "$(KEY)" || { echo "Falta la llave $(KEY). Ejecutar bootstrap/snowflake/gen_key.sh."; exit 1; }
	TF_VAR_private_key="$$(cat "$(KEY)")" terraform destroy
