# Módulo API Gateway HTTP API — VPC Link + NLB (ponte) + ALB
# Fluxo: API Gateway -> VPC Link -> NLB -> ALB (listener) -> target groups -> EC2
# Rotas: ANY /users/{proxy+}, ANY /games/{proxy+}, ANY /payments/{proxy+}
# Stage: $default com auto deploy (path não inclui stage)

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  name_prefix = var.project_name
  tags_shared  = merge(var.tags_base, {
    Application = "shared"
    Service     = "shared"
  })
  nlb_name = "${local.name_prefix}-main-nlb"

  # Formato JSON de access log (variáveis $context.* interpretadas pela AWS).
  # Ver: https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-logging-variables.html
  apigw_access_log_format = jsonencode({
    requestId          = "$context.requestId"
    requestTime        = "$context.requestTime"
    httpMethod         = "$context.httpMethod"
    routeKey           = "$context.routeKey"
    status             = "$context.status"
    protocol           = "$context.protocol"
    responseLength     = "$context.responseLength"
    sourceIp           = "$context.identity.sourceIp"
    integrationLatency = "$context.integrationLatency"
    integrationStatus  = "$context.integrationStatus"
    error              = "$context.error.message"
    integrationError   = "$context.integrationErrorMessage"
  })

  # Issuer = claim iss; a AWS resolve JWKS via {issuer}/.well-known/openid-configuration (Users API com PathBase /users).
  users_jwt_issuer_effective = length(trimspace(var.users_api_jwt_issuer)) > 0 ? trimspace(var.users_api_jwt_issuer) : "https://${aws_apigatewayv2_api.main.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/users"
}

# --- NLB (ponte entre VPC Link e ALB) ---
resource "aws_lb" "nlb" {
  name               = local.nlb_name
  internal           = true
  load_balancer_type = "network"
  subnets            = var.private_subnet_ids

  enable_cross_zone_load_balancing = true

  tags = merge(local.tags_shared, {
    Name = local.nlb_name
  })
}

# Target group do NLB: target_type = alb (ALB como target)
resource "aws_lb_target_group" "alb" {
  name        = "${local.name_prefix}-main-nlb-tg"
  port        = var.alb_listener_port
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "alb"

  # Com target_type = alb, a AWS exige health check HTTP ou HTTPS (não TCP).
  # O ALB interno usa default fixed-response 404 em "/" (sem regra); matcher 404 = ALB respondendo.
  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/"
    port                = "traffic-port"
    matcher             = "404"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = merge(local.tags_shared, {
    Name = "${local.name_prefix}-main-nlb-tg"
  })
}

resource "aws_lb_target_group_attachment" "alb" {
  target_group_arn = aws_lb_target_group.alb.arn
  target_id       = var.alb_arn
  port            = var.alb_listener_port
}

# Listener do NLB (porta 80 -> target group do ALB)
resource "aws_lb_listener" "nlb" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = "80"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb.arn
  }
}

# --- VPC Link (conecta API Gateway ao NLB na VPC) ---
resource "aws_apigatewayv2_vpc_link" "main" {
  name               = "${local.name_prefix}-main-vpclink"
  subnet_ids         = var.private_subnet_ids
  security_group_ids = var.vpc_link_security_group_ids

  tags = merge(local.tags_shared, {
    Name = "${local.name_prefix}-main-vpclink"
  })
}

# --- API Gateway HTTP API ---
resource "aws_apigatewayv2_api" "main" {
  name          = "${local.name_prefix}-main-apigw"
  description   = var.api_description
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
    allow_headers = ["*"]
    max_age       = 300
  }

  tags = merge(local.tags_shared, {
    Name = "${local.name_prefix}-main-apigw"
  })
}

# JWT emitido pela Users API: validação no edge (JWKS via OIDC discovery em {issuer}/.well-known/openid-configuration).
# Não anexar em /users para não bloquear POST /users/auth/login e .well-known.
resource "aws_apigatewayv2_authorizer" "users_jwt" {
  count = var.jwt_authorizer_enabled ? 1 : 0

  api_id           = aws_apigatewayv2_api.main.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "${local.name_prefix}-users-jwt"

  jwt_configuration {
    audience = var.users_api_jwt_audience
    issuer   = local.users_jwt_issuer_effective
  }

  lifecycle {
    precondition {
      condition     = length(var.users_api_jwt_audience) > 0
      error_message = "Defina users_api_jwt_audience (ex.: [\"fcg-cloud-platform\"]) quando jwt_authorizer_enabled = true."
    }
  }
}

