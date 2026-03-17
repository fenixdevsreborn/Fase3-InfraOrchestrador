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
  description = "ID da VPC onde o ALB será criado."
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "IDs das subnets privadas (pelo menos 2 AZs para ALB)."
}

variable "alb_security_group_id" {
  type        = string
  description = "ID do security group do ALB."
}

variable "services" {
  type        = list(string)
  description = "Lista de serviços (ex.: [\"usersapi\", \"gamesapi\", \"paymentsapi\"]). Um target group por serviço."
}

variable "path_prefix_to_service" {
  type        = map(string)
  description = "Mapa path_prefix -> service para listener rules (ex.: { \"/users\" = \"usersapi\", \"/games\" = \"gamesapi\", \"/payments\" = \"paymentsapi\" }). O path no ALB será path_prefix + '/*'."
}

variable "target_port" {
  type        = number
  description = "Porta dos targets (ex.: 80)."
  default     = 80
}

variable "tags_base" {
  type        = map(string)
  description = "Tags base (Project, ManagedBy, Environment)."
}

variable "health_check_path" {
  type        = string
  description = "Path do health check do target group."
  default     = "/"
}

variable "health_check_matcher" {
  type        = string
  description = "Códigos HTTP considerados saudáveis (ex.: 200)."
  default     = "200"
}
