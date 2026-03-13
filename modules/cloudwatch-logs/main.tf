# Log groups para API Gateway e Lambdas (observabilidade centralizada)

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.name_prefix}-http-api"
  retention_in_days = var.retention_days
  tags              = var.tags
}

resource "aws_cloudwatch_log_group" "notification_lambda" {
  name              = "/aws/lambda/${var.name_prefix}-notification"
  retention_in_days = var.retention_days
  tags              = var.tags
}

# Permite API Gateway enviar access logs para este log group
resource "aws_cloudwatch_log_resource_policy" "api_gateway" {
  policy_name     = "${var.name_prefix}-apigw-logs"
  policy_document = <<-DOC
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "apigateway.amazonaws.com" },
    "Action": "logs:CreateLogDelivery",
    "Resource": "${aws_cloudwatch_log_group.api_gateway.arn}:*"
  }]
}
DOC
}
