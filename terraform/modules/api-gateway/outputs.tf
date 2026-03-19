output "api_id" {
  value       = aws_apigatewayv2_api.main.id
  description = "ID da API Gateway HTTP API (fcg-fenix-main-apigw)."
}

output "api_endpoint" {
  value       = aws_apigatewayv2_api.main.api_endpoint
  description = "Endpoint base da API (sem stage no path; $default)."
}

output "invoke_url" {
  value       = aws_apigatewayv2_stage.default.invoke_url
  description = "URL de invocação (ex.: https://api-id.execute-api.region.amazonaws.com)."
}

output "vpc_link_id" {
  value       = aws_apigatewayv2_vpc_link.main.id
  description = "ID do VPC Link (fcg-fenix-main-vpclink)."
}

output "nlb_dns_name" {
  value       = aws_lb.nlb.dns_name
  description = "DNS name do NLB (ponte para o ALB)."
}

output "stage_name" {
  value       = aws_apigatewayv2_stage.default.name
  description = "Nome do stage ($default)."
}

output "access_log_group_name" {
  value       = aws_cloudwatch_log_group.api_gateway_access.name
  description = "Nome do log group no CloudWatch para access logs da HTTP API."
}

output "access_log_group_arn" {
  value       = aws_cloudwatch_log_group.api_gateway_access.arn
  description = "ARN do log group de access logs da API Gateway."
}

output "jwt_authorizer_id" {
  value       = var.jwt_authorizer_enabled ? aws_apigatewayv2_authorizer.users_jwt[0].id : null
  description = "ID do authorizer JWT (null se jwt_authorizer_enabled = false)."
}

output "users_jwt_issuer_effective" {
  value       = local.users_jwt_issuer_effective
  description = "Issuer usado no authorizer JWT; deve coincidir com Jwt:Issuer na Users API e nos tokens."
}
