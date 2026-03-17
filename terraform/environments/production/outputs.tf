# Outputs do ambiente production (reexposição dos módulos).

output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "ID da VPC fcg-fenix-main-vpc."
}

output "private_subnet_ids" {
  value       = module.vpc.private_subnet_ids
  description = "IDs das subnets privadas."
}

output "alb_dns_name" {
  value       = module.alb.alb_dns_name
  description = "DNS name do ALB interno."
}

output "target_group_arns" {
  value       = module.alb.target_group_arns
  description = "Map service -> ARN do target group."
}

output "api_gateway_invoke_url" {
  value       = module.api_gateway.invoke_url
  description = "URL de invocação da HTTP API ($default stage)."
}

output "ecr_repository_urls" {
  value       = module.ecr.repository_urls
  description = "Map service -> URL do repositório ECR."
}

output "ec2_instance_ids" {
  value = {
    usersapi    = module.ec2_usersapi.instance_id
    gamesapi    = module.ec2_gamesapi.instance_id
    paymentsapi = module.ec2_paymentsapi.instance_id
  }
  description = "Map service -> instance_id."
}

output "github_actions_role_arn" {
  value       = module.iam_github_oidc.role_arn
  description = "ARN da role OIDC para GitHub Actions."
}

output "ssm_parameter_prefixes" {
  value       = module.ssm.parameter_prefixes
  description = "Prefixos dos paths SSM por serviço."
}
