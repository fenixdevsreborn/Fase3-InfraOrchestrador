# FCG Fenix — Blueprint Terraform

Blueprint da estrutura Terraform para o repositório de infraestrutura, alinhado ao SPEC e ao PRD. Nomenclatura: `fcg-fenix-{aplicacao-ws}-{identificador}`. Infraestrutura somente para produção; não usar "prod" no nome dos recursos.

---

## 1. Estrutura de pastas

```
terraform/
├── environments/
│   └── production/
│       ├── main.tf              # Orquestração: chamadas aos módulos
│       ├── variables.tf         # Variáveis do ambiente
│       ├── outputs.tf           # Outputs expostos
│       ├── backend.tf           # Backend remoto S3 + lock (DynamoDB)
│       ├── versions.tf          # Terraform e providers (AWS)
│       ├── terraform.tfvars.example
│       └── terraform.tfvars     # Valores (não versionar secrets)
├── modules/
│   ├── vpc/
│   ├── security-groups/
│   ├── ecr/
│   ├── iam/
│   │   ├── github-oidc/
│   │   └── ec2-api/
│   ├── ec2-api/
│   ├── alb/
│   ├── api-gateway/
│   └── ssm/
└── README.md                    # Como rodar (opcional, na raiz do repo)
```

**Observação:** O ambiente único é `production`. Não existe pasta `dev`/`prod`; o nome do recurso não leva "prod".

---

## 2. Nomes dos módulos

| Módulo             | Caminho                    | Uso |
|--------------------|----------------------------|-----|
| VPC                | `modules/vpc`              | Rede base (VPC, subnets, IGW, NAT, route tables). |
| Security Groups    | `modules/security-groups` | SGs do ALB e das EC2 (usersapi, gamesapi, paymentsapi). |
| ECR                | `modules/ecr`              | Repositórios ECR por serviço. |
| IAM GitHub OIDC    | `modules/iam/github-oidc`  | Role para GitHub Actions (OIDC). |
| IAM EC2 API        | `modules/iam/ec2-api`      | Role + instance profile por API. |
| EC2 API            | `modules/ec2-api`         | Uma instância EC2 por API (usersapi, gamesapi, paymentsapi). |
| ALB                | `modules/alb`              | ALB interno, listener, target groups. |
| API Gateway        | `modules/api-gateway`     | HTTP API + VPC Link (VPC Link aponta para NLB; NLB para ALB ou TGs). |
| SSM                | `modules/ssm`              | Parameter Store (paths por serviço). |

---

## 3. Responsabilidade de cada módulo

### 3.1 `vpc`
- Criar VPC `fcg-fenix-main-vpc`.
- Subnets públicas (2 AZs): `fcg-fenix-public-a-subnet`, `fcg-fenix-public-b-subnet`.
- Subnets privadas (2 AZs): `fcg-fenix-private-a-subnet`, `fcg-fenix-private-b-subnet`.
- Internet Gateway `fcg-fenix-main-igw`.
- NAT Gateway(s) para saída das privadas.
- Route tables: `fcg-fenix-public-rt`, `fcg-fenix-private-rt`.
- Associar subnets às route tables.
- **Não cria** security groups.

### 3.2 `security-groups`
- Recebe `vpc_id` do módulo `vpc`.
- Cria:
  - `fcg-fenix-alb-sg` (tráfego para ALB).
  - `fcg-fenix-usersapi-sg` (tráfego ALB → EC2 usersapi + SSM).
  - `fcg-fenix-gamesapi-sg` (idem gamesapi).
  - `fcg-fenix-paymentsapi-sg` (idem paymentsapi).
- Regras: ALB recebe de VPC/API Gateway; cada SG de EC2 recebe apenas do ALB e do SSM.

### 3.3 `ecr`
- Cria um repositório ECR por serviço:
  - `fcg-fenix-usersapi-ecr`
  - `fcg-fenix-gamesapi-ecr`
  - `fcg-fenix-paymentsapi-ecr`
- Políticas de lifecycle (opcional) e tags padronizadas.

### 3.4 `iam/github-oidc`
- Configura OIDC provider (GitHub).
- Cria role `fcg-fenix-githubactions-role` com trust policy para o repositório/org definido.
- Permissões para: ECR (push/pull), SSM (SendCommand), e o necessário para Terraform nos workflows de infra (se aplicável).

### 3.5 `iam/ec2-api`
- Módulo **reutilizável por serviço** (chamado 3x: usersapi, gamesapi, paymentsapi).
- Cria role `fcg-fenix-{service}-role` e instance profile `fcg-fenix-{service}-profile`.
- Permissões: SSM Managed Instance, leitura de parâmetros em `/fcg-fenix/{service}/app`.

