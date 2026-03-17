# provider.tf — Provider AWS e default tags

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "fcg-fenix"
      ManagedBy   = "terraform"
      Environment = "production"
    }
  }
}
