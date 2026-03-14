# Ambiente staging

- **backend.hcl** — Backend S3 para staging (key: `fcg-infra/staging/terraform.tfstate`).
- **terraform.tfvars** — Variáveis padrão (environment = staging).

Os workflows usam `-backend-config=environments/staging/backend.hcl` quando `environment` é `staging`.
