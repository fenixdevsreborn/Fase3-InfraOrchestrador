# Módulo API Gateway HTTP API — integração privada via VPC Link para ALB interno
# Naming: fcg-fenix-main-apigw, fcg-fenix-main-vpclink, fcg-fenix-main-nlb (ponte para o ALB)

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
  description = "ID da VPC onde o NLB (ponte para o ALB) e o VPC Link serão criados."
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "IDs das subnets privadas para o NLB e o VPC Link."
}

variable "alb_arn" {
  type        = string
  description = "ARN do ALB interno (alvo do NLB)."
}

variable "alb_listener_port" {
  type        = number
  description = "Porta do listener do ALB (deve coincidir com o listener existente)."
  default     = 80
}

variable "route_paths" {
  type        = map(string)
  description = "Mapa path_prefix -> service para as rotas (ex.: { \"/users\" = \"usersapi\", \"/games\" = \"gamesapi\", \"/payments\" = \"paymentsapi\" }). Serão criadas rotas ANY path_prefix/{proxy+} e ANY path_prefix."
}

variable "tags_base" {
  type        = map(string)
  description = "Tags base (Project, ManagedBy, Environment)."
}

variable "vpc_link_security_group_ids" {
  type        = list(string)
  description = "IDs dos security groups para o VPC Link (opcional; necessário em algumas configurações de rede)."
  default     = []
}

variable "api_description" {
  type        = string
  description = "Descrição da API HTTP."
  default     = "FCG Fenix HTTP API - private integration via VPC Link to ALB"
}
