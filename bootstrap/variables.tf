# ------------------------------------------------------------------------------
# Bootstrap — variáveis
# ------------------------------------------------------------------------------

variable "project_name" {
  description = "Nome do projeto (prefixo dos recursos)."
  type        = string
  default     = "fcg"
}

variable "aws_region" {
  description = "Região AWS onde criar bucket e DynamoDB."
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Nome do bucket S3 para state do Terraform. Deve ser globalmente único. Ex: fcg-terraform-state-ACCOUNT-ID"
  type        = string
}

variable "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB para lock do state."
  type        = string
  default     = "fcg-terraform-locks"
}

variable "tags" {
  description = "Tags aplicadas aos recursos do bootstrap."
  type        = map(string)
  default     = {}
}
