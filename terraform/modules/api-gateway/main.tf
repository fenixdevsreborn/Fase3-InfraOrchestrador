# Módulo API Gateway HTTP API — VPC Link + NLB (ponte) + ALB
# Fluxo: API Gateway -> VPC Link -> NLB -> ALB (listener) -> target groups -> EC2
# Rotas: ANY /users/{proxy+}, ANY /games/{proxy+}, ANY /payments/{proxy+}
# Stage: $default com auto deploy (path não inclui stage)

locals {
  name_prefix = var.project_name
  tags_shared  = merge(var.tags_base, {
    Application = "shared"
    Service     = "shared"
  })
  nlb_name = "${local.name_prefix}-main-nlb"
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

  health_check {
    enabled             = true
    protocol            = "TCP"
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

# Integração privada: VPC Link -> NLB (uri = NLB:80)
resource "aws_apigatewayv2_integration" "alb" {
  api_id           = aws_apigatewayv2_api.main.id
  integration_type = "HTTP_PROXY"
  integration_uri  = "http://${aws_lb.nlb.dns_name}:${var.alb_listener_port}"

  connection_type        = "VPC_LINK"
  connection_id          = aws_apigatewayv2_vpc_link.main.id
  integration_method     = "ANY"
  payload_format_version = "1.0"
}

# Rotas: ANY /users/{proxy+}, ANY /games/{proxy+}, ANY /payments/{proxy+}
# A ordem (priority) define precedência; path mais específico primeiro se necessário.
resource "aws_apigatewayv2_route" "path" {
  for_each = var.route_paths

  api_id    = aws_apigatewayv2_api.main.id
  route_key = "ANY ${each.key}/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.alb.id}"
}

# Rotas exatas: ANY /users, ANY /games, ANY /payments (sem proxy+)
resource "aws_apigatewayv2_route" "path_exact" {
  for_each = var.route_paths

  api_id    = aws_apigatewayv2_api.main.id
  route_key = "ANY ${each.key}"
  target    = "integrations/${aws_apigatewayv2_integration.alb.id"
}

# Stage $default: auto deploy, sem path prefix (invoke URL = https://api-id.execute-api.region.amazonaws.com/)
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 100
    throttling_rate_limit  = 50
  }

  tags = merge(local.tags_shared, {
    Name = "${local.name_prefix}-main-apigw-default"
  })
}
