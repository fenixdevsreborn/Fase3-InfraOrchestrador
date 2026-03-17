output "role_name" {
  value       = aws_iam_role.ec2_api.name
  description = "Nome da IAM role (fcg-fenix-{service}-role)."
}

output "role_arn" {
  value       = aws_iam_role.ec2_api.arn
  description = "ARN da IAM role."
}

output "instance_profile_name" {
  value       = aws_iam_instance_profile.ec2_api.name
  description = "Nome do instance profile (fcg-fenix-{service}-profile)."
}

output "instance_profile_arn" {
  value       = aws_iam_instance_profile.ec2_api.arn
  description = "ARN do instance profile."
}
