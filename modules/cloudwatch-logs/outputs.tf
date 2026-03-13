output "api_gateway_log_group_name" {
  value = aws_cloudwatch_log_group.api_gateway.name
}

output "api_gateway_log_group_arn" {
  value = aws_cloudwatch_log_group.api_gateway.arn
}

output "notification_lambda_log_group_name" {
  value = aws_cloudwatch_log_group.notification_lambda.name
}

output "log_group_names" {
  value = [
    aws_cloudwatch_log_group.api_gateway.name,
    aws_cloudwatch_log_group.notification_lambda.name
  ]
}
