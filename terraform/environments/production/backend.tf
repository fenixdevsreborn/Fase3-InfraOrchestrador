# Backend remoto: S3 + DynamoDB para lock.
# Nomes: bucket fcg-fenix-tfstate; tabela fcg-fenix-tfstate-lock.
# Descomentar após criar bucket e tabela (bootstrap).

# terraform {
#   backend "s3" {
#     bucket         = "fcg-fenix-tfstate"
#     key            = "production/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "fcg-fenix-tfstate-lock"
#     encrypt        = true
#   }
# }
