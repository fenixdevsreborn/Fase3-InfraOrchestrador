output "repository_urls" {
  description = "Map: repository name (as in var.repository_names) -> repository URL"
  value       = { for k, r in aws_ecr_repository.repos : k => r.repository_url }
}

output "repository_arns" {
  value = { for k, r in aws_ecr_repository.repos : k => r.arn }
}
