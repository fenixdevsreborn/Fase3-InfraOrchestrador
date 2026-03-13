output "api_id" {
  value = aws_apigatewayv2_api.main.id
}

output "api_endpoint" {
  value = aws_apigatewayv2_stage.default.invoke_url
}

output "api_execution_arn" {
  value = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

output "jwt_authorizer_id" {
  value = length(aws_apigatewayv2_authorizer.jwt) > 0 ? aws_apigatewayv2_authorizer.jwt[0].id : null
}
