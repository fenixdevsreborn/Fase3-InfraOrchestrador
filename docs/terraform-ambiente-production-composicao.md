# FCG Fenix — Composição do ambiente production (Terraform)

Ambiente único de produção com: **network**, **security**, **ecr**, **iam**, **alb**, **ec2_service**, **apigateway**. Nomenclatura padronizada; sem "prod" no nome dos recursos; serviços: usersapi, gamesapi, paymentsapi.

---

## Estrutura de arquivos do ambiente

```
terraform/environments/production/
├── backend.tf                 # Backend S3 + lock (opcional)
├── versions.tf                # Terraform + required_providers
├── provider.tf                # Provider AWS + default_tags
├── locals.tf                  # Naming e tags centralizados
├── variables.tf               # Variáveis do ambiente
├── terraform.tfvars.example   # Exemplo de valores
├── main.tf                    # Orquestração dos módulos
└── outputs.tf                 # Outputs expostos
```

---

## 1. versions.tf

```hcl
# versions.tf — Versão do Terraform e providers
# Executar: terraform -chdir=terraform/environments/production init | plan | apply

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

---

## 2. provider.tf

```hcl
# provider.tf — Provider AWS e default tags

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "fcg-fenix"
      ManagedBy   = "terraform"
      Environment = "production"
    }
  }
}
```

---

## 3. variables.tf

```hcl
# variables.tf — Variáveis do ambiente production

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
  description = "Tipo da instância EC2 (ex.: t3.micro)."
  default     = "t3.micro"
}

variable "alb_target_port" {
  type        = number
  description = "Porta dos targets no ALB e na EC2 (ex.: 80)."
  default     = 80
}
```

---

## 4. terraform.tfvars.example

```hcl
# Copiar para terraform.tfvars e preencher. Não versionar terraform.tfvars com secrets.

aws_region = "us-east-1"

vpc_cidr             = "10.0.0.0/16"
availability_zones   = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]

tags_base = {
  Project     = "fcg-fenix"
  ManagedBy   = "terraform"
  Environment = "production"
}

github_oidc_org   = "sua-org"
github_oidc_repos = ["fcg-fenix-infra-repo", "fcg-fenix-usersapi-repo", "fcg-fenix-gamesapi-repo", "fcg-fenix-paymentsapi-repo"]

instance_type   = "t3.micro"
alb_target_port = 80
```

---

## 5. locals.tf (resumo)

Os **locals** centralizam naming e tags; são usados no `main.tf` para evitar repetição.

```hcl
# locals.tf — Naming e tags centralizados (fcg-fenix-{aplicacao-ws}-{identificador})

locals {
  project_name = "fcg-fenix"
  environment  = "production"
  services     = ["usersapi", "gamesapi", "paymentsapi"]

  name_prefix = local.project_name

  # ALB: path prefix -> serviço para listener rules e API Gateway
  alb_path_prefix_to_service = {
    "/users"    = "usersapi"
    "/games"    = "gamesapi"
    "/payments" = "paymentsapi"
  }

  # Tags base (obrigatórias) — podem ser sobrescritas por var.tags_base no ambiente
  tags_base = {
    Project     = local.project_name
    ManagedBy   = "terraform"
    Environment = local.environment
  }
}
```

O `locals.tf` completo do repositório inclui ainda `main_name`, `service_names`, `special_names`, `subnet_names`, `tags_shared`, `tags_for_service`, `tags_github_actions`, `naming` e `tags` para uso nos módulos. O trecho acima é o mínimo necessário para a composição; o restante serve para referência e evolução.

---

## 6. main.tf (composição completa)

Ordem dos módulos: **vpc → security_groups → ecr → iam_* → alb → ec2_* → ssm → api_gateway**.

```hcl
# main.tf — Orquestração do ambiente production
# network | security | ecr | iam | alb | ec2_service | apigateway

# --- Network ---
module "vpc" {
  source = "../../modules/vpc"

  project_name          = local.project_name
  environment           = local.environment
  vpc_cidr              = var.vpc_cidr
  availability_zones    = var.availability_zones
  public_subnet_cidrs   = var.public_subnet_cidrs
  private_subnet_cidrs  = var.private_subnet_cidrs
  tags_base             = var.tags_base
}

# --- Security ---
module "security_groups" {
  source = "../../modules/security-groups"

  project_name            = local.project_name
  environment             = local.environment
  vpc_id                  = module.vpc.vpc_id
  services                = local.services
  tags_base               = var.tags_base
  alb_ingress_cidr_blocks = [module.vpc.vpc_cidr_block]
  alb_ingress_ports       = [80, 443]
  api_ports               = [80]
}

# --- ECR ---
module "ecr" {
  source = "../../modules/ecr"

  project_name = local.project_name
  environment  = local.environment
  services     = local.services
  tags_base    = var.tags_base
}

# --- IAM (GitHub OIDC + EC2 por serviço) ---
module "iam_github_oidc" {
  source = "../../modules/iam/github-oidc"

  project_name      = local.project_name
  environment       = local.environment
  github_oidc_org   = var.github_oidc_org
  github_oidc_repos = var.github_oidc_repos
  tags_base         = var.tags_base
}

module "iam_ec2_usersapi" {
  source = "../../modules/iam/ec2-api"

  project_name        = local.project_name
  environment         = local.environment
  service             = "usersapi"
  tags_base           = var.tags_base
  ecr_repository_arns = [module.ecr.repository_arns["usersapi"]]
}

module "iam_ec2_gamesapi" {
  source = "../../modules/iam/ec2-api"

