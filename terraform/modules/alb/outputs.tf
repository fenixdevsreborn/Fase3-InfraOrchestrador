output "alb_id" {
  value       = aws_lb.main.id
  description = "ID do ALB (fcg-fenix-main-alb)."
}

output "alb_arn" {
  value       = aws_lb.main.arn
  description = "ARN do ALB."
}

output "alb_dns_name" {
  value       = aws_lb.main.dns_name
  description = "DNS name do ALB."
}

output "alb_zone_id" {
  value       = aws_lb.main.zone_id
  description = "Zone ID do ALB (para alias DNS)."
}

output "listener_arn" {
  value       = aws_lb_listener.main.arn
  description = "ARN do listener na porta 80."
}

output "target_group_arns" {
  value       = { for k, v in aws_lb_target_group.api : k => v.arn }
  description = "Mapa serviço -> ARN do target group."
}

output "target_group_ids" {
  value       = { for k, v in aws_lb_target_group.api : k => v.id }
  description = "Mapa serviço -> ID do target group."
}
