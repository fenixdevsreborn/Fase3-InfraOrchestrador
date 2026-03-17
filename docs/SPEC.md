# FCG Fenix — Especificação Técnica (SPEC)

Especificação técnica da infraestrutura e do fluxo de CI/CD do projeto FCG Fenix. Alinhado às convenções de nomenclatura e à arquitetura definidas no repositório de infraestrutura.

---

## 1. Visão geral

O projeto **FCG Fenix** é uma plataforma composta por três serviços principais (**usersapi**, **gamesapi**, **paymentsapi**), executando em ambiente **apenas de produção**, provisionado via **Terraform** e operado via **GitHub Actions**. A exposição pública é feita por **API Gateway HTTP API**, que se integra a um **ALB interno** por meio de **VPC Link**, distribuindo tráfego para **Target Groups** associados a **instâncias EC2 privadas** (uma por API), onde cada API roda em conjunto com um **PostgreSQL em Docker**.

Toda a infraestrutura segue o padrão de nomes `fcg-fenix-{aplicacao-ws}-{identificador}`, com **ECR dedicado por serviço**, autenticação **GitHub → AWS via OIDC**, e **deploy remoto via SSM Run Command**. Workflows de CI/CD das APIs são integrados a workflows reutilizáveis no repositório de infraestrutura.

---

## 2. Objetivos técnicos

- **Automatizar** o provisionamento da infraestrutura de produção com **Terraform**.
- **Padronizar** nomes, tags e estrutura de repositórios para facilitar governança e operação.
- **Garantir deploy contínuo e seguro** das três APIs usando **GitHub Actions**.
- **Centralizar a entrada HTTP** via API Gateway + VPC Link + ALB interno, abstraindo detalhes de rede das APIs.
- **Isolar a camada de aplicação** em **EC2 privadas**, acessíveis apenas via ALB/SSM.
- **Remover chaves estáticas** de acesso AWS, usando **OIDC** para autenticação GitHub → AWS.
- **Padronizar estratégia de deploy** com **SSM Run Command** acionado a partir de workflows reutilizáveis.
- **Garantir observabilidade mínima e auditabilidade** por meio de logs de API Gateway, ALB e EC2.

---

## 3. Escopo

- Infraestrutura **AWS** para **produção**:
  - VPC, subnets públicas/privadas, route tables, IGW, NAT.
  - Security Groups para ALB e EC2 das APIs.
  - ALB interno, listener HTTP/HTTPS, target groups por API.
  - API Gateway HTTP API + VPC Link.
  - EC2 privadas (1 por API) com suporte a Docker.
  - ECR por serviço.
  - Bucket S3 para Terraform state e, opcionalmente, DynamoDB para lock.
  - SSM Parameter Store para configurações das APIs.
- Repositório de infraestrutura:
  - Estrutura de pastas, módulos Terraform, backend remoto, providers.
  - Workflows GitHub Actions para Terraform (plan/apply) e deploy remoto via SSM.
- Padrão mínimo dos repositórios das APIs:
  - Estrutura mínima, Dockerfile, convenção de branches, integração com workflows reutilizáveis.
- Definição de:
  - Padrões de nomenclatura.
  - Padrão de tags AWS.
  - Contratos entre workflows (infra x APIs).
  - Fluxo de CI/CD ponta a ponta.
  - Requisitos de segurança, IAM, critérios de aceite e riscos.

---

## 4. Fora de escopo

- Implementação detalhada do **código de negócio** das APIs.
- Políticas detalhadas de **observabilidade** (Dashboards, Alarmes, Traces) – apenas menções de alto nível.
- Gestão de **custos** (FinOps) além de práticas básicas de tagging.
- Mecanismos avançados de **auto scaling** (ASG, ECS, etc.): neste SPEC, EC2 é 1 por API.
- Estratégias de **disaster recovery multi-região** e **multi-ambiente** (dev/homolog), focamos apenas em produção.
- Detalhes de **migrations de banco** ou estratégias complexas de versionamento de schema.

---

## 5. Arquitetura detalhada

### 5.1 Componentes principais

