# Terraform — FCG Fenix

Estrutura Terraform do repositório de infraestrutura. Ver **docs/terraform-blueprint.md** para o blueprint completo (módulos, ordem, variáveis, outputs).

## Como executar

O root do Terraform é `terraform/environments/production`. A partir da raiz do repositório:

```bash
cd terraform/environments/production
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

Ou, a partir da raiz do repo:

```bash
terraform -chdir=terraform/environments/production init
terraform -chdir=terraform/environments/production plan -var-file=terraform.tfvars
terraform -chdir=terraform/environments/production apply -var-file=terraform.tfvars
```

## Antes do primeiro apply

1. Criar bucket S3 `fcg-fenix-tfstate` e tabela DynamoDB para lock (ex.: `fcg-fenix-tfstate-lock`).
2. Descomentar e ajustar o bloco `backend "s3"` em `environments/production/backend.tf`.
3. Copiar `terraform.tfvars.example` para `terraform.tfvars` e preencher (sem versionar secrets).

## Módulos

- `vpc` — VPC, subnets, IGW, NAT, route tables
- `security-groups` — SGs do ALB e das EC2
- `ecr` — Repositórios ECR por serviço
- `iam/github-oidc` — Role para GitHub Actions (OIDC)
- `iam/ec2-api` — Role + instance profile por API
- `ec2-api` — EC2 privada por API
- `alb` — ALB interno, listener, target groups
- `api-gateway` — HTTP API + VPC Link
- `ssm` — Parameter Store por serviço

Os arquivos `main.tf` dos módulos estão em modo blueprint (TODO); implementar conforme o blueprint.
