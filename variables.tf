# ------------------------------------------------------------------------------
# Decisões de arquitetura (ver README e docs/DECISIONS.md)
# ------------------------------------------------------------------------------

variable "environment" {
  description = "Ambiente (prod, staging, demo). Usado em nomes e tags."
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Nome do projeto usado em recursos (prefixo)."
  type        = string
  default     = "fcg"
}

variable "aws_region" {
  description = "Região AWS para provisionar recursos."
  type        = string
  default     = "us-east-1"
}

# ------------------------------------------------------------------------------
# API Gateway + JWT
# ------------------------------------------------------------------------------

variable "jwt_issuer_uri" {
  description = "URI do emissor JWT (ex: https://cognito-idp.REGION.amazonaws.com/USER_POOL_ID ou URL da Users API com /.well-known/openid-configuration). Deixe vazio para desabilitar authorizer."
  type        = string
  default     = ""
}

variable "jwt_audience" {
  description = "Audience esperada no JWT (ex: fcg-cloud-platform). Usado pelo API Gateway JWT authorizer."
  type        = list(string)
  default     = ["fcg-cloud-platform"]
}

# ------------------------------------------------------------------------------
# Rede (VPC para RDS/Lambda em VPC se necessário)
# ------------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR da VPC (usada por RDS e opcionalmente Lambdas)."
  type        = string
  default     = "10.0.0.0/16"
}

variable "create_vpc" {
  description = "Criar VPC e subnets para RDS. Se false, use vpc_id e subnet_ids existentes."
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "ID da VPC existente (quando create_vpc = false)."
  type        = string
  default     = ""
}

variable "private_subnet_ids" {
  description = "IDs das subnets privadas para RDS (quando create_vpc = false)."
  type        = list(string)
  default     = []
}

# ------------------------------------------------------------------------------
# PostgreSQL (RDS)
# ------------------------------------------------------------------------------

variable "postgres_allocated_storage_gb" {
  description = "Armazenamento alocado para RDS PostgreSQL (GB)."
  type        = number
  default     = 20
}

variable "postgres_instance_class" {
  description = "Classe da instância RDS (ex: db.t3.micro para baixo custo)."
  type        = string
  default     = "db.t3.micro"
}

variable "postgres_engine_version" {
  description = "Versão do engine PostgreSQL."
  type        = string
  default     = "16"
}

variable "postgres_master_username" {
  description = "Usuário master do PostgreSQL. Será sobrescrito por secret se usar Secrets Manager."
  type        = string
  default     = "fcgadmin"
  sensitive   = true
}

variable "postgres_master_password" {
  description = "Senha master do PostgreSQL. Preferir variável de ambiente TF_VAR_postgres_master_password."
  type        = string
  default     = ""
  sensitive   = true
}

variable "postgres_create_db" {
  description = "Criar instância RDS PostgreSQL. false = apenas preparar módulo/security groups para uso futuro."
  type        = bool
  default     = true
}

# ------------------------------------------------------------------------------
# Lambda (notificação)
# ------------------------------------------------------------------------------

variable "notification_lambda_memory_mb" {
  description = "Memória alocada para a Lambda de notificação (MB)."
  type        = number
  default     = 256
}

variable "notification_lambda_timeout_sec" {
  description = "Timeout da Lambda de notificação (segundos)."
  type        = number
  default     = 30
}

# ------------------------------------------------------------------------------
# SQS
# ------------------------------------------------------------------------------

variable "sqs_notification_queue_name" {
  description = "Nome da fila SQS para eventos de notificação."
  type        = string
  default     = "fcg-notification-events"
}

variable "sqs_message_retention_seconds" {
  description = "Retenção de mensagens na fila (segundos)."
  type        = number
  default     = 86400 # 1 dia
}

# ------------------------------------------------------------------------------
# ECR
# ------------------------------------------------------------------------------

variable "ecr_repository_names" {
  description = "Sufixos dos repositórios ECR (prefixo = project-environment). Ex: notification-lambda, games-api."
  type        = list(string)
  default     = ["notification-lambda", "games-api", "payments-api", "users-api"]
}

# ------------------------------------------------------------------------------
# Imagens Docker por serviço (uma variável por serviço)
# Permite atualizar um único serviço via -var ou image_tags.auto.tfvars sem alterar os demais.
# Workflows (deploy-from-service-update, terraform-apply) passam apenas a tag do serviço alterado.
# ------------------------------------------------------------------------------

variable "ecr_image_tag_users_api" {
  description = "Tag da imagem Users API no ECR (ex.: latest ou SHA). Atualizado por workflows de deploy."
  type        = string
  default     = "latest"
}

variable "ecr_image_tag_games_api" {
  description = "Tag da imagem Games API no ECR."
  type        = string
  default     = "latest"
}

variable "ecr_image_tag_payments_api" {
  description = "Tag da imagem Payments API no ECR."
  type        = string
  default     = "latest"
}

variable "ecr_image_tag_notification_lambda" {
  description = "Tag da imagem Notification Lambda no ECR."
  type        = string
  default     = "latest"
}

# ------------------------------------------------------------------------------
# S3 (frontend estático)
# ------------------------------------------------------------------------------

variable "frontend_bucket_name" {
  description = "Nome do bucket S3 para frontend estático. Deixe vazio para gerar automaticamente."
  type        = string
  default     = ""
}

variable "frontend_enable_cors" {
  description = "Habilitar CORS no bucket do frontend."
  type        = bool
  default     = true
}

# ------------------------------------------------------------------------------
# CloudWatch Logs
# ------------------------------------------------------------------------------

variable "log_retention_days" {
  description = "Dias de retenção dos log groups CloudWatch."
  type        = number
  default     = 14
}

# ------------------------------------------------------------------------------
# Tags
# ------------------------------------------------------------------------------

variable "tags" {
  description = "Tags comuns aplicadas a todos os recursos."
  type        = map(string)
  default     = {}
}
