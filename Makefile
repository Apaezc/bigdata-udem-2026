# Targets del template (ver CONTRATO.md). Cada target delega en scripts/*.sh.
SHELL := /bin/bash
.DEFAULT_GOAL := help

# Configuración local generada por 'make setup' (.env no versionado).
-include .env
PREFIX ?= bigdata
AWS_REGION ?= us-east-2
export PREFIX AWS_REGION
export PATH := $(CURDIR)/.venv/bin:$(PATH)

.PHONY: help setup reparar-entorno config doctor estado test secrets publicar-bootstrap retirar-bootstrap rutas correr jars-s3a migrar-clase07 actualizar-vm deploy airflow-on airflow-off airflow-local airflow-local-down airflow-local-estado \
	airflow-habilitar airflow-deshabilitar snowflake snowflake-secreto snowflake-conexion \
	airflow-tunel airflow-password desbloquear snowflake-ampliar-cuota destroy limpieza-total

help: ## Muestra los targets disponibles
	@grep -hE '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  %-24s %s\n", $$1, $$2}'

setup: ## Verifica herramientas, alinea AWS_REGION y crea la configuración de AWS en S3 si no existe
	bash scripts/setup.sh

reparar-entorno: ## Recrea .venv con Python 3.12, reinstala dependencias, registra el kernel y repara snow
	bash scripts/reparar-entorno.sh

config: ## Muestra la configuración de AWS guardada en S3 (config/aws.tfvars)
	bash scripts/config.sh

doctor: ## Diagnóstico: versiones, entorno de Python, AWS, Snowflake, Terraform y estado OIDC
	bash scripts/doctor.sh

estado: ## Airflow (on/off + URL), últimos job runs de Glue, warehouse y costos
	bash scripts/estado.sh

test: ## Ruff y pytest
	bash scripts/test.sh

correr: ## Corre el pipeline en dev (PASO=bronze|silver|gold|snowflake COMPUTO= LIMITE= MES= REPROCESAR=); sin nada usa pipeline.yaml
	PASO="$(PASO)" COMPUTO="$(COMPUTO)" LIMITE="$(LIMITE)" MES="$(MES)" REPROCESAR="$(REPROCESAR)" bash scripts/correr.sh

jars-s3a: ## Baja una vez los jars que Spark necesita para leer y escribir en S3 (~280 MB, en ~/.spark-jars)
	bash scripts/jars-s3a.sh

migrar-clase07: ## Pasa tu cuenta al diseño de la clase 7 (mueve el crudo a prod/bronze, esquemas de Snowflake, jars)
	bash scripts/migrar-clase07.sh

actualizar-vm: ## Deja la VM de Airflow de prod con el secreto y el código de la clase 7 (una vez)
	bash scripts/actualizar-vm.sh

rutas: ## Dónde lee y escribe cada entorno: bucket y carpetas (ENTORNO=dev|prod; vacío = los dos; solo informativo)
	bash scripts/rutas.sh $(ENTORNO)

secrets: ## Carga AWS_ROLE_ARN y TF_STATE_BUCKET en tu fork (desde el bootstrap, con gh)
	bash scripts/secrets.sh

# Targets de instructor: sin '##' para que no salgan en make help (se siguen corriendo por su nombre).
publicar-bootstrap: # SOLO INSTRUCTOR: publica la plantilla (versión fija) para el enlace Launch Stack
	bash scripts/publicar-bootstrap.sh

retirar-bootstrap: # SOLO INSTRUCTOR: retira la plantilla publicada (al cerrar la semana de inscripción)
	bash scripts/publicar-bootstrap.sh --retirar

deploy: ## terraform apply de infra/aws (el código de prod lo publica solo el CI/CD al hacer merge a main)
	bash scripts/deploy.sh

airflow-on: ## Enciende la instancia de Airflow e imprime la URL
	bash scripts/airflow-on.sh

airflow-off: ## Apaga la instancia de Airflow
	bash scripts/airflow-off.sh

airflow-habilitar: ## enable_airflow=true en la configuración de S3 y deploy (crea la VM)
	bash scripts/airflow-config.sh true

airflow-deshabilitar: ## enable_airflow=false en S3 y deploy (destruye la VM; exige CONFIRMAR_DESTRUCCION=true)
	bash scripts/airflow-config.sh false

snowflake: ## Apply de infra/snowflake, guarda sus outputs en S3 y aplica la fase 2 de AWS (SIN_DEPLOY=true omite el deploy)
	bash scripts/snowflake.sh

snowflake-secreto: ## Guarda la conexión de AIRFLOW_SVC (llave privada) en el secreto <prefix>/snowflake
	bash scripts/snowflake-secreto.sh

airflow-local: ## Airflow de dev en el Code Editor (UI: /codeeditor/default/ports/8080/)
	bash scripts/airflow-local.sh up

airflow-local-down: ## Detiene el Airflow de dev del Code Editor
	bash scripts/airflow-local.sh down

airflow-local-estado: ## Salud y memoria del Airflow de dev
	bash scripts/airflow-local.sh estado

airflow-tunel: ## Túnel SSM al Airflow de prod (VM) desde el Code Editor
	bash scripts/airflow-tunel.sh

airflow-password: ## Muestra usuario y contraseña de Airflow (Secrets Manager)
	bash scripts/airflow-password.sh

desbloquear: ## Revierte las acciones de Budgets (quita la política Deny), con confirmación
	bash scripts/desbloquear.sh

snowflake-ampliar-cuota: ## Amplía la cuota de créditos del resource monitor (CUOTA=N)
	CUOTA=$(CUOTA) bash scripts/snowflake-ampliar-cuota.sh

snowflake-conexion: ## Configura la conexión por defecto de snow (llave en ~/.snowflake/keys, connections.toml)
	bash scripts/snowflake-conexion.sh

destroy: ## Vacía el lake y destruye Snowflake y AWS; opcional: bootstrap y state (confirmación escrita)
	bash scripts/destroy.sh

limpieza-total: # SOLO INSTRUCTOR: deja la cuenta como nueva tras make destroy (Snowflake, EFS, state, validación, secrets)
	bash scripts/limpieza-total.sh
