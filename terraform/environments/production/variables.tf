# Variáveis do ambiente production.

variable "aws_region" {
  type        = string
  description = "Região AWS."
  default     = "us-east-1"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR da VPC (ex.: 10.0.0.0/16)."
}

variable "availability_zones" {
  type        = list(string)
  description = "Lista de availability zones (ex.: [\"us-east-1a\", \"us-east-1b\"])."
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs das subnets públicas, na mesma ordem de availability_zones."
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs das subnets privadas, na mesma ordem de availability_zones."
}

variable "tags_base" {
  type = object({
    Project     = string
    ManagedBy   = string
    Environment = string
  })
  description = "Tags base aplicadas a todos os recursos."
}

variable "github_oidc_org" {
  type        = string
  description = "Organização ou owner do repositório GitHub para OIDC."
}

variable "github_oidc_repos" {
  type        = list(string)
  description = "Lista de repositórios permitidos para assumir a role (ex.: fcg-fenix-infra-repo)."
}

variable "instance_type" {
  type        = string
  description = <<-EOT
    Tipo EC2 para as três APIs (usersapi, gamesapi, paymentsapi). Default t3.nano (menor custo típico x86).
    Se Postgres+.NET no mesmo container OOM, suba para t3.micro ou t3.small.
  EOT
  default     = "t3.nano"
}

variable "alb_target_port" {
  type        = number
  description = "Porta dos targets no ALB e na EC2 (ex.: 80)."
  default     = 80
}

variable "users_api_jwt_issuer" {
  type        = string
  description = "Jwt:Issuer na Users API (claim iss). Vazio = Terraform usa https://{api-id}.execute-api.{região}.amazonaws.com/users (recomendado com ASPNETCORE_PATHBASE=/users)."
  default     = ""
}

variable "users_api_jwt_audience" {
  type        = list(string)
  description = "Jwt:Audience na Users API, Games API e Payments API (ex.: fcg-cloud-platform)."
  default     = ["fcg-cloud-platform"]
}

variable "api_gateway_jwt_authorizer_enabled" {
  type        = bool
  description = <<-EOT
    Habilita authorizer JWT no API Gateway (/games, /payments). A AWS exige que {issuer}/.well-known/openid-configuration já funcione no apply.
    Use false no primeiro deploy; após Users API publicar OIDC na URL do issuer, defina true e rode Apply de novo.
  EOT
  default     = false
}
