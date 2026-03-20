# Módulo EC2 API — uma instância privada por serviço
# Naming: fcg-fenix-{service}-ec2
# User data: instala Docker e prepara diretório /opt/fcg-fenix/{service}

locals {
  name_prefix  = var.project_name
  instance_name = "${local.name_prefix}-${var.service}-ec2"
  tags_service  = merge(var.tags_base, {
    Application = var.service
    Service     = var.service
  })
  subnet_id = var.private_subnet_ids[var.subnet_index]
}

# AMI: Amazon Linux 2 se ami_id não for informado
data "aws_ami" "amazon_linux_2" {
  count       = var.ami_id == null ? 1 : 0
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

locals {
  ami_to_use = coalesce(var.ami_id, try(data.aws_ami.amazon_linux_2[0].id, ""))
}

# User data: Docker + diretório da aplicação
locals {
  user_data = <<-EOT
#!/bin/bash
set -e
yum update -y
# AWS CLI: necessário no deploy via SSM (aws ecr get-login-password na instância)
yum install -y awscli
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user
mkdir -p /opt/fcg-fenix/${var.service}
chown -R ec2-user:ec2-user /opt/fcg-fenix/${var.service}
EOT
}

resource "aws_instance" "api" {
  ami                    = local.ami_to_use
  instance_type          = var.instance_type
  subnet_id              = local.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = var.instance_profile_name

  user_data                   = local.user_data
  user_data_replace_on_change = true

  # IMDSv2 obrigatório (recomendação AWS; reduz risco de SSRF contra metadata).
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  tags = merge(local.tags_service, {
    Name = local.instance_name
  })
}

# Registro da instância no target group
resource "aws_lb_target_group_attachment" "api" {
  target_group_arn = var.target_group_arn
  target_id        = aws_instance.api.id
  port             = var.target_port
}
