# Módulo Security Groups — variáveis
# Cria: SG do ALB (fcg-fenix-alb-sg) e SGs por serviço (fcg-fenix-{service}-sg).

variable "project_name" {
  type        = string
  description = "Prefixo do projeto (ex.: fcg-fenix)."
}

variable "environment" {
  type        = string
  description = "Ambiente (ex.: production). Usado em tags."
}

variable "vpc_id" {
  type        = string
  description = "ID da VPC onde os security groups serão criados."
}

variable "services" {
  type        = list(string)
  description = "Lista de serviços (ex.: [\"usersapi\", \"gamesapi\", \"paymentsapi\"]). Um SG por serviço."
}

variable "tags_base" {
  type        = map(string)
  description = "Tags base (Project, ManagedBy, Environment)."
}

variable "alb_ingress_cidr_blocks" {
  type        = list(string)
  description = "CIDRs permitidos a acessar o ALB (ex.: [\"10.0.0.0/16\"] para tráfego interno). Para API Gateway via VPC Link use o CIDR da VPC."
  default     = []
}

variable "alb_ingress_ports" {
  type        = list(number)
  description = "Portas que o ALB aceita (ex.: [80, 443])."
  default     = [80, 443]
}

variable "api_ports" {
  type        = list(number)
  description = "Portas que as EC2 das APIs escutam (ex.: [80] ou [8080])."
  default     = [80]
}