- **Repositórios GitHub**
  - `fcg-fenix-infra-repo` (infraestrutura).
  - `fcg-fenix-usersapi-repo`.
  - `fcg-fenix-gamesapi-repo`.
  - `fcg-fenix-paymentsapi-repo`.

- **Rede**
  - VPC única: `fcg-fenix-main-vpc`.
  - Subnets:
    - Públicas: `fcg-fenix-public-a-subnet`, `fcg-fenix-public-b-subnet`.
    - Privadas: `fcg-fenix-private-a-subnet`, `fcg-fenix-private-b-subnet`.
  - Route tables:
    - `fcg-fenix-public-rt` (associada às subnets públicas).
    - `fcg-fenix-private-rt` (associada às subnets privadas).
  - Internet Gateway: `fcg-fenix-main-igw`.
  - NAT Gateway(s) para saída das instâncias privadas.

- **Segurança de rede**
  - Security Group ALB: `fcg-fenix-alb-sg`.
  - Security Group EC2 Users: `fcg-fenix-usersapi-sg`.
  - Security Group EC2 Games: `fcg-fenix-gamesapi-sg`.
  - Security Group EC2 Payments: `fcg-fenix-paymentsapi-sg`.

- **Compute**
  - EC2 privadas, 1 por API:
    - `fcg-fenix-usersapi-ec2`.
    - `fcg-fenix-gamesapi-ec2`.
    - `fcg-fenix-paymentsapi-ec2`.
  - Em cada EC2:
    - Container da API.
    - Container do PostgreSQL.
    - Diretório padrão: `/opt/fcg-fenix/{servico}`.
    - Orquestração local (Docker Compose ou script) gerenciada via SSM Run Command.

- **Balanceamento e exposição**
  - ALB interno: `fcg-fenix-main-alb`.
  - Listener: `fcg-fenix-main-listener`.
  - Target groups:
    - `fcg-fenix-usersapi-tg`.
    - `fcg-fenix-gamesapi-tg`.
    - `fcg-fenix-paymentsapi-tg`.
  - API Gateway:
    - HTTP API: `fcg-fenix-main-apigw`.
    - VPC Link: `fcg-fenix-main-vpclink` apontando para o ALB.
  - Roteamento:
    - Rotas no API Gateway por caminho ou domínio (ex: `/users`, `/games`, `/payments`) encaminhando para o VPC Link + Target Group correspondente.

- **Registry**
  - Repositórios ECR:
    - `fcg-fenix-usersapi-ecr`.
    - `fcg-fenix-gamesapi-ecr`.
    - `fcg-fenix-paymentsapi-ecr`.

- **Configuração e deploy**
  - SSM Parameter Store:
    - `/fcg-fenix/usersapi/app`.
    - `/fcg-fenix/gamesapi/app`.
    - `/fcg-fenix/paymentsapi/app`.
  - Deploy:
    - Imagem construída em cada repositório de API → push para ECR.
    - Workflow da API chama workflow reutilizável no repo de infra → que usa SSM Run Command para atualizar containers na EC2 pertinente.

- **Terraform**
  - State remoto em S3: `fcg-fenix-tfstate`.
  - Lock opcional via DynamoDB: nome alinhado ao padrão (ex: `fcg-fenix-tfstate-lock`).

### 5.2 Fluxos principais

- **Provisionamento (infra-repo)**
  - Developer executa Terraform via pipeline GitHub Actions.
  - Terraform aplica mudanças na VPC, EC2, ALB, API Gateway, IAM, ECR, SSM, etc.

- **Deploy de API**
  - Push em branch principal da API → build de imagem → push para ECR → chamada de reusable workflow → SSM Run Command atualiza containers na EC2.

---

## 6. Padrão de nomenclatura

- **Regra geral:**  
  `fcg-fenix-{aplicacao-ws}-{identificador}`

- **Regras:**
  - Tudo em minúsculo.
  - Sem acentos.
  - Sem espaços.
  - Separar por hífens.
  - `aplicacao-ws` = `usersapi`, `gamesapi`, `paymentsapi`, ou `main` para recursos compartilhados.
  - `identificador` descreve o tipo do recurso (ex: `ecr`, `ec2`, `sg`, `tg`, `apigw`, `vpclink`, `vpc`, `subnet`, `rt`, `igw`, `role`, `profile`, `repo`).

