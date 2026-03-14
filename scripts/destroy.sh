#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Terraform Destroy — execução local com backend por ambiente
# Uso: ./scripts/destroy.sh <ambiente>
# Confirme que deseja destruir; use com cuidado.
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
  echo "Arquivo não encontrado: $BACKEND_CONFIG." >&2
  exit 1
fi

echo "Você está prestes a destruir o ambiente: $ENV"
echo "Digite 'DESTROY' (maiúsculo) para confirmar:"
read -r CONFIRM
if [ "$CONFIRM" != "DESTROY" ]; then
  echo "Confirmação incorreta. Nenhum recurso foi alterado."
  exit 1
fi

cd "$REPO_ROOT"
export TF_VAR_environment="$ENV"
terraform init -no-color -backend-config="$BACKEND_CONFIG"
terraform destroy -no-color -auto-approve
