# Scripts — Fase3-InfraOrchestrador

## `wait-oidc-and-enable-apigw-jwt.sh` / `.ps1`

Esperam o endpoint OIDC da Users API (via `terraform output api_gateway_invoke_url`) e executam `terraform apply` com `api_gateway_jwt_authorizer_enabled=true`.

Ver README raiz, seção **Formas mais fáceis (JWT no API Gateway)**.

Equivalente no GitHub Actions: workflow **Enable API Gateway JWT (wait OIDC + apply)**.
