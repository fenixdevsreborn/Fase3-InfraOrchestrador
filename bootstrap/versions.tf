# ------------------------------------------------------------------------------
# Bootstrap — Terraform e providers
# Este diretório cria apenas o bucket S3 e a tabela DynamoDB para o state remoto.
# ------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
