#!/usr/bin/env bash
# Aguarda GET 200 em .../users/.well-known/openid-configuration e roda terraform apply com JWT no API Gateway.
# Uso (na raiz do repo ou com TF_DIR definido):
#   chmod +x scripts/wait-oidc-and-enable-apigw-jwt.sh
#   ./scripts/wait-oidc-and-enable-apigw-jwt.sh [max_minutos]
#
set -euo pipefail
TF_DIR="${TF_DIR:-terraform/environments/production}"
MAX_MIN="${1:-20}"
cd "$(dirname "$0")/.."
cd "$TF_DIR"

if [ ! -f terraform.tfvars ]; then
  echo "Erro: crie terraform.tfvars em $TF_DIR (ou use TFVARS_* no CI)."
  exit 1
fi

terraform init -input=false
INVOKE_URL="$(terraform output -raw api_gateway_invoke_url)"
INVOKE_URL="${INVOKE_URL%/}"
OIDC_URL="${INVOKE_URL}/users/.well-known/openid-configuration"
echo "OIDC: $OIDC_URL"

MAX_SEC=$((MAX_MIN * 60))
ELAPSED=0
SLEEP=15
while [ "$ELAPSED" -lt "$MAX_SEC" ]; do
  if curl -sfS --max-time 30 "$OIDC_URL" >/dev/null; then
    echo "OIDC OK."
    terraform apply -auto-approve -input=false \
      -var-file=terraform.tfvars \
      -var=api_gateway_jwt_authorizer_enabled=true
    exit 0
  fi
  echo "Aguardando OIDC... (${ELAPSED}s / ${MAX_SEC}s)"
  sleep "$SLEEP"
  ELAPSED=$((ELAPSED + SLEEP))
done

echo "Timeout após ${MAX_MIN} min. Verifique Users API (PathBase /users, Jwt__Issuer)."
exit 1
