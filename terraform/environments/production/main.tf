# Orquestração do ambiente production.
# Ordem lógica: vpc -> security_groups -> alb -> ec2_api; ecr, iam, ssm em paralelo; api_gateway após NLB/VPC Link.
# Naming e tags centralizados em locals.tf.

module "vpc" {
  source = "../../modules/vpc"

  project_name          = local.project_name
  environment           = local.environment
  vpc_cidr              = var.vpc_cidr
  availability_zones    = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  tags_base            = var.tags_base
}

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

module "ecr" {
  source = "../../modules/ecr"

  project_name = local.project_name
  environment  = local.environment
  services     = local.services
  tags_base    = var.tags_base
}
# Outputs: repository_urls, repository_arns

module "iam_github_oidc" {
  source = "../../modules/iam/github-oidc"

  project_name       = local.project_name
  environment        = local.environment
  github_oidc_org    = var.github_oidc_org
  github_oidc_repos  = var.github_oidc_repos
  tags_base          = var.tags_base
}

module "iam_ec2_usersapi" {
  source = "../../modules/iam/ec2-api"

  project_name         = local.project_name
  environment          = local.environment
  service              = "usersapi"
  tags_base            = var.tags_base
  ecr_repository_arns  = [module.ecr.repository_arns["usersapi"]]
}

module "iam_ec2_gamesapi" {
  source = "../../modules/iam/ec2-api"

  project_name         = local.project_name
  environment          = local.environment
  service              = "gamesapi"
  tags_base            = var.tags_base
  ecr_repository_arns  = [module.ecr.repository_arns["gamesapi"]]
}

module "iam_ec2_paymentsapi" {
  source = "../../modules/iam/ec2-api"

  project_name         = local.project_name
  environment          = local.environment
  service              = "paymentsapi"
  tags_base            = var.tags_base
  ecr_repository_arns  = [module.ecr.repository_arns["paymentsapi"]]
}

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

module "ec2_usersapi" {
  source = "../../modules/ec2-api"

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

module "ec2_gamesapi" {
  source = "../../modules/ec2-api"

  project_name           = local.project_name
  environment            = local.environment
  service                = "gamesapi"
  vpc_id                 = module.vpc.vpc_id
  private_subnet_ids     = module.vpc.private_subnet_ids
  security_group_id      = module.security_groups.gamesapi_sg_id
  instance_profile_name  = module.iam_ec2_gamesapi.instance_profile_name
  target_group_arn       = module.alb.target_group_arns["gamesapi"]
  target_port            = var.alb_target_port
  instance_type          = var.instance_type
  tags_base              = var.tags_base
}

module "ec2_paymentsapi" {
  source = "../../modules/ec2-api"

  project_name           = local.project_name
  environment            = local.environment
  service                = "paymentsapi"
  vpc_id                 = module.vpc.vpc_id
  private_subnet_ids     = module.vpc.private_subnet_ids
  security_group_id      = module.security_groups.paymentsapi_sg_id
  instance_profile_name  = module.iam_ec2_paymentsapi.instance_profile_name
  target_group_arn       = module.alb.target_group_arns["paymentsapi"]
  target_port            = var.alb_target_port
  instance_type          = var.instance_type
  tags_base              = var.tags_base
}

module "ssm" {
  source = "../../modules/ssm"

  project_name = local.project_name
  environment  = local.environment
  services     = local.services
  tags_base    = var.tags_base
}

module "api_gateway" {
  source = "../../modules/api-gateway"

  project_name         = local.project_name
  environment          = local.environment
  vpc_id               = module.vpc.vpc_id
  private_subnet_ids   = module.vpc.private_subnet_ids
  alb_arn              = module.alb.alb_arn
  alb_listener_port    = var.alb_target_port
  route_paths          = local.alb_path_prefix_to_service
  tags_base            = var.tags_base
}
