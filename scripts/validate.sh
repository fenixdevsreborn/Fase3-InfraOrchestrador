#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Terraform fmt (check) e validate na raiz (sem backend)
# Uso: ./scripts/validate.sh
# ------------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"
echo "Verificando formatação (terraform fmt -check -recursive)..."
terraform fmt -check -recursive -diff || {
  echo "Execute 'terraform fmt -recursive' para corrigir a formatação." >&2
  exit 1
}
echo "Inicializando (backend=false)..."
terraform init -backend=false -no-color
echo "Validando configuração..."
terraform validate -no-color
echo "✅ fmt e validate OK"
