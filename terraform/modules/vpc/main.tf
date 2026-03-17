# Módulo VPC — rede base
# Cria: VPC, subnets públicas/privadas (2 AZs), IGW, NAT Gateway, route tables.
# Naming: fcg-fenix-main-* para recursos compartilhados.

locals {
  name_prefix = var.project_name
  tags_shared = merge(var.tags_base, {
    Application = "shared"
    Service     = "shared"
  })
  # Sufixos para subnets (a, b) conforme ordem das AZs
  az_suffixes = ["a", "b"]
}

# --- VPC ---
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.tags_shared, {
    Name = "${local.name_prefix}-main-vpc"
  })
}

# --- Internet Gateway ---
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.tags_shared, {
    Name = "${local.name_prefix}-main-igw"
  })
}

# --- Subnets públicas ---
resource "aws_subnet" "public" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch  = true

  tags = merge(local.tags_shared, {
    Name = "${local.name_prefix}-public-${local.az_suffixes[count.index]}-subnet"
    Type = "public"
  })
}

# --- Subnets privadas ---
resource "aws_subnet" "private" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(local.tags_shared, {
    Name = "${local.name_prefix}-private-${local.az_suffixes[count.index]}-subnet"
    Type = "private"
  })
}

# --- NAT Gateway (uma por AZ ou única; aqui: única na primeira subnet pública) ---
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.tags_shared, {
    Name = "${local.name_prefix}-main-nat-eip"
  })

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(local.tags_shared, {
    Name = "${local.name_prefix}-main-nat"
  })

  depends_on = [aws_internet_gateway.main]
}

# --- Route table pública ---
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.tags_shared, {
    Name = "${local.name_prefix}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# --- Route table privada ---
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(local.tags_shared, {
    Name = "${local.name_prefix}-private-rt"
  })
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
