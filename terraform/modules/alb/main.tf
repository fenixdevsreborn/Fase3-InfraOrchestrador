# Módulo ALB — ALB interno, listener, target groups, listener rules por path
# Naming: fcg-fenix-main-alb, fcg-fenix-main-listener, fcg-fenix-{service}-tg

locals {
  name_prefix = var.project_name
  tags_shared  = merge(var.tags_base, {
    Application = "shared"
    Service     = "shared"
  })
  tags_for_service = {
    for svc in var.services : svc => merge(var.tags_base, {
      Application = svc
      Service     = svc
    })
  }
}

# --- ALB interno ---
resource "aws_lb" "main" {
  name               = "${local.name_prefix}-main-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.private_subnet_ids

  enable_deletion_protection = false
  idle_timeout               = 60

  tags = merge(local.tags_shared, {
    Name = "${local.name_prefix}-main-alb"
  })
}

# --- Target groups (um por serviço) ---
resource "aws_lb_target_group" "api" {
  for_each = toset(var.services)

  name     = "${local.name_prefix}-${each.key}-tg"
  port     = var.target_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = var.health_check_path
    matcher             = var.health_check_matcher
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = merge(local.tags_for_service[each.key], {
    Name = "${local.name_prefix}-${each.key}-tg"
  })
}

# --- Listener (porta 80); default action = fixed-response 404 ---
resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }

  tags = merge(local.tags_shared, {
    Name = "${local.name_prefix}-main-listener"
  })
}

# --- Listener rules: path pattern /users/* -> usersapi-tg, etc. ---
resource "aws_lb_listener_rule" "path" {
  for_each = var.path_prefix_to_service

  listener_arn = aws_lb_listener.main.arn
  priority     = index(keys(var.path_prefix_to_service), each.key) + 1

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api[each.value].arn
  }

  condition {
    path_pattern {
      values = ["${each.key}/*", "${each.key}"]
    }
  }
}
