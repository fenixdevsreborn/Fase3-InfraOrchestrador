# ------------------------------------------------------------------------------
# Bootstrap — outputs para configurar backend nos environments
# ------------------------------------------------------------------------------

output "state_bucket_name" {
  description = "Nome do bucket S3 do state."
  value       = aws_s3_bucket.state.id
}

output "state_bucket_arn" {
  description = "ARN do bucket S3 do state."
  value       = aws_s3_bucket.state.arn
}

output "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB de lock."
  value       = aws_dynamodb_table.locks.name
}

output "dynamodb_table_arn" {
  description = "ARN da tabela DynamoDB de lock."
  value       = aws_dynamodb_table.locks.arn
}

output "backend_config_hint" {
  description = "Exemplo de backend.hcl para environments/<env>/backend.hcl"
  value       = <<-EOT
    # Use em environments/<env>/backend.hcl (substitua ENV por prod, staging ou demo):
    bucket         = "${aws_s3_bucket.state.id}"
    key            = "fcg-infra/ENV/terraform.tfstate"
    region         = "${var.aws_region}"
    dynamodb_table = "${aws_dynamodb_table.locks.name}"
    encrypt        = true
  EOT
}
