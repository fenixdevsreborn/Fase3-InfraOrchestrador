# Backend S3 para ambiente prod
# Preencha bucket e dynamodb_table com os valores do bootstrap (terraform output -raw state_bucket_name / dynamodb_table_name)
# Uso: terraform init -backend-config=environments/prod/backend.hcl

bucket         = "fcg-terraform-state-REPLACE-WITH-ACCOUNT-ID"
key            = "fcg-infra/prod/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "fcg-terraform-locks"
encrypt        = true
