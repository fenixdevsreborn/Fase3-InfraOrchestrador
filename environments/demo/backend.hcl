# Backend S3 para ambiente demo
# Preencha bucket e dynamodb_table com os valores do bootstrap
# Uso: terraform init -backend-config=environments/demo/backend.hcl

bucket         = "fcg-terraform-state-REPLACE-WITH-ACCOUNT-ID"
key            = "fcg-infra/demo/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "fcg-terraform-locks"
encrypt        = true
