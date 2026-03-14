# Ambiente demo

- **backend.hcl** — Backend S3 para demo (key: `fcg-infra/demo/terraform.tfstate`).
- **terraform.tfvars** — Variáveis padrão (environment = demo).

Os workflows usam `-backend-config=environments/demo/backend.hcl` quando `environment` é `demo`.
