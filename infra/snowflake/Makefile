# Uso desde infra/snowflake: make <target>   (o make -C infra/snowflake <target>)
# KEY: llave privada generada por bootstrap/snowflake/gen_key.sh.
# BACKEND: archivo con la config del backend S3 (copiar desde backend.hcl.example).

KEY     ?= $(HOME)/.snowflake/keys/terraform_svc_rsa_key.p8
BACKEND ?= backend.hcl

.PHONY: help init fmt fmt-check validate plan apply outputs destroy

help: ## Lista los targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "%-12s %s\n", $$1, $$2}'

init: ## terraform init con backend S3 (requiere backend.hcl)
	@test -f "$(BACKEND)" || { echo "Falta $(BACKEND). Copiar desde backend.hcl.example."; exit 1; }
	terraform init -backend-config=$(BACKEND)

fmt: ## terraform fmt -recursive
	terraform fmt -recursive

fmt-check: ## terraform fmt -check (CI)
	terraform fmt -check -recursive

validate: ## terraform validate (requiere init)
	terraform validate

plan: ## terraform plan (requiere la llave privada)
	@test -f "$(KEY)" || { echo "Falta la llave $(KEY). Ejecutar bootstrap/snowflake/gen_key.sh."; exit 1; }
	TF_VAR_private_key="$$(cat "$(KEY)")" terraform plan

apply: ## terraform apply (requiere la llave privada)
	@test -f "$(KEY)" || { echo "Falta la llave $(KEY). Ejecutar bootstrap/snowflake/gen_key.sh."; exit 1; }
	TF_VAR_private_key="$$(cat "$(KEY)")" terraform apply

outputs: ## Muestra outputs (storage_aws_iam_user_arn, storage_aws_external_id)
	terraform output

destroy: ## terraform destroy (requiere la llave privada)
	@test -f "$(KEY)" || { echo "Falta la llave $(KEY). Ejecutar bootstrap/snowflake/gen_key.sh."; exit 1; }
	TF_VAR_private_key="$$(cat "$(KEY)")" terraform destroy
