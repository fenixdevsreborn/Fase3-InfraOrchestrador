# Blueprint — ECR, ALB, EC2 e IAM (FCG Fenix)

Blueprint dos módulos Terraform: ECR, ALB (interno + target groups + listener rules por path), EC2 por serviço e IAM (role + instance profile) para EC2. Sem API Gateway.

---

## 1. Visão dos módulos

| Módulo | Caminho | Responsabilidade |
|--------|---------|------------------|
| **ECR** | `modules/ecr` | Um repositório por serviço: `fcg-fenix-{service}-ecr`. |
| **ALB** | `modules/alb` | ALB interno `fcg-fenix-main-alb`, listener, target groups `fcg-fenix-{service}-tg`, listener rules por path (`/users/*`, `/games/*`, `/payments/*`). |
| **IAM EC2** | `modules/iam/ec2-api` | Role `fcg-fenix-{service}-role` e instance profile `fcg-fenix-{service}-profile` com SSM e ECR pull. |
| **EC2 API** | `modules/ec2-api` | Uma EC2 privada por serviço `fcg-fenix-{service}-ec2`, user data (Docker), registro no target group. |

---

## 2. Naming

| Recurso | Nome |
|---------|------|
| ECR | `fcg-fenix-usersapi-ecr`, `fcg-fenix-gamesapi-ecr`, `fcg-fenix-paymentsapi-ecr` |
| ALB | `fcg-fenix-main-alb` |
| Listener | `fcg-fenix-main-listener` |
| Target group | `fcg-fenix-usersapi-tg`, `fcg-fenix-gamesapi-tg`, `fcg-fenix-paymentsapi-tg` |
| EC2 | `fcg-fenix-usersapi-ec2`, `fcg-fenix-gamesapi-ec2`, `fcg-fenix-paymentsapi-ec2` |
| IAM role | `fcg-fenix-usersapi-role`, etc. |
| Instance profile | `fcg-fenix-usersapi-profile`, etc. |

---

## 3. Roteamento ALB

| Path pattern | Target group | Serviço |
|--------------|--------------|---------|
| `/users/*` | `fcg-fenix-usersapi-tg` | usersapi |
| `/games/*` | `fcg-fenix-gamesapi-tg` | gamesapi |
| `/payments/*` | `fcg-fenix-paymentsapi-tg` | paymentsapi |
| (default) | fixed-response 404 | — |

---

## 4. Dependências e ordem de composição

1. **VPC** e **security_groups** (já existentes).
2. **ECR** — sem dependência de rede.
3. **IAM ec2-api** — um por serviço; sem dependência de rede.
4. **ALB** — depende de vpc, subnets privadas, security group do ALB; cria target groups (vazios).
5. **EC2-api** — um por serviço; depende de vpc, subnet privada, security group do serviço, instance profile, target group (do ALB).

Ordem no `main.tf`: vpc → security_groups → ecr → iam_ec2_* → alb → ec2_*.

---

## 5. Variáveis e outputs por módulo

### ECR
- **In**: `project_name`, `environment`, `services`, `tags_base`.
- **Out**: `repository_urls` (map service → URL), `repository_arns` (map service → ARN).

### ALB
- **In**: `project_name`, `environment`, `vpc_id`, `private_subnet_ids`, `alb_security_group_id`, `services`, `path_prefix_to_service` (map path_prefix → service, ex. `/users` → usersapi), `target_port`, `tags_base`.
- **Out**: `alb_id`, `alb_arn`, `alb_dns_name`, `listener_arn`, `target_group_arns` (map service → ARN).

### IAM ec2-api
- **In**: `project_name`, `environment`, `service`, `tags_base`, opcional `ecr_repository_arns` (lista de ARNs para pull).
- **Out**: `role_name`, `role_arn`, `instance_profile_name`, `instance_profile_arn`.

### EC2-api
- **In**: `project_name`, `environment`, `service`, `vpc_id`, `private_subnet_ids`, `security_group_id`, `instance_profile_name`, `target_group_arn`, `instance_type`, `target_port` (porta no target group), opcional `ami_id`, `tags_base`.
- **Out**: `instance_id`, `private_ip`, `availability_zone`.

