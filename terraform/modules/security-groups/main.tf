# Módulo Security Groups — ALB e EC2 por serviço
# ALB: fcg-fenix-alb-sg | EC2: fcg-fenix-{service}-sg
# Regras: ALB recebe de VPC/API Gateway; EC2 recebe apenas do ALB e do SSM.

locals {
  name_prefix = var.project_name
  tags_shared = merge(var.tags_base, {
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

# --- Security Group do ALB ---
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Security group for main ALB. Allow ingress from VPC/API Gateway and egress to API instances."
  vpc_id      = var.vpc_id

  tags = merge(local.tags_shared, {
    Name = "${local.name_prefix}-alb-sg"
  })
}

# ALB: ingress nas portas configuradas; uma regra por (porta, cidr)
locals {
  alb_ingress_cidrs = length(var.alb_ingress_cidr_blocks) > 0 ? var.alb_ingress_cidr_blocks : ["0.0.0.0/0"]
  alb_ingress_rules = distinct(flatten([
    for port in var.alb_ingress_ports : [
      for cidr in local.alb_ingress_cidrs : { port = port, cidr = cidr }
    ]
  ]))
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  for_each = { for i, r in local.alb_ingress_rules : "${r.port}-${replace(r.cidr, "/", "_")}" => r }

  security_group_id = aws_security_group.alb.id
  description       = "Allow port ${each.value.port} from ${each.value.cidr}"
  from_port         = each.value.port
  to_port           = each.value.port
  protocol          = "tcp"
  cidr_ipv4         = each.value.cidr
}

# ALB: egress apenas para os SGs das EC2 das APIs (nenhum egress para internet)
resource "aws_vpc_security_group_egress_rule" "alb_to_apis" {
  for_each = toset(var.services)

  security_group_id            = aws_security_group.alb.id
  description                  = "Allow ALB to ${each.key}"
  from_port                    = min(var.api_ports...)
  to_port                      = max(var.api_ports...)
  protocol                     = "tcp"
  referenced_security_group_id = aws_security_group.api[each.key].id
}

# --- Security Groups das EC2 (um por serviço) ---
resource "aws_security_group" "api" {
  for_each    = toset(var.services)
  name        = "${local.name_prefix}-${each.key}-sg"
  description = "Security group for ${each.key} EC2. Allow from ALB and SSM."
  vpc_id      = var.vpc_id

  tags = merge(local.tags_for_service[each.key], {
    Name = "${local.name_prefix}-${each.key}-sg"
  })
}

# EC2: ingress apenas do ALB (porta da API)
resource "aws_vpc_security_group_ingress_rule" "api_from_alb" {
  for_each = toset(var.services)

  security_group_id            = aws_security_group.api[each.key].id
  description                  = "Allow from ALB"
  from_port                    = min(var.api_ports...)
  to_port                      = max(var.api_ports...)
  protocol                     = "tcp"
  referenced_security_group_id = aws_security_group.alb.id
}

# EC2: ingress do SSM (porta 443 para Session Manager / Run Command)
resource "aws_vpc_security_group_ingress_rule" "api_ssm" {
  for_each = toset(var.services)

  security_group_id = aws_security_group.api[each.key].id
  description       = "Allow SSM Agent"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

# Nota: em produção, o tráfego SSM costuma vir dos endpoints VPC da AWS (com.amazonaws.com). 
# Usar cidr_ipv4 = "0.0.0.0/0" para SSM é permissivo; para endurecer, use VPC endpoints e restrinja o CIDR.

# EC2: egress (saída para internet via NAT para pull de imagens, updates, etc.)
resource "aws_vpc_security_group_egress_rule" "api_egress" {
  for_each = toset(var.services)

  security_group_id = aws_security_group.api[each.key].id
  description       = "Allow all egress"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ALB: sem egress para 0.0.0.0/0 — apenas para os SGs das APIs (princípio do menor privilégio)
