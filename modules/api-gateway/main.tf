# API Gateway HTTP API (v2) — custo menor que REST API
# JWT authorizer: quando jwt_issuer_uri é definido, cria authorizer e associa às rotas que precisarem (exemplo com rota catch-all).

resource "aws_apigatewayv2_api" "main" {
  name          = "${var.name_prefix}-api"
  protocol_type = "HTTP"
  description   = "FCG Cloud Platform HTTP API"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
    allow_headers = ["authorization", "content-type", "x-correlation-id", "x-api-key"]
    max_age       = 300
  }

  tags = var.tags
}

# Log group para access logs (quando não se passa um existente)
resource "aws_cloudwatch_log_group" "api" {
  count             = var.access_log_group_arn != null && var.access_log_group_arn != "" ? 0 : 1
  name              = "/aws/apigateway/${var.name_prefix}-http-api"
  retention_in_days = 14
  tags              = var.tags
}

locals {
  access_log_destination_arn = (var.access_log_group_arn != null && var.access_log_group_arn != "") ? var.access_log_group_arn : (length(aws_cloudwatch_log_group.api) > 0 ? aws_cloudwatch_log_group.api[0].arn : null)
}

# Integração default (pode ser substituída por integrações Lambda/HTTP por rota)
resource "aws_apigatewayv2_integration" "default" {
  api_id           = aws_apigatewayv2_api.main.id
  integration_type  = "HTTP_PROXY"
  integration_uri   = "https://httpbin.org/anything"
  integration_method = "ANY"
  payload_format_version = "1.0"
  description      = "Placeholder until routes are defined"
}

# Stage $default (invoke URL direto)
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  dynamic "access_log_settings" {
    for_each = local.access_log_destination_arn != null ? [1] : []
    content {
      destination_arn = local.access_log_destination_arn
      format = jsonencode({
        requestId   = "$context.requestId"
        ip          = "$context.identity.sourceIp"
        requestTime = "$context.requestTime"
        httpMethod  = "$context.httpMethod"
        routeKey    = "$context.routeKey"
        status      = "$context.status"
      })
    }
  }

  tags = var.tags
}

# JWT Authorizer (só cria se issuer for informado)
resource "aws_apigatewayv2_authorizer" "jwt" {
  count = var.jwt_issuer_uri != null && var.jwt_issuer_uri != "" ? 1 : 0

  api_id           = aws_apigatewayv2_api.main.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "${var.name_prefix}-jwt"

  jwt_configuration {
    audience = var.jwt_audience
    issuer   = var.jwt_issuer_uri
  }
}

# Rota de exemplo (qualquer path) — sem authorizer; pode duplicar com authorizer_id para rotas protegidas
resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.default.id}"
}

# Permissão para API Gateway escrever no log group
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_log_resource_policy" "api" {
  count           = var.access_log_group_arn != null && var.access_log_group_arn != "" ? 0 : 1
  policy_name     = "${var.name_prefix}-apigw-logs"
  policy_document = <<-DOC
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "apigateway.amazonaws.com" },
    "Action": "logs:CreateLogDelivery",
    "Resource": "${aws_cloudwatch_log_group.api[0].arn}:*"
  }]
}
DOC
}
