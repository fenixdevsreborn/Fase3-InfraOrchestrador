# Módulo IAM EC2 API — role e instance profile por serviço
# Naming: fcg-fenix-{service}-role, fcg-fenix-{service}-profile
# Permissões: SSM (Run Command, Session Manager) e ECR pull.

locals {
  name_prefix = var.project_name
  role_name   = "${local.name_prefix}-${var.service}-role"
  profile_name = "${local.name_prefix}-${var.service}-profile"
  tags_service = merge(var.tags_base, {
    Application = var.service
    Service     = var.service
  })
}

# --- Role ---
resource "aws_iam_role" "ec2_api" {
  name = local.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.tags_service, {
    Name = local.role_name
  })
}

# --- SSM: Run Command e Session Manager ---
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_api.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# --- CloudWatch Agent: envio de logs e métricas da instância ---
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2_api.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# --- ECR: GetAuthorizationToken (contas) + pull apenas nos repositórios listados ---
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Política inline: ECR pull restrito aos ARNs informados
resource "aws_iam_role_policy" "ecr_pull" {
  count = length(var.ecr_repository_arns) > 0 ? 1 : 0

  name   = "${local.name_prefix}-${var.service}-ecr-pull"
  role   = aws_iam_role.ec2_api.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GetAuthorizationToken"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "PullFromRepositories"
        Effect = "Allow"
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = var.ecr_repository_arns
      }
    ]
  })
}

# --- Instance profile ---
resource "aws_iam_instance_profile" "ec2_api" {
  name = local.profile_name
  role = aws_iam_role.ec2_api.name

  tags = merge(local.tags_service, {
    Name = local.profile_name
  })
}
