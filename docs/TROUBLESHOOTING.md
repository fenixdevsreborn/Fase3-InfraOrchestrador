# Troubleshooting — FCG Infra Orchestrator

Erros comuns e o que verificar.

---

## Terraform e backend

| Situação | Possível causa | O que fazer |
|----------|----------------|-------------|
| **"failed to get existing workspace" ou erro ao iniciar backend** | Backend S3 não configurado ou inacessível. | Garantir que `environments/<env>/backend.hcl` existe e está preenchido (sem placeholder `REPLACE-WITH-ACCOUNT-ID`). Rodar bootstrap se ainda não rodou. Usar `terraform init -backend-config=environments/<env>/backend.hcl`. Ver [BOOTSTRAP.md](BOOTSTRAP.md). |
| **"Error acquiring the state lock"** | Outra execução (ou alguém local) está com o state travado. | Esperar a outra execução terminar. Se for seguro, remover o item de lock na tabela DynamoDB (cuidado em ambiente compartilhado). |
| **Plan/apply falha com "backend config"** | Init sem `-backend-config` para o ambiente. | Nos workflows, o init já usa `-backend-config=environments/${{ inputs.environment }}/backend.hcl`. Local: `terraform init -backend-config=environments/prod/backend.hcl`. |

---

## AWS e OIDC

| Situação | Possível causa | O que fazer |
|----------|----------------|-------------|
| **"Not authorized to perform sts:AssumeRoleWithWebIdentity"** | Trust policy não permite o repo ou audience errado. | Ajustar a condition `token.actions.githubusercontent.com:sub` para `repo:ORG/REPO:*` e o audience para `sts.amazonaws.com`. Ver [OIDC.md](OIDC.md). |
| **Push para ECR falha com "no basic auth credentials"** | Login no ECR falhou (role sem permissão ou região errada). | Verificar `AWS_ROLE_ARN_ECR`, região e permissões da role (ecr:GetAuthorizationToken e ecr:PutImage, etc.). |
| **"Repository not found" ou 404 no ECR** | Nome do repositório diferente do que existe na AWS. | Conferir variable `ECR_REPOSITORY_NAME` no repo do serviço; deve ser igual ao nome criado pelo Terraform (ex.: output `ecr_repository_urls`). |

---

## GitHub Actions e deploy

| Situação | Possível causa | O que fazer |
|----------|----------------|-------------|
| **Orquestrador não dispara / repository_dispatch não roda** | Token ou repo errado; workflow inexistente. | No **serviço:** conferir secret `ORCHESTRATOR_REPO_TOKEN` (PAT com permissão repo) e variable `ORCHESTRATOR_REPO` (owner/repo). No **orquestrador:** workflow deve ter `on.repository_dispatch.types: [deploy-request]`. |
| **Destroy não executa; "Destroy não confirmado"** | Campo de confirmação diferente de `DESTROY`. | Digitar exatamente `DESTROY` em maiúsculo no campo **confirm_destroy**. |
| **Workflow "Bootstrap / backend check" falha** | backend.hcl com placeholder. | Preencher `bucket` e `dynamodb_table` em `environments/<env>/backend.hcl` com os outputs do bootstrap. |

---

## RDS e variáveis sensíveis

| Situação | Possível causa | O que fazer |
|----------|----------------|-------------|
| **Terraform apply falha com "password" ou "postgres"** | Senha do RDS não passada ou secret errado. | Definir secret `TF_VAR_POSTGRES_MASTER_PASSWORD` no orquestrador. Não commitar senha em tfvars. |
| **Plan falha com erro de RDS** | Plan sem senha quando RDS existe. | Os workflows de plan e deploy-from-service passam `TF_VAR_postgres_master_password`; garantir que o secret está configurado. |

---

## Outros

| Situação | Possível causa | O que fazer |
|----------|----------------|-------------|
| **terraform fmt -check falha no CI** | Arquivos .tf com formatação diferente. | Rodar `terraform fmt -recursive` localmente e commitar. |
| **Bucket S3 não pode ser removido no destroy** | Bucket não vazio. | Esvaziar o bucket antes: `aws s3 rm s3://NOME_DO_BUCKET --recursive`. Ou configurar `force_destroy = true` no módulo do bucket (se aplicável). |

Para checklists de setup e primeiro deploy: [README-OPERATIONAL.md](README-OPERATIONAL.md).
