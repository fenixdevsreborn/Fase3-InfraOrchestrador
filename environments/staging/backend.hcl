# Backend S3 para ambiente staging
# Preencha bucket e dynamodb_table com os valores do bootstrap
# Uso: terraform init -backend-config=environments/staging/backend.hcl

bucket         = "fcg-terraform-state-REPLACE-WITH-ACCOUNT-ID"
key            = "fcg-infra/staging/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "fcg-terraform-locks"
encrypt        = true
