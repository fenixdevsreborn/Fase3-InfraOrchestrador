# versions.tf — Versão do Terraform e providers
# Executar: terraform -chdir=terraform/environments/production init | plan | apply

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
