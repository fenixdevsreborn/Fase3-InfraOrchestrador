# Módulo ECR — um repositório por serviço
# Naming: fcg-fenix-{service}-ecr

locals {
  name_prefix = var.project_name
  tags_for_service = {
    for svc in var.services : svc => merge(var.tags_base, {
      Application = svc
      Service     = svc
    })
  }
}

resource "aws_ecr_repository" "api" {
  for_each = toset(var.services)

  name                 = "${local.name_prefix}-${each.key}-ecr"
  image_tag_mutability = var.image_tag_mutability
  image_scanning_configuration {
    scan_on_push = true
  }

  dynamic "encryption_configuration" {
    for_each = var.encrypt_images ? [1] : []
    content {
      encryption_type = "AES256"
    }
  }

  tags = merge(local.tags_for_service[each.key], {
    Name = "${local.name_prefix}-${each.key}-ecr"
  })
}

# Política de lifecycle opcional: manter últimas N imagens
resource "aws_ecr_lifecycle_policy" "api" {
  for_each   = toset(var.services)
  repository = aws_ecr_repository.api[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Manter últimas 10 imagens"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
