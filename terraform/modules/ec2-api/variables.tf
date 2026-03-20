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

variable "vpc_id" {
  type        = string
  description = "ID da VPC."
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "IDs das subnets privadas. A instância será criada na primeira (ou use subnet_index)."
}

variable "subnet_index" {
  type        = number
  description = "Índice da subnet em private_subnet_ids onde criar a EC2 (0 ou 1 para 2 AZs)."
  default     = 0
}

variable "security_group_id" {
  type        = string
  description = "ID do security group da EC2 para este serviço."
}

variable "instance_profile_name" {
  type        = string
  description = "Nome do instance profile (role) a anexar à EC2."
}

variable "target_group_arn" {
  type        = string
  description = "ARN do target group para registrar a instância."
}

variable "target_port" {
  type        = number
  description = "Porta na qual o target group faz health check e envia tráfego (ex.: 80)."
  default     = 80
}

variable "instance_type" {
  type        = string
  description = <<-EOT
    Tipo EC2. Default t3.nano = menor custo burstable x86 na família t3 (2 vCPU compartilhados, 0,5 GiB RAM).
    Atenção: imagem Postgres+.NET no mesmo container costuma precisar de mais RAM — use t3.micro (1 GiB) ou t3.small se houver OOM ou lentidão.
  EOT
  default     = "t3.nano"
}

variable "ami_id" {
  type        = string
  description = "AMI da instância. Se vazio, usa Amazon Linux 2 (data source)."
  default     = null
}

variable "tags_base" {
  type        = map(string)
  description = "Tags base (Project, ManagedBy, Environment)."
}

variable "root_volume_size" {
  type        = number
  description = "Tamanho do volume raiz em GB (gp3). Mínimo prático para Docker + imagens: 12–20."
  default     = 12
}
