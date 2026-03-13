output "function_name" {
  value = aws_lambda_function.main.function_name
}

output "function_arn" {
  value = aws_lambda_function.main.arn
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.lambda.name
}
