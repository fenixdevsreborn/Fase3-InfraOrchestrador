# Arquitetura — FCG Infra Orchestrator

Visão do fluxo de deploy e da relação entre repositórios, ECR, orquestrador e AWS.

---

## Fluxo: Serviço → ECR → Orquestrador → Terraform → AWS

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│  Repositórios de serviço (Users API, Games API, Payments API, Notification Lambda)│
│  • CI: build + testes em todo push/PR                                             │
│  • Publish image: em push em main → build Docker → push ECR → repository_dispatch  │
└─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  ECR (Elastic Container Registry)                                                │
│  • Repositórios criados pelo Terraform: fcg-<env>-users-api, games-api, etc.   │
│  • Imagens com tag = SHA do commit (e opcionalmente latest em prod)              │
└─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        │ evento deploy-request (service_name, image_tag, environment)
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  Fase3-InfraOrchestrador (este repositório)                                       │
│  • Workflow "Deploy from service update": recebe evento → atualiza image_tags     │
│    .auto.tfvars → terraform init (backend por ambiente) → plan → apply            │
│  • Terraform atualiza apenas o recurso cuja imagem mudou (ex.: Lambda)            │
└─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  AWS                                                                              │
│  • State do Terraform: S3 + DynamoDB (lock), key por ambiente (prod/staging/demo) │
│  • Recursos: VPC, ECR, SQS, Lambda (notificação, container), API Gateway,        │
│    S3 (frontend), RDS PostgreSQL, CloudWatch Logs                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Componentes provisionados pelo Terraform

| Componente | Uso |
|------------|-----|
| **VPC** | Rede para RDS e, se necessário, Lambdas em VPC (opcional; pode usar VPC existente). |
| **ECR** | Um repositório por serviço: notification-lambda, users-api, games-api, payments-api. Apenas a **Notification Lambda** consome imagem hoje; as demais são preparação para deploy futuro (ver [DECISIONS.md](DECISIONS.md)). |
| **SQS** | Fila de notificação + DLQ; a Lambda de notificação consome mensagens. |
| **Lambda (notificação)** | Função container (imagem no ECR), trigger SQS, IAM (SQS, CloudWatch, SES). |
| **API Gateway HTTP API** | Rota e integração placeholder; JWT authorizer opcional. Rotas reais quando houver backends (Lambda/HTTP). |
| **S3** | Bucket para frontend estático (website, CORS, versionamento). |
| **RDS PostgreSQL** | Instância única (single-AZ), db.t3.micro, opcional. |
| **CloudWatch Logs** | Log groups para API Gateway e Lambda. |

---

## State e ambientes

- **Bootstrap** (`bootstrap/`): Cria bucket S3 e tabela DynamoDB para o state; state do bootstrap é local.
- **Ambientes** (`environments/prod`, `staging`, `demo`): Cada um tem `backend.hcl` com key distinta (`fcg-infra/<env>/terraform.tfstate`). Os workflows usam `terraform init -backend-config=environments/<env>/backend.hcl` para isolar state por ambiente.
- **Raiz**: Contém a stack (main.tf, módulos); plan/apply/destroy rodam na raiz com backend configurado via `-backend-config`.

---

## Referências

- [DECISIONS.md](DECISIONS.md) — Decisões de arquitetura e custo.
- [README-OPERATIONAL.md](README-OPERATIONAL.md) — Guia operacional e checklists.
- [BOOTSTRAP.md](BOOTSTRAP.md) — Criação do backend do Terraform.
