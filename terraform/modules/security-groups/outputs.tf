# Módulo Security Groups — outputs

output "alb_sg_id" {
  value       = aws_security_group.alb.id
  description = "ID do security group do ALB (fcg-fenix-alb-sg)."
}

output "alb_sg_arn" {
  value       = aws_security_group.alb.arn
  description = "ARN do security group do ALB."
}

output "usersapi_sg_id" {
  value       = try(aws_security_group.api["usersapi"].id, null)
  description = "ID do security group da EC2 usersapi."
}

output "gamesapi_sg_id" {
  value       = try(aws_security_group.api["gamesapi"].id, null)
  description = "ID do security group da EC2 gamesapi."
}

output "paymentsapi_sg_id" {
  value       = try(aws_security_group.api["paymentsapi"].id, null)
  description = "ID do security group da EC2 paymentsapi."
}

output "api_sg_ids" {
  value       = { for k, v in aws_security_group.api : k => v.id }
  description = "Mapa serviço -> ID do security group (reutilizável para qualquer lista de services)."
}
