# ------------------------------------------------------------------------------
# Bootstrap — bucket S3 (state) + DynamoDB (lock)
# Execute uma vez por conta/região; depois configure environments/<env>/backend.hcl
# ------------------------------------------------------------------------------

locals {
  common_tags = merge(var.tags, {
    Project   = var.project_name
    ManagedBy = "terraform"
    Purpose   = "terraform-state-backend"
  })
}

# Bucket S3 para state do Terraform
resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name

  tags = local.common_tags
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Tabela DynamoDB para lock do state
resource "aws_dynamodb_table" "locks" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = local.common_tags
}