- **Exemplos:**
  - Repositórios Git: `fcg-fenix-usersapi-repo`, `fcg-fenix-infra-repo`.
  - ECR: `fcg-fenix-usersapi-ecr`.
  - EC2: `fcg-fenix-usersapi-ec2`.
  - IAM Role EC2: `fcg-fenix-usersapi-role`.
  - IAM Role GitHub Actions: `fcg-fenix-githubactions-role`.
  - Instance Profile: `fcg-fenix-usersapi-profile`.
  - SG: `fcg-fenix-usersapi-sg`, `fcg-fenix-alb-sg`.
  - VPC: `fcg-fenix-main-vpc`.
  - API Gateway: `fcg-fenix-main-apigw`.
  - VPC Link: `fcg-fenix-main-vpclink`.

- **Restrições:**
  - **Não usar** `prod` em nomes de recursos.
  - Para recursos compartilhados, usar `main` como aplicação (`fcg-fenix-main-*`).

---

## 7. Padrão de tags

- **Tags obrigatórias em todos os recursos gerenciados por Terraform:**

| Tag         | Valor                     | Observação                                     |
|------------|---------------------------|------------------------------------------------|
| Project    | `fcg-fenix`               | Identifica o projeto                           |
| ManagedBy  | `terraform`               | Indica gestão via IaC                          |
| Environment| `production`              | Ambiente (não aparece no nome do recurso)      |
| Application| `usersapi`/`gamesapi`/`paymentsapi` ou `shared` | Serviço ou recurso compartilhado |
| Service    | Mesmo valor de `Application` | Facilita queries e filtragem               |

- **Regras:**
  - Para recursos compartilhados (ex: VPC, ALB, API Gateway), `Application` / `Service` podem ser `shared` ou outro valor acordado, mantendo consistência.
  - A tag `Environment` sempre `production`, independente do nome do recurso.

---

## 8. Estrutura do repositório de infraestrutura

```
fcg-fenix-infra-repo/
├── .github/
│   └── workflows/
│       ├── terraform-plan.yml
│       ├── terraform-apply.yml
│       ├── reusable-deploy-api.yml        # Deploy via SSM Run Command
│       └── reusable-validate-plan.yml     # (opcional) validação/quality gate
├── terraform/
│   ├── environments/
│   │   └── production/
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       ├── outputs.tf
│   │       └── terraform.tfvars
│   ├── modules/
│   │   ├── vpc/
│   │   ├── ec2-api/
│   │   ├── ecr/
│   │   ├── alb/
│   │   ├── api-gateway/
│   │   ├── iam/
│   │   │   ├── github-oidc/
│   │   │   └── ec2-api/
│   │   └── ssm/
│   ├── backend.tf
│   └── versions.tf
├── docs/
│   ├── 01-arquitetura-e-convencoes.md
│   └── SPEC.md
├── scripts/
│   └── bootstrap-ec2.sh
├── CONVENTIONS.md
├── .gitignore
└── README.md
```

---

## 9. Estrutura mínima esperada dos repositórios das APIs

Exemplo para `fcg-fenix-usersapi-repo` (análogo para `gamesapi` e `paymentsapi`):

```
fcg-fenix-usersapi-repo/
├── src/
│   └── ...
├── docker/
│   ├── Dockerfile
│   └── docker-compose.local.yml
├── .github/
│   └── workflows/
│       ├── ci.yml
│       └── cd.yml
├── README.md
└── .gitignore
```

- **Requisitos mínimos:**
  - `Dockerfile` capaz de produzir imagem pronta para produção.
  - Workflow `ci.yml`: build, testes, build da imagem Docker.
  - Workflow `cd.yml`: push da imagem para o ECR correto e chamada do reusable workflow do repo de infra, informando `service`, `image_tag`, `environment`.

---

## 10. Contratos entre workflows

### 10.1 Infra (reusable workflows) ↔ APIs

- **Reusable workflow de deploy** (`reusable-deploy-api.yml`) deve expor:
  - `service` (obrigatório): `usersapi` | `gamesapi` | `paymentsapi`.
  - `image_tag` (obrigatório): tag da imagem Docker.
  - `environment` (obrigatório): `production`.
  - `caller_repo` (opcional): nome do repo chamador.

