# Módulo VPC — variáveis
# Convenção de nomes: {project_name}-{aplicacao-ws}-{identificador}
# Recursos compartilhados usam "main"; não usar "prod" no nome.

variable "project_name" {
  type        = string
  description = "Prefixo do projeto (ex.: fcg-fenix). Usado em todos os nomes de recursos."
}

variable "environment" {
  type        = string
  description = "Ambiente (ex.: production). Usado apenas em tags, não no nome do recurso."
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR da VPC (ex.: 10.0.0.0/16)."
}

variable "availability_zones" {
  type        = list(string)
  description = "Lista de availability zones (ex.: [\"us-east-1a\", \"us-east-1b\"]). Ordem define sufixo a/b nas subnets."
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs das subnets públicas, na mesma ordem de availability_zones (ex.: [\"10.0.1.0/24\", \"10.0.2.0/24\"])."
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs das subnets privadas, na mesma ordem de availability_zones (ex.: [\"10.0.10.0/24\", \"10.0.11.0/24\"])."
}

variable "tags_base" {
  type        = map(string)
  description = "Tags base (Project, ManagedBy, Environment). Serão mergeadas com Application/Service = shared nos recursos."
}
