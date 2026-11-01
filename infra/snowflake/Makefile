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

.PHONY: help airflow-key init fmt fmt-check validate plan apply outputs destroy

help: ## Lista los targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "%-12s %s\n", $$1, $$2}'

airflow-key: ## Genera la llave de AIRFLOW_SVC si falta (no sobrescribe)
	@test -f "$(AIRFLOW_PRIV)" || { echo "Generando la llave de AIRFLOW_SVC en $(AIRFLOW_PRIV)"; bash ../../bootstrap/snowflake/gen_key.sh AIRFLOW_SVC >/dev/null; }
	@test -f "$(AIRFLOW_PUB)" || openssl rsa -in "$(AIRFLOW_PRIV)" -pubout -out "$(AIRFLOW_PUB)" 2>/dev/null

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
	TF_VAR_private_key="$$(cat "$(KEY)")" $(AIRFLOW_ENV) terraform plan

apply: airflow-key ## terraform apply (requiere la llave privada)
	@test -f "$(KEY)" || { echo "Falta la llave $(KEY). Ejecutar bootstrap/snowflake/gen_key.sh."; exit 1; }
	TF_VAR_private_key="$$(cat "$(KEY)")" $(AIRFLOW_ENV) terraform apply

outputs: ## Muestra outputs (storage_aws_iam_user_arn, storage_aws_external_id, airflow_conexion)
	terraform output

destroy: ## terraform destroy (requiere la llave privada)
	@test -f "$(KEY)" || { echo "Falta la llave $(KEY). Ejecutar bootstrap/snowflake/gen_key.sh."; exit 1; }
	TF_VAR_private_key="$$(cat "$(KEY)")" terraform destroy
