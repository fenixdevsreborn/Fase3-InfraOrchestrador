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

  # Backend remoto opcional: descomente e configure para persistir state
  # backend "s3" {
  #   bucket         = "fcg-terraform-state-REPLACE"
  #   key            = "fcg-infra/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "fcg-terraform-locks"
  #   encrypt        = true
  # }
}