### 3.6 `ec2-api`
- Módulo **reutilizável por serviço** (chamado 3x).
- Cria uma EC2 privada: `fcg-fenix-{service}-ec2`.
- Usa: subnet privada, `fcg-fenix-{service}-sg`, `fcg-fenix-{service}-profile`, user data para Docker + diretório `/opt/fcg-fenix/{service}`.
- Registra a instância no target group correspondente (recebe `target_group_arn` do módulo `alb`).

### 3.7 `alb`
- Cria ALB interno `fcg-fenix-main-alb`.
- Listener `fcg-fenix-main-listener` (HTTP/HTTPS).
- Target groups: `fcg-fenix-usersapi-tg`, `fcg-fenix-gamesapi-tg`, `fcg-fenix-paymentsapi-tg`.
- Usa `fcg-fenix-alb-sg` e subnets privadas.
- **Outputs:** IDs/ARNs dos target groups para o módulo `ec2-api` registrar as instâncias.

### 3.8 `api-gateway`
- Cria API Gateway HTTP API `fcg-fenix-main-apigw`.
- Cria VPC Link `fcg-fenix-main-vpclink` (para HTTP API, o link aponta para um NLB; definir NLB ou integração conforme documentação AWS).
- Rotas (ex.: `/users`, `/games`, `/payments`) integradas ao VPC Link / back-end correspondente.
- **Nota:** API Gateway HTTP API com VPC Link exige NLB; o NLB pode ter os mesmos target groups do ALB ou um NLB dedicado — detalhar na implementação.

### 3.9 `ssm`
- Cria estrutura de parâmetros (paths) por serviço:
  - `/fcg-fenix/usersapi/app`
  - `/fcg-fenix/gamesapi/app`
  - `/fcg-fenix/paymentsapi/app`
- Pode criar parâmetros placeholder ou apenas documentar; valores sensíveis vêm de tfvars/Secrets Manager.

---

## 4. Arquivos principais de cada módulo

| Módulo             | Arquivos obrigatórios       | Descrição |
|--------------------|----------------------------|-----------|
| `vpc`              | `main.tf`, `variables.tf`, `outputs.tf` | Recursos de rede; variáveis (cidr, azs, etc.); outputs (vpc_id, subnet_ids, etc.). |
| `security-groups`  | `main.tf`, `variables.tf`, `outputs.tf` | Regras por SG; vpc_id, tags; ids dos SGs. |
| `ecr`              | `main.tf`, `variables.tf`, `outputs.tf` | Repositórios; lista de serviços; urls/arns dos repositórios. |
| `iam/github-oidc`  | `main.tf`, `variables.tf`, `outputs.tf` | OIDC provider, role, policies; org/repo GitHub; role_arn. |
| `iam/ec2-api`      | `main.tf`, `variables.tf`, `outputs.tf` | Role + instance profile por service; service name; profile_arn, role_name. |
| `ec2-api`          | `main.tf`, `variables.tf`, `outputs.tf` | EC2, user data, target group attachment; vpc, subnet, sg, profile, tg_arn, service; instance_id, private_ip. |
| `alb`              | `main.tf`, `variables.tf`, `outputs.tf` | ALB, listener, target groups; vpc_id, subnet_ids, sg_id; tg_arns por service. |
| `api-gateway`      | `main.tf`, `variables.tf`, `outputs.tf` | HTTP API, VPC Link, rotas; vpc_link_id, etc.; api_id, invoke_url. |
| `ssm`              | `main.tf`, `variables.tf`, `outputs.tf` | Parameter Store paths; lista de serviços; arns/names. |

Cada módulo deve receber `tags` base (ou `project`, `environment`, `managed_by`) para compor as tags obrigatórias (Project, ManagedBy, Environment, Application, Service).

---

## 5. Arquivos do ambiente principal (`environments/production`)

| Arquivo            | Conteúdo |
|--------------------|----------|
| `main.tf`          | `terraform` + `provider "aws"` (ou no root); chamadas `module "vpc"`, `module "security_groups"`, …, `module "ssm"` com passagem de variáveis e dependências implícitas (resource references). |
| `variables.tf`     | Declaração de variáveis usadas no ambiente: `project_name`, `environment`, `region`, `availability_zones`, `services` (lista: usersapi, gamesapi, paymentsapi), `github_org`, `github_repos`, etc. |
| `outputs.tf`       | Outputs que reexpoem valores dos módulos (vpc_id, alb_dns, api_gateway_url, ecr_urls, instance_ids por serviço, role_arn do GitHub OIDC). |
| `terraform.tfvars` | Valores das variáveis (region, azs, etc.). **Não** colocar secrets; usar variáveis de ambiente ou backend/Secrets Manager. |

O `main.tf` do ambiente **não** declara provider; isso fica em `terraform/versions.tf` ou `terraform/backend.tf` na raiz, e o ambiente é aplicado a partir da raiz com `-chdir=environments/production` ou equivalente.

---

## 6. Ordem de composição dos módulos