# --- CloudWatch: access logs da HTTP API (stage $default) ---
resource "aws_cloudwatch_log_group" "api_gateway_access" {
  name              = "/aws/apigateway/${local.name_prefix}-main-http-access"
  retention_in_days = var.api_gateway_access_log_retention_days

  tags = merge(local.tags_shared, {
    Name = "${local.name_prefix}-apigw-access-logs"
  })
}

# Permite que o serviço API Gateway escreva no log group (HTTP API v2).
resource "aws_cloudwatch_log_resource_policy" "api_gateway_access" {
  policy_name = "${local.name_prefix}-apigw-http-access-logs"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAPIGatewayPushToCWLogs"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.api_gateway_access.arn}:*"
        Condition = {
          ArnLike = {
            "aws:SourceArn" = "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.main.id}/*/*"
          }
        }
      }
    ]
  })
}

# Integração privada: VPC Link -> listener do NLB (AWS exige ARN do listener ELB, não URL http://)
resource "aws_apigatewayv2_integration" "alb" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_uri    = aws_lb_listener.nlb.arn
  integration_method = "ANY"

  connection_type        = "VPC_LINK"
  connection_id          = aws_apigatewayv2_vpc_link.main.id
  payload_format_version = "1.0"
}

# Rotas: ANY /users/{proxy+}, ANY /games/{proxy+}, ANY /payments/{proxy+}
# A ordem (priority) define precedência; path mais específico primeiro se necessário.
resource "aws_apigatewayv2_route" "path" {
  for_each = var.route_paths

  api_id    = aws_apigatewayv2_api.main.id
  route_key = "ANY ${each.key}/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.alb.id}"

  authorization_type = var.jwt_authorizer_enabled && contains(var.jwt_authorizer_route_prefixes, each.key) ? "JWT" : "NONE"
  authorizer_id      = var.jwt_authorizer_enabled && contains(var.jwt_authorizer_route_prefixes, each.key) ? aws_apigatewayv2_authorizer.users_jwt[0].id : null
}

# Rotas exatas: ANY /users, ANY /games, ANY /payments (sem proxy+)
resource "aws_apigatewayv2_route" "path_exact" {
  for_each = var.route_paths

  api_id    = aws_apigatewayv2_api.main.id
  route_key = "ANY ${each.key}"
  target    = "integrations/${aws_apigatewayv2_integration.alb.id}"

  authorization_type = var.jwt_authorizer_enabled && contains(var.jwt_authorizer_route_prefixes, each.key) ? "JWT" : "NONE"
  authorizer_id      = var.jwt_authorizer_enabled && contains(var.jwt_authorizer_route_prefixes, each.key) ? aws_apigatewayv2_authorizer.users_jwt[0].id : null
}

# Webhook do provedor de pagamento: anônimo no edge ([AllowAnonymous] na Payments API).
# Com ASPNETCORE_PATHBASE=/payments na Payments API, o path da app é /payments/webhooks/provider → URL pública dupla: /payments/payments/webhooks/provider.
resource "aws_apigatewayv2_route" "payments_webhook_provider" {
  count = contains(keys(var.route_paths), "/payments") ? 1 : 0

  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "POST /payments/payments/webhooks/provider"
  target             = "integrations/${aws_apigatewayv2_integration.alb.id}"
  authorization_type = "NONE"
}

# Stage $default: auto deploy, sem path prefix (invoke URL = https://api-id.execute-api.region.amazonaws.com/)
# Access logs (CloudWatch) + métricas detalhadas e nível de log de execução na rota padrão (console "Metrics / Logging").
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_access.arn
    format          = local.apigw_access_log_format
  }

  default_route_settings {
    throttling_burst_limit = 100
    throttling_rate_limit  = 50

    detailed_metrics_enabled = var.api_gateway_detailed_metrics_enabled
    logging_level            = var.api_gateway_route_logging_level
    data_trace_enabled       = var.api_gateway_data_trace_enabled
  }

  tags = merge(local.tags_shared, {
    Name = "${local.name_prefix}-main-apigw-default"
  })

  # Garante política do log group antes do stage passar a enviar access logs.
  depends_on = [aws_cloudwatch_log_resource_policy.api_gateway_access]
}
