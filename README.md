# FCG Infra Orchestrator

Repositório Terraform que provisiona e atualiza a infraestrutura AWS da **FCG Cloud Platform**. Os serviços (Users API, Games API, Payments API, Notification Lambda) fazem build e enviam a imagem para o ECR; este orquestrador recebe o aviso e aplica a nova versão via Terraform.

---

## Guia operacional (comece aqui)

**Para entender como tudo funciona e o que fazer no dia a dia**, use o guia completo em linguagem prática:

→ **[docs/README-OPERATIONAL.md](docs/README-OPERATIONAL.md)**

Lá você encontra:

- Como cada serviço faz **build** e como a imagem vai para o **ECR**
- Como o orquestrador **recebe a atualização** e como o **Terraform faz o deploy**
- Como rodar **Terraform plan**, **apply** e **destroy** manualmente (pelo GitHub Actions)
- Como fazer **rollback** para uma imagem anterior
- Quais **Secrets e Variables** configurar no GitHub
- Como configurar **OIDC** entre GitHub e AWS
- **Erros comuns** e o que verificar
- **Checklists:** setup inicial, primeiro deploy, destruição do ambiente

---

## Checklists rápidos

### Setup inicial (antes do primeiro deploy)

- [ ] **Backend do Terraform:** Criar bucket S3 e tabela DynamoDB (por [bootstrap](docs/BOOTSTRAP.md) ou [manual no console AWS](docs/SETUP-MANUAL-AWS-CONSOLE.md)); preencher `environments/<env>/backend.hcl`
- [ ] OIDC: Identity provider e IAM Role para o repo do orquestrador; secret `AWS_ROLE_ARN_TERRAFORM` no GitHub (ver [docs/OIDC.md](docs/OIDC.md))
- [ ] Orquestrador: secrets `AWS_ROLE_ARN_TERRAFORM`, `TF_VAR_POSTGRES_MASTER_PASSWORD` (se RDS); variable `AWS_REGION` (opcional)
- [ ] Cada serviço: `AWS_ROLE_ARN_ECR`, `ORCHESTRATOR_REPO_TOKEN`; variables `ECR_REPOSITORY_NAME`, `ORCHESTRATOR_REPO`

### Primeiro deploy

- [ ] Rodar **Terraform Plan** (Actions) e revisar o plano
- [ ] Rodar **Terraform Apply** (Actions) e confirmar sucesso
- [ ] Anotar outputs (ex.: `ecr_repository_urls`); configurar `ECR_REPOSITORY_NAME` em cada serviço
- [ ] Fazer push em `main` de um serviço e conferir que a imagem foi ao ECR e que **Deploy from service update** rodou no orquestrador

### Destruição do ambiente

- [ ] Avisar a equipe; backup de dados se necessário; esvaziar bucket S3 do frontend se tiver objetos
- [ ] Actions → **Terraform Destroy** → Run workflow → environment → **confirm_destroy**: digitar `DESTROY` (maiúsculo)
- [ ] Conferir na AWS que os recursos foram removidos

---

## Operação manual (resumo)

| Ação | Onde | O que fazer |
|------|------|-------------|
| **Plan** (só ver mudanças) | Actions → Terraform Plan | Run workflow → escolher **environment** |
| **Apply** (aplicar infra ou atualizar imagens) | Actions → Terraform Apply | Run workflow → **environment**; opcionalmente preencher tags de imagens |
| **Destroy** (destruir ambiente) | Actions → Terraform Destroy | Run workflow → **environment** → **confirm_destroy**: `DESTROY` |

Detalhes e rollback: [docs/WORKFLOWS-OPERATION.md](docs/WORKFLOWS-OPERATION.md) e [docs/README-OPERATIONAL.md](docs/README-OPERATIONAL.md).

---

## Objetivos e documentação técnica