A ordem abaixo respeita dependências de dados (outputs → inputs). O `main.tf` do ambiente pode declarar todos os módulos; o Terraform resolve a ordem com base em referências.

1. **vpc** — Sem dependências. Fornece: `vpc_id`, `private_subnet_ids`, `public_subnet_ids`, etc.
2. **security-groups** — Depende de: `vpc`. Fornece: `alb_sg_id`, `usersapi_sg_id`, `gamesapi_sg_id`, `paymentsapi_sg_id`.
3. **ecr** — Sem dependências de outros módulos. Fornece: `repository_urls` / `repository_arns` por serviço.
4. **iam/github-oidc** — Sem dependências de rede. Fornece: `role_arn`, `role_name`.
5. **iam/ec2-api** — Chamado 3x (usersapi, gamesapi, paymentsapi). Fornece: `instance_profile_arn`, `role_name` por serviço.
6. **alb** — Depende de: `vpc`, `security-groups`. Fornece: `target_group_arns` (por serviço), `alb_arn`, `alb_dns_name`.
7. **ec2-api** — Depende de: `vpc`, `security-groups`, `iam/ec2-api`, `alb`. Chamado 3x; cada chamada recebe o `target_group_arn` do ALB para o mesmo serviço. Fornece: `instance_id`, `private_ip` por serviço.
8. **api-gateway** — Depende de: VPC Link (e NLB, se usado). Pode depender de `alb` ou de um módulo NLB. Fornece: `api_id`, `invoke_url`.
9. **ssm** — Sem dependências de outros módulos. Pode ser executado em qualquer ordem.

**Resumo da ordem sugerida no `main.tf`:**
- vpc → security_groups → alb  
- ecr, iam/github-oidc, iam/ec2-api, ssm (paralelos entre si)  
- ec2_api (após alb e iam/ec2-api)  
- api_gateway (após NLB/VPC Link — ver nota no módulo)

---

## 7. Variáveis centrais necessárias

Variáveis que o ambiente `production` deve definir e repassar aos módulos:

| Variável             | Tipo     | Descrição |
|----------------------|----------|-----------|
| `project_name`       | `string` | Ex.: `fcg-fenix`. Usado em nomes e tags. |
| `environment`        | `string` | Ex.: `production`. Só em tags; não no nome do recurso. |
| `aws_region`         | `string` | Região AWS (ex.: `us-east-1`). |
| `availability_zones` | `list(string)` | Lista de AZs (ex.: `["us-east-1a", "us-east-1b"]`). |
| `services`           | `list(string)` | Lista de serviços: `["usersapi", "gamesapi", "paymentsapi"]`. |
| `vpc_cidr`           | `string` | CIDR da VPC (ex.: `10.0.0.0/16`). |
| `tags_base`          | `object` | Tags base: `Project`, `ManagedBy`, `Environment`. |
| `github_oidc_org`    | `string` | Org (ou owner) do GitHub para OIDC. |
| `github_oidc_repos`  | `list(string)` | Repositórios permitidos para assumir a role (ex.: infra-repo, usersapi-repo). |
| `instance_type`     | `string` | Tipo da EC2 (ex.: `t3.micro`). |
| `api_gateway_routes` | `map(string)` | Mapeamento path → serviço (ex.: `{ "/users" = "usersapi" }`). |

Cada módulo pode expor variáveis específicas (ex.: `ec2-api`: `ami_id`, `key_name`; `vpc`: `enable_nat_gateway`). As acima são as **centrais** compartilhadas.

---

## 8. Outputs principais

Outputs que o ambiente `production` deve expor (em `outputs.tf`, repassando dos módulos):

| Output                  | Descrição |
|-------------------------|-----------|
| `vpc_id`                | ID da VPC `fcg-fenix-main-vpc`. |
| `private_subnet_ids`    | IDs das subnets privadas (para referência ou outros recursos). |
| `alb_dns_name`          | DNS name do ALB interno. |
| `alb_zone_id`           | Zone ID do ALB (para alias/dns interno). |
| `target_group_arns`     | Map service → ARN do target group. |
| `api_gateway_invoke_url`| URL de invocação da HTTP API. |
| `api_gateway_id`        | ID da API. |
| `ecr_repository_urls`   | Map service → URL do repositório ECR. |
| `ec2_instance_ids`      | Map service → instance_id. |
| `ec2_private_ips`       | Map service → private_ip. |
| `github_actions_role_arn` | ARN da role OIDC para GitHub Actions. |
| `ssm_parameter_prefixes`| Prefixos dos paths SSM por serviço (`/fcg-fenix/usersapi/app`, etc.). |

Esses outputs alimentam pipelines (GitHub Actions), documentação e scripts de deploy (SSM usa instance IDs).

---

*Blueprint Terraform — FCG Fenix. Alinhado a SPEC.md e PRD.md.*
