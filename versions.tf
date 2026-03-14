terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  # Backend S3: parâmetros vêm de -backend-config=environments/<env>/backend.hcl
  # Ex.: terraform init -backend-config=environments/prod/backend.hcl
  backend "s3" {}
}
