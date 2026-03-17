# FCG Fenix — Arquitetura e Convenções (Consolidado)

Documento gerado a partir do **Prompt 1**: consolidação de arquitetura AWS e convenções do projeto. Sem código; apenas decisões e estrutura.

---

## 1. Regras base de nomenclatura

| Regra | Descrição |
|-------|-----------|
| **Padrão** | `fcg-fenix-{aplicacao-ws}-{identificador}` |
| **Escrita** | Tudo em minúsculo, sem acento, sem espaço, separar por hífen |
| **aplicacao-ws** | Nome curto do sistema/serviço (ex: `usersapi`, `gamesapi`, `paymentsapi`) |
| **identificador** | Tipo do recurso ou finalidade (ex: `ec2`, `ecr`, `sg`, `tg`) |
| **Recursos compartilhados** | Usar `main` no lugar da aplicação quando fizer sentido (ex: `fcg-fenix-main-vpc`) |
| **Ambiente** | Não usar "prod" nos nomes dos recursos (só na tag `Environment`) |

**Fórmula recomendada:** `fcg-fenix-{servico}-{recurso}`

---

## 2. Convenções de nomes por tipo de recurso

### Repositórios (GitHub)

| Recurso | Nome |
|---------|------|
| Infraestrutura | `fcg-fenix-infra-repo` |
| Users API | `fcg-fenix-usersapi-repo` |
| Games API | `fcg-fenix-gamesapi-repo` |
| Payments API | `fcg-fenix-paymentsapi-repo` |

### ECR

| Recurso | Nome |
|---------|------|
| Users API | `fcg-fenix-usersapi-ecr` |
| Games API | `fcg-fenix-gamesapi-ecr` |
| Payments API | `fcg-fenix-paymentsapi-ecr` |

### Compute (EC2)

| Recurso | Nome |
|---------|------|
| Users API | `fcg-fenix-usersapi-ec2` |
| Games API | `fcg-fenix-gamesapi-ec2` |
| Payments API | `fcg-fenix-paymentsapi-ec2` |

### IAM

| Recurso | Nome |
|---------|------|
| Users API | `fcg-fenix-usersapi-role` |
| Games API | `fcg-fenix-gamesapi-role` |
| Payments API | `fcg-fenix-paymentsapi-role` |
| GitHub Actions | `fcg-fenix-githubactions-role` |
| Instance Profile (Users) | `fcg-fenix-usersapi-profile` |
| Instance Profile (Games) | `fcg-fenix-gamesapi-profile` |
| Instance Profile (Payments) | `fcg-fenix-paymentsapi-profile` |

### Rede — Security Groups

| Recurso | Nome |
|---------|------|
| ALB | `fcg-fenix-alb-sg` |
| Users API | `fcg-fenix-usersapi-sg` |
| Games API | `fcg-fenix-gamesapi-sg` |
| Payments API | `fcg-fenix-paymentsapi-sg` |

### Load Balancer (ALB)

| Recurso | Nome |
|---------|------|
| ALB | `fcg-fenix-main-alb` |
| Listener | `fcg-fenix-main-listener` |
| Target Group Users | `fcg-fenix-usersapi-tg` |
| Target Group Games | `fcg-fenix-gamesapi-tg` |
| Target Group Payments | `fcg-fenix-paymentsapi-tg` |

### API Gateway e VPC Link

| Recurso | Nome |
|---------|------|
| API Gateway HTTP API | `fcg-fenix-main-apigw` |
| VPC Link | `fcg-fenix-main-vpclink` |

### VPC e sub-redes

| Recurso | Nome |
|---------|------|
| VPC | `fcg-fenix-main-vpc` |
| Subnet pública AZ A | `fcg-fenix-public-a-subnet` |
| Subnet pública AZ B | `fcg-fenix-public-b-subnet` |
| Subnet privada AZ A | `fcg-fenix-private-a-subnet` |
| Subnet privada AZ B | `fcg-fenix-private-b-subnet` |
| Route table pública | `fcg-fenix-public-rt` |
| Route table privada | `fcg-fenix-private-rt` |
| Internet Gateway | `fcg-fenix-main-igw` |

