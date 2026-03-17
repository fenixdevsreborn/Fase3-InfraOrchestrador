output "repository_urls" {
  value       = { for k, v in aws_ecr_repository.api : k => v.repository_url }
  description = "Mapa serviço -> URL do repositório ECR."
}

output "repository_arns" {
  value       = { for k, v in aws_ecr_repository.api : k => v.arn }
  description = "Mapa serviço -> ARN do repositório ECR (para políticas IAM)."
}

output "repository_names" {
  value       = { for k, v in aws_ecr_repository.api : k => v.name }
  description = "Mapa serviço -> nome do repositório."
}
