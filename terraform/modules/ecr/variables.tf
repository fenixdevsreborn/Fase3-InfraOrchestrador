variable "project_name" {
  type        = string
  description = "Prefixo do projeto (ex.: fcg-fenix)."
}

variable "environment" {
  type        = string
  description = "Ambiente (ex.: production). Usado em tags."
}

variable "services" {
  type        = list(string)
  description = "Lista de serviços (ex.: [\"usersapi\", \"gamesapi\", \"paymentsapi\"]). Um repositório ECR por serviço."
}

variable "tags_base" {
  type        = map(string)
  description = "Tags base (Project, ManagedBy, Environment)."
}

variable "image_tag_mutability" {
  type        = string
  description = "MUTABLE ou IMMUTABLE para as imagens do repositório."
  default     = "MUTABLE"
}

variable "encrypt_images" {
  type        = bool
  description = "Habilitar criptografia nas imagens (KMS)."
  default     = false
}

variable "force_delete" {
  type        = bool
  description = "Se true, terraform destroy remove o repositório mesmo com imagens (DeleteRepository force)."
  default     = true
}