- **Objetivos:** provisionar infra na AWS (API Gateway, SQS, Lambda, ECR, S3, RDS, etc.) sem criar tudo no console; baixo acoplamento; destruição limpa.
- **Arquitetura e fluxo:** [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- **Setup manual no console AWS (sem Terraform/GitHub trigger):** [docs/SETUP-MANUAL-AWS-CONSOLE.md](docs/SETUP-MANUAL-AWS-CONSOLE.md)
- **Próximos passos sem Terraform (roles prontas):** [docs/PROXIMOS-PASSOS-SEM-TERRAFORM.md](docs/PROXIMOS-PASSOS-SEM-TERRAFORM.md)
- **Bootstrap (backend S3 + DynamoDB):** [docs/BOOTSTRAP.md](docs/BOOTSTRAP.md)
- **OIDC (GitHub ↔ AWS):** [docs/OIDC.md](docs/OIDC.md)
- **Decisões de arquitetura:** [docs/DECISIONS.md](docs/DECISIONS.md)
- **Deploy automático (serviço → orquestrador):** [docs/DEPLOY-FROM-SERVICE-UPDATE.md](docs/DEPLOY-FROM-SERVICE-UPDATE.md)
- **Workflows manuais (plan/apply/destroy):** [docs/WORKFLOWS-OPERATION.md](docs/WORKFLOWS-OPERATION.md)
- **Imagens e rollback:** [docs/IMAGES-AND-ROLLBACK.md](docs/IMAGES-AND-ROLLBACK.md)
- **Erros comuns:** [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)

## Pré-requisitos

- Terraform >= 1.5
- Para rodar local: AWS CLI ou variáveis de ambiente AWS; para CI: OIDC configurado (recomendado)

## Estrutura

```
Fase3-InfraOrchestrador/
├── bootstrap/                  # Terraform do backend (S3 + DynamoDB); rodar uma vez
├── environments/               # Backend e tfvars por ambiente
│   ├── prod/   (backend.hcl, terraform.tfvars)
│   ├── staging/
│   └── demo/
├── main.tf, variables.tf, outputs.tf, versions.tf, provider.tf, locals.tf
├── terraform.tfvars.example, image_tags.auto.tfvars.example
├── scripts/                    # plan.sh, apply.sh, destroy.sh, bootstrap.sh, validate.sh
├── Makefile
├── .github/workflows/
│   ├── terraform-fmt-validate.yml   # fmt + validate em PR/push
│   ├── terraform-plan.yml
│   ├── terraform-apply.yml
│   ├── terraform-destroy.yml
│   ├── deploy-from-service-update.yml
│   └── bootstrap-check.yml          # Valida backend.hcl configurado
├── docs/
│   ├── README-OPERATIONAL.md
│   ├── ARCHITECTURE.md
│   ├── BOOTSTRAP.md
│   ├── OIDC.md
│   ├── TROUBLESHOOTING.md
│   ├── WORKFLOWS-OPERATION.md
│   ├── DEPLOY-FROM-SERVICE-UPDATE.md
│   ├── IMAGES-AND-ROLLBACK.md
│   └── DECISIONS.md
└── modules/   # api-gateway, cloudwatch-logs, ecr, frontend-s3, notification-lambda, postgres, sqs, vpc
```

## Uso rápido (local)

**Primeira vez:** rodar o [bootstrap](docs/BOOTSTRAP.md) e preencher `environments/<env>/backend.hcl`.

```bash
export TF_VAR_environment=prod
export TF_VAR_postgres_master_password="sua-senha"   # se usar RDS; não commitar
terraform init -backend-config=environments/prod/backend.hcl
terraform plan -out=tfplan
terraform apply tfplan
```

Ou use os scripts: `./scripts/plan.sh prod`, `./scripts/apply.sh prod`. Destruir: `./scripts/destroy.sh prod` (pede confirmação) ou workflow **Terraform Destroy** no GitHub com **confirm_destroy**: `DESTROY`.

## Variáveis principais

| Variável | Descrição | Default |
|----------|-----------|---------|
| `environment` | prod, staging, demo | prod |
| `project_name` | Prefixo dos recursos | fcg |
| `aws_region` | Região AWS | us-east-1 |
| `postgres_master_password` | Senha RDS (use TF_VAR ou secret) | - |
| `ecr_image_tag_*` | Tag por serviço (users_api, games_api, payments_api, notification_lambda) | latest |

## Outputs úteis

- `api_gateway_endpoint`, `sqs_notification_queue_url`
- `ecr_repository_urls` (nome → URL para push)
- `service_image_tags`, `service_image_uris` (para rollback)
- `frontend_bucket_name`, `postgres_endpoint`, `notification_lambda_name`, etc.

---

Para dúvidas de operação, erros comuns e passos detalhados, use **[docs/README-OPERATIONAL.md](docs/README-OPERATIONAL.md)**.
