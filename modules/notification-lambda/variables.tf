variable "name_prefix" {
  type = string
}

variable "ecr_repository_url" {
  type        = string
  description = "URL do repositório ECR (sem tag)"
}

variable "image_tag" {
  type        = string
  description = "Tag da imagem a ser implantada (ex: sha curto do commit ou latest)"
  default     = "latest"
}

variable "sqs_queue_arn" {
  type = string
}

variable "sqs_queue_url" {
  type = string
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "memory_mb" {
  type    = number
  default = 256
}

variable "timeout_sec" {
  type    = number
  default = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}
