# ------------------------------------------------------------------------------
# FCG Infra Orchestrator — Root module
# Provisiona infraestrutura AWS para FCG Cloud Platform (baixo custo, demo/prod).
# ------------------------------------------------------------------------------

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# ------------------------------------------------------------------------------
# VPC (opcional: para RDS e Lambdas em VPC)
# ------------------------------------------------------------------------------
module "vpc" {
  source   = "./modules/vpc"
  count    = var.create_vpc ? 1 : 0
  name     = local.name_prefix
  cidr     = var.vpc_cidr
  tags     = local.common_tags
}

locals {
  vpc_id             = var.create_vpc ? module.vpc[0].vpc_id : var.vpc_id
  private_subnet_ids = var.create_vpc ? module.vpc[0].private_subnet_ids : var.private_subnet_ids
}

# ------------------------------------------------------------------------------
# CloudWatch Logs (log groups para API Gateway e Lambdas)
# ------------------------------------------------------------------------------
module "logs" {
  source          = "./modules/cloudwatch-logs"
  name_prefix     = local.name_prefix
  retention_days  = var.log_retention_days
  tags            = local.common_tags
}

# ------------------------------------------------------------------------------
# SQS — Fila de notificação
# ------------------------------------------------------------------------------
module "sqs" {
  source                    = "./modules/sqs"
  name_prefix               = local.name_prefix
  notification_queue_name   = var.sqs_notification_queue_name
  message_retention_seconds = var.sqs_message_retention_seconds
  tags                      = local.common_tags
}

# ------------------------------------------------------------------------------
# Lambda — Notificação (container image, trigger SQS)
# ------------------------------------------------------------------------------
module "notification_lambda" {
  source              = "./modules/notification-lambda"
  name_prefix         = local.name_prefix
  ecr_repository_url  = module.ecr.repository_urls["notification-lambda"]
  image_tag           = var.ecr_image_tag_notification_lambda
  sqs_queue_arn       = module.sqs.notification_queue_arn
  sqs_queue_url       = module.sqs.notification_queue_url
  log_retention_days  = var.log_retention_days
  memory_mb           = var.notification_lambda_memory_mb
  timeout_sec         = var.notification_lambda_timeout_sec
  tags                = local.common_tags
}

# ------------------------------------------------------------------------------
# ECR — Repositórios para imagens Docker
# ------------------------------------------------------------------------------
module "ecr" {
  source            = "./modules/ecr"
  name_prefix       = local.name_prefix
  repository_names  = var.ecr_repository_names
  tags              = local.common_tags
}

# ------------------------------------------------------------------------------
# API Gateway HTTP API + JWT Authorizer (preparado)
# ------------------------------------------------------------------------------
module "api_gateway" {
  source                = "./modules/api-gateway"
  name_prefix           = local.name_prefix
  jwt_issuer_uri        = var.jwt_issuer_uri
  jwt_audience          = var.jwt_audience
  access_log_group_arn  = module.logs.api_gateway_log_group_arn
  tags                  = local.common_tags
}

# ------------------------------------------------------------------------------
# S3 — Frontend estático (site estático + opcional CloudFront depois)
# ------------------------------------------------------------------------------
module "frontend" {
  source        = "./modules/frontend-s3"
  name_prefix   = local.name_prefix
  bucket_name   = var.frontend_bucket_name
  enable_cors   = var.frontend_enable_cors
  tags          = local.common_tags
}

# ------------------------------------------------------------------------------
# RDS PostgreSQL (estratégia: instância única, baixo custo)
# ------------------------------------------------------------------------------
module "postgres" {
  source                   = "./modules/postgres"
  count                    = var.postgres_create_db ? 1 : 0
  name_prefix              = local.name_prefix
  vpc_id                   = local.vpc_id
  private_subnet_ids       = local.private_subnet_ids
  allocated_storage_gb     = var.postgres_allocated_storage_gb
  instance_class           = var.postgres_instance_class
  engine_version           = var.postgres_engine_version
  master_username          = var.postgres_master_username
  master_password          = var.postgres_master_password
  tags                     = local.common_tags
}
