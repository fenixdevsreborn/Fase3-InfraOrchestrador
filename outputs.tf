# ------------------------------------------------------------------------------
# Outputs úteis para integração (CI/CD, apps, documentação)
# ------------------------------------------------------------------------------

output "environment" {
  description = "Ambiente provisionado."
  value       = var.environment
}

output "region" {
  description = "Região AWS."
  value       = var.aws_region
}

# API Gateway
output "api_gateway_id" {
  description = "ID do API Gateway HTTP API."
  value       = module.api_gateway.api_id
}

output "api_gateway_endpoint" {
  description = "URL de invocação do API Gateway (base para rotas)."
  value       = module.api_gateway.api_endpoint
}

output "api_gateway_execution_arn" {
  description = "ARN de execução do API Gateway (para permissões Lambda/outros)."
  value       = module.api_gateway.api_execution_arn
}

# SQS
output "sqs_notification_queue_url" {
  description = "URL da fila SQS de notificação."
  value       = module.sqs.notification_queue_url
}

output "sqs_notification_queue_arn" {
  description = "ARN da fila SQS de notificação."
  value       = module.sqs.notification_queue_arn
}

# Lambda
output "notification_lambda_name" {
  description = "Nome da Lambda de notificação."
  value       = module.notification_lambda.function_name
}

output "notification_lambda_arn" {
  description = "ARN da Lambda de notificação."
  value       = module.notification_lambda.function_arn
}

# ECR
output "ecr_repository_urls" {
  description = "Mapa nome do repositório -> URL base (sem tag) para push."
  value       = module.ecr.repository_urls
}

# Imagens em uso (para rollback e auditoria)
output "service_image_tags" {
  description = "Tag de imagem por serviço (estado aplicado). Use terraform output -json service_image_tags para rollback."
  value       = local.service_image_tags
}

output "service_image_uris" {
  description = "URI completa (repositório:tag) por serviço."
  value       = { for k, url in module.ecr.repository_urls : k => "${url}:${local.service_image_tags[k]}" }
}

# S3 Frontend
output "frontend_bucket_name" {
  description = "Nome do bucket S3 do frontend estático."
  value       = module.frontend.bucket_name
}

output "frontend_bucket_website_endpoint" {
  description = "Endpoint de website do bucket (se habilitado)."
  value       = module.frontend.website_endpoint
}

# CloudWatch Logs
output "log_groups" {
  description = "Nomes dos log groups CloudWatch criados."
  value       = module.logs.log_group_names
}

# RDS PostgreSQL (quando criado)
output "postgres_endpoint" {
  description = "Endpoint do RDS PostgreSQL (host:port)."
  value       = var.postgres_create_db ? module.postgres[0].endpoint : null
}

output "postgres_port" {
  description = "Porta do RDS PostgreSQL."
  value       = var.postgres_create_db ? module.postgres[0].port : null
}

output "postgres_database_name" {
  description = "Nome do banco criado no RDS."
  value       = var.postgres_create_db ? module.postgres[0].database_name : null
}

# VPC (quando criada)
output "vpc_id" {
  description = "ID da VPC."
  value       = local.vpc_id
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas (RDS/Lambda)."
  value       = local.private_subnet_ids
}
