output "instance_id" {
  value       = aws_instance.api.id
  description = "ID da instância EC2."
}

output "private_ip" {
  value       = aws_instance.api.private_ip
  description = "IP privado da instância."
}

output "availability_zone" {
  value       = aws_instance.api.availability_zone
  description = "AZ da instância."
}

output "instance_arn" {
  value       = aws_instance.api.arn
  description = "ARN da instância."
}