### Terraform (state e lock)

| Recurso | Nome |
|---------|------|
| Bucket de state | `fcg-fenix-tfstate` |
| Lock (se nome auxiliar) | `fcg-fenix-tfstate-lock` |

### SSM e diretórios nas EC2

| Recurso | Path / Caminho |
|---------|----------------|
| SSM Users API | `/fcg-fenix/usersapi/app` |
| SSM Games API | `/fcg-fenix/gamesapi/app` |
| SSM Payments API | `/fcg-fenix/paymentsapi/app` |
| Diretório app Users | `/opt/fcg-fenix/usersapi` |
| Diretório app Games | `/opt/fcg-fenix/gamesapi` |
| Diretório app Payments | `/opt/fcg-fenix/paymentsapi` |

---

## 3. Tags AWS obrigatórias

| Tag | Valor | Uso |
|-----|--------|-----|
| **Project** | `fcg-fenix` | Agrupamento do projeto |
| **ManagedBy** | `terraform` | Indica IaC |
| **Environment** | `production` | Governança (não usar "prod" no nome do recurso) |
| **Application** | `usersapi` / `gamesapi` / `paymentsapi` | Serviço |
| **Service** | `usersapi` / `gamesapi` / `paymentsapi` | Mesmo valor que Application |

**Regra:** Nome = identificação do recurso. Tag = governança. Manter separados.

---

## 4. Recursos AWS necessários (lista consolidada)

### Identidade e acesso

- **IAM**
  - Role para GitHub Actions (OIDC): `fcg-fenix-githubactions-role`
  - Role por API (EC2): `fcg-fenix-usersapi-role`, `fcg-fenix-gamesapi-role`, `fcg-fenix-paymentsapi-role`
  - Instance profile por API: `fcg-fenix-usersapi-profile`, `fcg-fenix-gamesapi-profile`, `fcg-fenix-paymentsapi-profile`

### Rede

- **VPC**
  - VPC: `fcg-fenix-main-vpc`
  - Subnets públicas (2 AZs): `fcg-fenix-public-a-subnet`, `fcg-fenix-public-b-subnet`
  - Subnets privadas (2 AZs): `fcg-fenix-private-a-subnet`, `fcg-fenix-private-b-subnet`
  - Route tables: `fcg-fenix-public-rt`, `fcg-fenix-private-rt`
  - Internet Gateway: `fcg-fenix-main-igw`
  - NAT Gateway(s) conforme design (nome alinhado ao padrão)

- **Security Groups**
  - `fcg-fenix-alb-sg`, `fcg-fenix-usersapi-sg`, `fcg-fenix-gamesapi-sg`, `fcg-fenix-paymentsapi-sg`

### Compute

- **EC2**
  - Uma instância privada por API: `fcg-fenix-usersapi-ec2`, `fcg-fenix-gamesapi-ec2`, `fcg-fenix-paymentsapi-ec2`
  - Em cada EC2: API + PostgreSQL em Docker (compose local ou container sidecar)

### Load balancing e API Gateway

- **ALB (interno)**
  - ALB: `fcg-fenix-main-alb`
  - Listener: `fcg-fenix-main-listener`
  - Target groups: `fcg-fenix-usersapi-tg`, `fcg-fenix-gamesapi-tg`, `fcg-fenix-paymentsapi-tg`

- **API Gateway**
  - HTTP API: `fcg-fenix-main-apigw`
  - VPC Link: `fcg-fenix-main-vpclink` (apontando para o ALB)

### Container registry

- **ECR**
  - Um repositório por API: `fcg-fenix-usersapi-ecr`, `fcg-fenix-gamesapi-ecr`, `fcg-fenix-paymentsapi-ecr`