---

## 6. Exemplo de composição (ambiente production)

```hcl
# ECR
module "ecr" {
  source     = "../../modules/ecr"
  project_name = local.project_name
  environment  = local.environment
  services     = local.services
  tags_base     = var.tags_base
}

# IAM por serviço
module "iam_ec2_usersapi" {
  source       = "../../modules/iam/ec2-api"
  project_name = local.project_name
  environment  = local.environment
  service      = "usersapi"
  tags_base    = var.tags_base
  ecr_repository_arns = [module.ecr.repository_arns["usersapi"]]
}
# ... idem gamesapi, paymentsapi ...

# ALB com path rules
module "alb" {
  source                  = "../../modules/alb"
  project_name            = local.project_name
  environment             = local.environment
  vpc_id                  = module.vpc.vpc_id
  private_subnet_ids      = module.vpc.private_subnet_ids
  alb_security_group_id   = module.security_groups.alb_sg_id
  services                = local.services
  path_prefix_to_service  = { "/users" = "usersapi", "/games" = "gamesapi", "/payments" = "paymentsapi" }
  target_port             = 80
  tags_base               = var.tags_base
}

# EC2 por serviço
module "ec2_usersapi" {
  source                 = "../../modules/ec2-api"
  project_name           = local.project_name
  environment            = local.environment
  service                = "usersapi"
  vpc_id                 = module.vpc.vpc_id
  private_subnet_ids     = module.vpc.private_subnet_ids
  security_group_id      = module.security_groups.usersapi_sg_id
  instance_profile_name  = module.iam_ec2_usersapi.instance_profile_name
  target_group_arn       = module.alb.target_group_arns["usersapi"]
  instance_type          = var.instance_type
  target_port            = 80
  tags_base              = var.tags_base
}
# ... idem gamesapi, paymentsapi ...
```

---

## 7. Exemplos de composição (trechos do production)

### ECR + IAM EC2 com ECR pull

```hcl
module "ecr" {
  source       = "../../modules/ecr"
  project_name = local.project_name
  environment  = local.environment
  services     = local.services
  tags_base    = var.tags_base
}

module "iam_ec2_usersapi" {
  source               = "../../modules/iam/ec2-api"
  project_name         = local.project_name
  environment          = local.environment
  service              = "usersapi"
  tags_base            = var.tags_base
  ecr_repository_arns  = [module.ecr.repository_arns["usersapi"]]
}
```

### ALB com path rules

```hcl
locals {
  alb_path_prefix_to_service = {
    "/users"    = "usersapi"
    "/games"    = "gamesapi"
    "/payments" = "paymentsapi"
  }
}

module "alb" {
  source                  = "../../modules/alb"
  project_name            = local.project_name
  environment             = local.environment
  vpc_id                  = module.vpc.vpc_id
  private_subnet_ids      = module.vpc.private_subnet_ids
  alb_security_group_id   = module.security_groups.alb_sg_id
  services                = local.services
  path_prefix_to_service  = local.alb_path_prefix_to_service
  target_port             = var.alb_target_port
  tags_base               = var.tags_base
}
```

### EC2 por serviço

```hcl
module "ec2_usersapi" {
  source                 = "../../modules/ec2-api"
  project_name           = local.project_name
  environment            = local.environment
  service                = "usersapi"
  vpc_id                 = module.vpc.vpc_id
  private_subnet_ids     = module.vpc.private_subnet_ids
  security_group_id      = module.security_groups.usersapi_sg_id
  instance_profile_name  = module.iam_ec2_usersapi.instance_profile_name
  target_group_arn       = module.alb.target_group_arns["usersapi"]
  target_port            = var.alb_target_port
  instance_type          = var.instance_type
  tags_base              = var.tags_base
}
```

---

*Blueprint ECR, ALB, EC2, IAM — FCG Fenix. API Gateway em documento separado.*
