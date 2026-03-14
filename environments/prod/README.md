# Ambiente prod

- **backend.hcl** — Configuração do backend S3 para este ambiente (key: `fcg-infra/prod/terraform.tfstate`). Preencha `bucket` e `dynamodb_table` com os outputs do bootstrap.
- **terraform.tfvars** — Variáveis padrão do ambiente (environment = prod). Use na raiz com `-var-file=environments/prod/terraform.tfvars` ou deixe o CI definir via `TF_VAR_environment=prod`.

Os workflows do GitHub Actions usam `terraform init -backend-config=environments/prod/backend.hcl` quando o input `environment` é `prod`.
