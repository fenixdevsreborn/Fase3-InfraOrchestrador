variable "project_name" {
  type        = string
  description = "Prefixo do projeto (ex.: fcg-fenix)."
}

variable "environment" {
  type        = string
  description = "Ambiente (ex.: production). Usado em tags."
}

variable "service" {
  type        = string
  description = "Nome do serviço (ex.: usersapi, gamesapi, paymentsapi)."
}

variable "tags_base" {
  type        = map(string)
  description = "Tags base (Project, ManagedBy, Environment)."
}

variable "ecr_repository_arns" {
  type        = list(string)
  description = "Lista de ARNs dos repositórios ECR que a EC2 pode fazer pull (ex.: [module.ecr.repository_arns[\"usersapi\"]])."
  default     = []
}
