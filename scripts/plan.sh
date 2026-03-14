#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Terraform Plan — execução local com backend por ambiente
# Uso: ./scripts/plan.sh <ambiente>   ex.: ./scripts/plan.sh prod
# ------------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV="${1:-}"

if [ -z "$ENV" ]; then
  echo "Uso: $0 <ambiente>" >&2
  echo "Ambientes: prod, staging, demo" >&2
  exit 1
fi

case "$ENV" in
  prod|staging|demo) ;;
  *)
    echo "Ambiente inválido: $ENV. Use prod, staging ou demo." >&2
    exit 1
    ;;
esac

BACKEND_CONFIG="environments/${ENV}/backend.hcl"
if [ ! -f "$REPO_ROOT/$BACKEND_CONFIG" ]; then
  echo "Arquivo não encontrado: $BACKEND_CONFIG. Rode o bootstrap e preencha backend.hcl." >&2
  exit 1
fi

cd "$REPO_ROOT"
export TF_VAR_environment="$ENV"
terraform init -no-color -backend-config="$BACKEND_CONFIG"
terraform validate -no-color

if [ -f image_tags.auto.tfvars ]; then
  terraform plan -no-color -out=tfplan -var-file=image_tags.auto.tfvars
else
  terraform plan -no-color -out=tfplan
fi

echo "Plano salvo em tfplan. Para aplicar: terraform apply tfplan (ou use ./scripts/apply.sh $ENV)"
