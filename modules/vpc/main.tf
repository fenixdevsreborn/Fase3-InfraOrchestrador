# VPC mínima: subnets privadas para RDS (e opcionalmente Lambdas)
# Para baixo custo: single AZ ou duas AZs; sem NAT Gateway inicial (Lambdas fora da VPC).

resource "aws_vpc" "main" {
  cidr_block           = var.cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = merge(var.tags, {
    Name = var.name
  })
}

# Subnets privadas (2 AZs para RDS multi-AZ no futuro; hoje 1 pode ser suficiente)
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "private" {
  count             = min(2, length(data.aws_availability_zones.available.names))
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.cidr, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = merge(var.tags, {
    Name = "${var.name}-private-${count.index + 1}"
  })
}

# DB subnet group (RDS exige)
resource "aws_db_subnet_group" "main" {
  name       = "${var.name}-db"
  subnet_ids = aws_subnet.private[*].id
  tags       = var.tags
}

# Security group para RDS: apenas tráfego interno (ex.: Lambda ou ECS na mesma VPC)
# Para acesso público temporário (demo), pode-se abrir 5432 para um CIDR específico.
resource "aws_security_group" "rds" {
  name_prefix = "${var.name}-rds-"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = aws_vpc.main.id
  tags        = var.tags

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.cidr]
    description = "PostgreSQL from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}
