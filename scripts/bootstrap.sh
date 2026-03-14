#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Executa o Terraform do bootstrap (bucket S3 + DynamoDB para state)
# Uso: ./scripts/bootstrap.sh [plan|apply|destroy]
# Requer variável state_bucket_name (ou terraform.tfvars no diretório bootstrap/)
# ------------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ACTION="${1:-plan}"

case "$ACTION" in
  plan|apply|destroy) ;;
  *)
    echo "Uso: $0 plan|apply|destroy" >&2
    exit 1
    ;;
esac

cd "$REPO_ROOT/bootstrap"
terraform init -no-color

case "$ACTION" in
  plan)
    terraform plan -no-color -out=tfplan
    echo "Para aplicar: ./scripts/bootstrap.sh apply"
    ;;
  apply)
    terraform apply -no-color -auto-approve
    echo "Próximo passo: preencha environments/<env>/backend.hcl com os outputs (terraform output -raw state_bucket_name e dynamodb_table_name)."
    ;;
  destroy)
    echo "Isso removerá o bucket S3 e a tabela DynamoDB do state. O bucket deve estar vazio."
    echo "Digite 'yes' para confirmar:"
    read -r CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
      echo "Cancelado."
      exit 1
    fi
    terraform destroy -no-color -auto-approve
    ;;
esac
