# ------------------------------------------------------------------------------
# FCG Infra Orchestrator — Makefile
# Uso: make plan ENV=prod   make apply ENV=prod   make destroy ENV=prod
#      make bootstrap-plan   make bootstrap-apply   make validate   make fmt
# ------------------------------------------------------------------------------

ENV ?= prod
SCRIPT_DIR := scripts

.PHONY: plan apply destroy bootstrap-plan bootstrap-apply bootstrap-destroy validate fmt check

plan:
	@$(SCRIPT_DIR)/plan.sh $(ENV)

apply:
	@$(SCRIPT_DIR)/apply.sh $(ENV)

destroy:
	@$(SCRIPT_DIR)/destroy.sh $(ENV)

bootstrap-plan:
	@$(SCRIPT_DIR)/bootstrap.sh plan

bootstrap-apply:
	@$(SCRIPT_DIR)/bootstrap.sh apply

bootstrap-destroy:
	@$(SCRIPT_DIR)/bootstrap.sh destroy

validate:
	@$(SCRIPT_DIR)/validate.sh

fmt:
	terraform fmt -recursive

# Verifica se backend.hcl está configurado para o ambiente (sem placeholder)
check:
	@test -f environments/$(ENV)/backend.hcl || (echo "Arquivo environments/$(ENV)/backend.hcl não encontrado." && exit 1)
	@grep -q "REPLACE-WITH-ACCOUNT-ID" environments/$(ENV)/backend.hcl && (echo "Preencha bucket e dynamodb_table em environments/$(ENV)/backend.hcl (outputs do bootstrap)." && exit 1) || true
	@echo "Backend config OK para $(ENV)"
