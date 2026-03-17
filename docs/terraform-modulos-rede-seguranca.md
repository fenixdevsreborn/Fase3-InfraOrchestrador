# Módulos Terraform — Rede e Segurança (FCG Fenix)

Observações sobre desenho e segurança dos módulos **vpc** (network) e **security-groups**.

---

## 1. Módulo VPC (network)

### Estrutura de arquivos

- `terraform/modules/vpc/variables.tf`
- `terraform/modules/vpc/main.tf`
- `terraform/modules/vpc/outputs.tf`
- `terraform/modules/vpc/README.md`

### Naming

| Recurso      | Nome (exemplo)                |
|-------------|--------------------------------|
| VPC         | `fcg-fenix-main-vpc`          |
| IGW         | `fcg-fenix-main-igw`          |
| Subnet pub  | `fcg-fenix-public-a-subnet`, `fcg-fenix-public-b-subnet` |
| Subnet priv | `fcg-fenix-private-a-subnet`, `fcg-fenix-private-b-subnet` |
| NAT         | `fcg-fenix-main-nat`          |
| EIP NAT      | `fcg-fenix-main-nat-eip`     |
| Route table  | `fcg-fenix-public-rt`, `fcg-fenix-private-rt` |

Não usar "prod" no nome; recursos compartilhados usam **main**.

### Desenho

- **2 AZs**: duas subnets públicas e duas privadas; sufixos `a` e `b` seguem a ordem de `availability_zones`.
- **NAT único**: um NAT Gateway na primeira subnet pública para reduzir custo; evolução possível para um NAT por AZ (HA).
- **Route tables**: uma pública (0.0.0.0/0 → IGW) e uma privada (0.0.0.0/0 → NAT); associações explícitas por subnet.
- **DNS**: `enable_dns_hostnames` e `enable_dns_support` na VPC.

### Segurança

- Subnets privadas não têm rota direta para a internet; saída apenas via NAT.
- Compute (EC2 das APIs) deve ficar **sempre** em subnets privadas.
- IP público apenas nas subnets públicas (`map_public_ip_on_launch = true` só nelas).

### Variáveis obrigatórias no ambiente

- `public_subnet_cidrs` e `private_subnet_cidrs` na mesma ordem de `availability_zones` e dentro do `vpc_cidr`.

---

## 2. Módulo Security Groups

### Estrutura de arquivos

- `terraform/modules/security-groups/variables.tf`
- `terraform/modules/security-groups/main.tf`
- `terraform/modules/security-groups/outputs.tf`
- `terraform/modules/security-groups/README.md`

### Naming

| Recurso | Nome (exemplo)           |
|---------|---------------------------|
| ALB     | `fcg-fenix-alb-sg`       |
| EC2     | `fcg-fenix-usersapi-sg`, `fcg-fenix-gamesapi-sg`, `fcg-fenix-paymentsapi-sg` |

### Desenho

- **ALB**: um SG compartilhado. Ingress nas portas configuráveis (ex. 80, 443) a partir de CIDRs (em produção: CIDR da VPC para API Gateway via VPC Link). Egress **apenas** para os SGs das EC2 das APIs; sem egress para 0.0.0.0/0.
- **EC2**: um SG por serviço. Ingress (1) do ALB na porta da API e (2) 443 para SSM. Egress livre para pull de imagens e updates.

### Segurança

- **Menor privilégio**: ALB só pode enviar tráfego para os SGs das APIs, não para a internet.
- **EC2**: recebem tráfego apenas do ALB (aplicação) e SSM (gerenciamento). Ingress SSM com 0.0.0.0/0 é permissivo; para endurecer, usar VPC endpoints e restringir CIDR.
- **Tags**: ALB com Application/Service = shared; cada SG de EC2 com Application/Service = nome do serviço.

### Ingress do ALB em produção

- Usar `alb_ingress_cidr_blocks = [module.vpc.vpc_cidr_block]` para que apenas tráfego interno (ex. VPC Link) alcance o ALB. Evitar 0.0.0.0/0 em produção.

---

## 3. Ordem e dependências

1. **vpc** — sem dependências; expõe `vpc_id`, `vpc_cidr_block`, `public_subnet_ids`, `private_subnet_ids`.
2. **security_groups** — depende de `vpc_id` (e em produção de `vpc_cidr_block` para ingress do ALB).

O ambiente production já passa `public_subnet_cidrs` e `private_subnet_cidrs` ao VPC e `alb_ingress_cidr_blocks = [module.vpc.vpc_cidr_block]` ao módulo de security groups.