- **Responsabilidades do reusable workflow:**
  - Assumir role AWS via OIDC (`fcg-fenix-githubactions-role`).
  - Resolver o ECR correto com base em `service`.
  - Executar SSM Run Command na instância EC2 correta (pull da imagem, restart do container).

- **Contrato com workflows das APIs (`cd.yml`):**
  - As APIs garantem que a imagem foi buildada e enviada ao ECR antes de chamar o reusable.
  - Informam corretamente `service` e `image_tag`.

### 10.2 Terraform workflows

- **terraform-plan.yml**: input opcional do ambiente; saída: artefato do plano.
- **terraform-apply.yml**: requer plano aprovado ou gatilho manual; executa `apply`.

---

## 11. Fluxo de CI/CD

### 11.1 Infraestrutura

1. Alteração em código Terraform em `fcg-fenix-infra-repo`.
2. Pull request → `terraform-plan.yml`: `terraform fmt` / `validate`, `terraform plan`.
3. Revisão de PR.
4. Merge → `terraform-apply.yml`: `plan` + `apply` em produção.

### 11.2 APIs

1. Push/PR em `fcg-fenix-{servico}-repo`.
2. `ci.yml`: build, testes, lint.
3. Merge na branch principal → `cd.yml`: build da imagem, push para ECR, chamada do reusable workflow com `service`, `image_tag`, `environment=production`.
4. Reusable workflow: assume role via OIDC, executa SSM Run Command na EC2 correspondente, atualiza container.

---

## 12. Requisitos de segurança

- **Identidade:** Proibir chaves estáticas; usar **OIDC GitHub → AWS**.
- **Rede:** EC2s em subnets privadas; ALB interno; API Gateway como entrada pública; Security Groups restritivos (ALB e EC2).
- **Dados:** Credenciais e secrets em SSM (ou Secrets Manager), não em código.
- **IaC:** Terraform com backend remoto e lock; revisão de PR obrigatória.
- **Logs:** Ativar logs de SSM, API Gateway e ALB.

---

## 13. Requisitos de IAM

- **Role GitHub Actions** (`fcg-fenix-githubactions-role`): trust policy para GitHub OIDC; permissões para ECR, SSM (SendCommand), e recursos de Terraform nos workflows de infra.
- **Roles EC2:** `fcg-fenix-usersapi-role`, `fcg-fenix-gamesapi-role`, `fcg-fenix-paymentsapi-role` — SSM Agent e leitura de parâmetros em `/fcg-fenix/{servico}/app`.
- **Instance profiles:** anexados às respectivas EC2.
- **Princípio:** least privilege; separação entre roles de deploy (GitHub), execução (EC2) e infra (Terraform).

---

## 14. Critérios de aceite

- **Infraestrutura:** VPC, subnets, NAT, SGs, ALB, API Gateway, VPC Link, EC2, ECR criados conforme padrão de nomes e tags; Terraform com state remoto e lock; módulos separados por domínio.
- **CI/CD:** Workflows de infra e reusable workflow de deploy funcionando; repos das APIs com `ci.yml` e `cd.yml` funcionais.
- **Segurança:** OIDC em uso; EC2 não expostas à internet; tags obrigatórias em todos os recursos.
- **Funcional:** Chamadas ao API Gateway roteadas corretamente para cada API; deploy de nova versão atualiza containers via SSM e serviço responde saudável.

---

## 15. Riscos técnicos e mitigação

| Risco | Mitigação |
|-------|-----------|
| Falha em SSM Run Command durante deploy | Scripts idempotentes; logs de SSM; verificação de health pós-deploy. |
| Má configuração do OIDC | Testes em sandbox; trust policy restrita por org/repo/branch. |
| Single EC2 por API (SPOF) | Documentar limitação; planejar evolução para ASG; backups e scripts de re-provisioning. |
| Falta de observabilidade | Habilitar logs mínimos; planejar SPEC de logging/monitoramento. |
| Divergência infra x APIs | Revisão conjunta; rotas estáveis e versionamento via path. |

---

*Documento: SPEC.md — FCG Fenix. Alinhado a 01-arquitetura-e-convencoes.md e PRD.md.*