  project_name        = local.project_name
  environment         = local.environment
  service             = "gamesapi"
  tags_base           = var.tags_base
  ecr_repository_arns = [module.ecr.repository_arns["gamesapi"]]
}

module "iam_ec2_paymentsapi" {
  source = "../../modules/iam/ec2-api"

  project_name        = local.project_name
  environment         = local.environment
  service             = "paymentsapi"
  tags_base           = var.tags_base
  ecr_repository_arns = [module.ecr.repository_arns["paymentsapi"]]
}

# --- ALB (interno + target groups + listener rules por path) ---
module "alb" {
  source = "../../modules/alb"

  project_name           = local.project_name
  environment            = local.environment
  vpc_id                 = module.vpc.vpc_id
  private_subnet_ids     = module.vpc.private_subnet_ids
  alb_security_group_id  = module.security_groups.alb_sg_id
  services               = local.services
  path_prefix_to_service = local.alb_path_prefix_to_service
  target_port            = var.alb_target_port
  tags_base              = var.tags_base
}

# --- EC2 por serviço ---
module "ec2_usersapi" {
  source = "../../modules/ec2-api"

  project_name          = local.project_name
  environment           = local.environment
  service               = "usersapi"
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  security_group_id     = module.security_groups.usersapi_sg_id
  instance_profile_name = module.iam_ec2_usersapi.instance_profile_name
  target_group_arn     = module.alb.target_group_arns["usersapi"]
  target_port           = var.alb_target_port
  instance_type        = var.instance_type
  tags_base             = var.tags_base
}

module "ec2_gamesapi" {
  source = "../../modules/ec2-api"

  project_name          = local.project_name
  environment           = local.environment
  service               = "gamesapi"
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  security_group_id     = module.security_groups.gamesapi_sg_id
  instance_profile_name = module.iam_ec2_gamesapi.instance_profile_name
  target_group_arn     = module.alb.target_group_arns["gamesapi"]
  target_port           = var.alb_target_port
  instance_type        = var.instance_type
  tags_base             = var.tags_base
}

module "ec2_paymentsapi" {
  source = "../../modules/ec2-api"

  project_name          = local.project_name
  environment           = local.environment
  service               = "paymentsapi"
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  security_group_id     = module.security_groups.paymentsapi_sg_id
  instance_profile_name = module.iam_ec2_paymentsapi.instance_profile_name
  target_group_arn     = module.alb.target_group_arns["paymentsapi"]
  target_port           = var.alb_target_port
  instance_type        = var.instance_type
  tags_base             = var.tags_base
}

# --- SSM (paths por serviço) ---
module "ssm" {
  source = "../../modules/ssm"

  project_name = local.project_name
  environment  = local.environment
  services     = local.services
  tags_base    = var.tags_base
}

# --- API Gateway HTTP API (VPC Link → NLB → ALB) ---
module "api_gateway" {
  source = "../../modules/api-gateway"

  project_name       = local.project_name
  environment        = local.environment
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  alb_arn            = module.alb.alb_arn
  alb_listener_port  = var.alb_target_port
  route_paths        = local.alb_path_prefix_to_service
  tags_base          = var.tags_base
}
```

---

## 7. outputs.tf

```hcl
# outputs.tf — Outputs do ambiente production

# Network
output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "ID da VPC fcg-fenix-main-vpc."
}

output "private_subnet_ids" {
  value       = module.vpc.private_subnet_ids
  description = "IDs das subnets privadas."
}

# ALB
output "alb_dns_name" {
  value       = module.alb.alb_dns_name
  description = "DNS name do ALB interno."
}

output "target_group_arns" {
  value       = module.alb.target_group_arns
  description = "Map service -> ARN do target group."
}

# API Gateway
output "api_gateway_invoke_url" {
  value       = module.api_gateway.invoke_url
  description = "URL de invocação da HTTP API ($default stage)."
}

# ECR
output "ecr_repository_urls" {
  value       = module.ecr.repository_urls
  description = "Map service -> URL do repositório ECR."
}

# EC2
output "ec2_instance_ids" {
  value = {
    usersapi    = module.ec2_usersapi.instance_id
    gamesapi    = module.ec2_gamesapi.instance_id
    paymentsapi = module.ec2_paymentsapi.instance_id
  }
  description = "Map service -> instance_id."
}

# IAM
output "github_actions_role_arn" {
  value       = module.iam_github_oidc.role_arn
  description = "ARN da role OIDC para GitHub Actions."
}

# SSM
output "ssm_parameter_prefixes" {
  value       = module.ssm.parameter_prefixes
  description = "Prefixos dos paths SSM por serviço."
}
```

---

## Resumo dos módulos e ordem

| Ordem | Módulo           | Dependências principais                          |
|-------|------------------|--------------------------------------------------|
| 1     | vpc              | —                                                |
| 2     | security_groups  | vpc_id                                           |
| 3     | ecr              | —                                                |
| 4     | iam_github_oidc  | —                                                |
| 5     | iam_ec2_*        | ecr (repository_arns)                            |
| 6     | alb              | vpc, security_groups                             |
| 7     | ec2_*            | vpc, security_groups, iam_ec2_*, alb (tg_arns)   |
| 8     | ssm              | —                                                |
| 9     | api_gateway      | vpc, alb (alb_arn)                               |

---

*Documento: composição do ambiente production — FCG Fenix. Nomenclatura: fcg-fenix-{aplicacao-ws}-{identificador}; sem "prod" nos nomes.*
