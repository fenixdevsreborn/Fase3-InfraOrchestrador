# Módulo VPC (network)

Rede base para FCG Fenix: VPC, subnets públicas/privadas, IGW, NAT Gateway, route tables.

## Naming

- `{project_name}-main-vpc`
- `{project_name}-main-igw`
- `{project_name}-public-a-subnet`, `{project_name}-public-b-subnet`
- `{project_name}-private-a-subnet`, `{project_name}-private-b-subnet`
- `{project_name}-main-nat`, `{project_name}-main-nat-eip`
- `{project_name}-public-rt`, `{project_name}-private-rt`

Não usar "prod" no nome; recursos compartilhados usam "main".

## Desenho

- **2 AZs**: subnets públicas e privadas em duas availability zones (sufixos a e b na ordem de `availability_zones`).
- **NAT único**: um NAT Gateway na primeira subnet pública para reduzir custo; todo tráfego de saída das privadas passa por ele. Para HA, pode-se evoluir para um NAT por AZ.
- **Route tables**: uma para públicas (rota 0.0.0.0/0 → IGW), uma para privadas (0.0.0.0/0 → NAT). Associações explícitas para cada subnet.
- **DNS**: VPC com `enable_dns_hostnames` e `enable_dns_support` para resolução e nomes de host.

## Segurança

- Subnets privadas **não** têm rota direta para a internet; saída apenas via NAT.
- Nenhum recurso de aplicação (EC2 das APIs) deve ficar em subnet pública; usar sempre subnets privadas para compute.
- Mapas de IP públicos apenas nas subnets públicas (`map_public_ip_on_launch = true` só nas públicas).

## Uso

Garantir que `public_subnet_cidrs` e `private_subnet_cidrs` estejam dentro do `vpc_cidr` e na mesma ordem de `availability_zones`. Exemplo:

```hcl
module "vpc" {
  source = "../../modules/vpc"

  project_name          = "fcg-fenix"
  environment           = "production"
  vpc_cidr              = "10.0.0.0/16"
  availability_zones    = ["us-east-1a", "us-east-1b"]
  public_subnet_cidrs   = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs   = ["10.0.10.0/24", "10.0.11.0/24"]
  tags_base             = { Project = "fcg-fenix", ManagedBy = "terraform", Environment = "production" }
}
```
