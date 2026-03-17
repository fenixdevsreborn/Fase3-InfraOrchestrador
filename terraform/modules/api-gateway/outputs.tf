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
