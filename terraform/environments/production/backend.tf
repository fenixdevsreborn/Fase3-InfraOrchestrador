# Backend remoto: S3 + DynamoDB para lock.
# Criar bucket e tabela uma vez com o workflow "Terraform Bootstrap" (Actions → Terraform Bootstrap).
terraform {
  backend "s3" {
    bucket         = "fcg-fenix-tfstate"
    key            = "production/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "fcg-fenix-tfstate-lock"
    encrypt        = true
  }
}