### Deploy e parâmetros

- **SSM**
  - Parâmetros em `/fcg-fenix/{usersapi|gamesapi|paymentsapi}/app` para configuração das apps
  - Uso de SSM Run Command para deploy remoto nas EC2

### Terraform

- **S3**
  - Bucket de state: `fcg-fenix-tfstate`
  - Opcional: DynamoDB para lock (`fcg-fenix-tfstate-lock` ou nome derivado do bucket)

---

## 5. Arquitetura desejada (resumo)

| Aspecto | Decisão |
|---------|---------|
| Ambiente | Somente produção; sem "prod" no nome dos recursos |
| Repositórios | 1 repo de infraestrutura + 1 repo por API (usersapi, gamesapi, paymentsapi) |
| IaC | Terraform |
| CI/CD | GitHub Actions |
| Entrada pública | API Gateway HTTP API |
| Integração API Gateway ↔ ALB | VPC Link |
| ALB | Interno (privado) |
| Back-end | 1 EC2 privada por API |
| Banco por API | 1 PostgreSQL em Docker na mesma EC2 da API |
| Registry | 1 ECR por API |
| Deploy | Remoto via SSM Run Command |
| Autenticação GitHub → AWS | OIDC (sem chaves estáticas) |
| Workflows | Reusable workflows no repositório de infraestrutura |

---

## 6. Estrutura proposta do repositório de infraestrutura

```
fcg-fenix-infra-repo/
├── .github/
│   └── workflows/
│       ├── terraform-plan.yml
│       ├── terraform-apply.yml
│       ├── reusable-deploy-api.yml    # Reusable: deploy por SSM
│       └── ...
├── terraform/
│   ├── environments/
│   │   └── production/                # único ambiente; sem "prod" nos recursos
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       ├── outputs.tf
│   │       └── terraform.tfvars
│   ├── modules/
│   │   ├── vpc/
│   │   ├── ec2-api/                   # módulo reutilizável por API
│   │   ├── ecr/
│   │   ├── alb/
│   │   ├── api-gateway/
│   │   ├── iam/
│   │   │   ├── github-oidc/
│   │   │   └── ec2-api/
│   │   └── ssm/
│   ├── backend.tf                    # S3 + optional DynamoDB lock
│   └── versions.tf                   # provider requirements
├── docs/
│   ├── 01-arquitetura-e-convencoes.md
│   └── ...
├── scripts/                          # scripts auxiliares (ex: bootstrap SSM, healthcheck)
│   └── ...
├── .gitignore
├── README.md
└── CONVENTIONS.md                    # resumo das convenções de nome e tags
```

**Observações:**

- **terraform/environments/production**: contém a orquestração (chamada aos módulos) e valores por ambiente. Como é só produção, pode existir apenas esse ambiente.
- **terraform/modules**: cada módulo encapsula um bloco lógico (vpc, ec2 por API, ecr, alb, api-gateway, iam, ssm) e usa variáveis para nomes e tags, garantindo o padrão `fcg-fenix-{servico}-{recurso}`.
- **.github/workflows**: workflows que chamam Terraform (plan/apply) e reusable workflow para deploy das APIs via SSM, acionado pelos repositórios de cada API.

---

## 7. Próximos passos (sequência de prompts)

1. **Prompt 1 (este documento)** — Consolidar arquitetura e convenções ✅  
2. **Prompt 2** — Implementar módulos Terraform (ex.: VPC, subnets, security groups).  
3. **Prompt 3** — Implementar EC2, ALB, target groups, API Gateway, VPC Link.  
4. **Prompt 4** — Implementar ECR, IAM (GitHub OIDC + roles EC2), SSM e backend Terraform.  
5. **Prompt 5** — GitHub Actions: reusable workflows e integração com repos das APIs.  

---

*Documento gerado conforme Prompt 1 — sem código; apenas convenções e estrutura.*
