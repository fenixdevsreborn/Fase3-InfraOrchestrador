# Bucket S3 para frontend estático (site estático; CloudFront opcional depois)

resource "random_pet" "bucket" {
  count    = var.bucket_name != null && var.bucket_name != "" ? 0 : 1
  length   = 2
  prefix   = var.name_prefix
}

locals {
  bucket_name = coalesce(var.bucket_name, "${var.name_prefix}-${random_pet.bucket[0].id}")
}

resource "aws_s3_bucket" "frontend" {
  bucket        = local.bucket_name
  force_destroy = true
  tags          = merge(var.tags, { Name = local.bucket_name })
}

resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy    = true
  ignore_public_acls     = true
  restrict_public_buckets = true
}

# Website config (opcional: para usar como static website com CloudFront)
resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  index_document { suffix = "index.html" }
  error_document { key = "index.html" }
}

# CORS
resource "aws_s3_bucket_cors_configuration" "frontend" {
  count  = var.enable_cors ? 1 : 0
  bucket = aws_s3_bucket.frontend.id
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = []
    max_age_seconds = 3600
  }
}
