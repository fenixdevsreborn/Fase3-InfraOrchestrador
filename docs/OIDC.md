# Configuração OIDC — GitHub Actions e AWS

OIDC permite que o GitHub Actions **assuma uma IAM Role** na AWS sem usar access key ou secret fixos. Este documento descreve como configurar e quais secrets/variables usar.

---

## Por que OIDC

- Não é necessário armazenar `AWS_ACCESS_KEY_ID` e `AWS_SECRET_ACCESS_KEY` no GitHub.
- Credenciais temporárias geradas por demanda; a role define as permissões.
- Recomendado pela AWS e pelo GitHub para CI/CD.

---

## 1. Criar o Identity Provider OIDC na AWS (uma vez por conta)

1. No console AWS: **IAM** → **Identity providers** → **Add provider**.
2. **Provider type:** OpenID Connect.
3. **Provider URL:** `https://token.actions.githubusercontent.com`
4. **Audience:** `sts.amazonaws.com`
5. Salvar.

---

## 2. Criar a IAM Role para o orquestrador (Terraform)

1. **IAM** → **Roles** → **Create role**.
2. **Trusted entity type:** Custom trust policy.
3. **Trust policy** (ajuste `ACCOUNT_ID`, `ORG` e `REPO`):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:ORG/REPO:*"
        }
      }
    }
  ]
}
```

- Para o **orquestrador:** use o repositório do orquestrador (ex.: `minha-org/Fase3-InfraOrchestrador`) em `repo:ORG/REPO:*`.
- A role precisa de permissões para: S3 (bucket do state), DynamoDB (tabela de lock), e todos os recursos que o Terraform cria (EC2/VPC, Lambda, ECR, API Gateway, RDS, S3 do frontend, CloudWatch Logs, etc.). Use uma policy customizada ou políticas gerenciadas conforme necessário.

4. Copie o **ARN da role** (ex.: `arn:aws:iam::123456789012:role/github-fcg-terraform`).

---

## 3. Criar a IAM Role para cada serviço (push no ECR)

Para cada repositório de aplicação (Users API, Games API, etc.) que faz push de imagem no ECR:

1. Crie uma role com a mesma trust policy acima, trocando `repo:ORG/REPO:*` pelo repositório do **serviço** (ex.: `repo:ORG/Fase3-UsersAPI:*`).
2. Anexe permissões para: `ecr:GetAuthorizationToken` e, no recurso do ECR, `ecr:BatchCheckLayerAvailability`, `ecr:GetDownloadUrlForLayer`, `ecr:PutImage`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload`, etc. (policy padrão para push ECR).

---

## 4. Configurar no GitHub

### Orquestrador (Fase3-InfraOrchestrador)

| Nome | Tipo | Obrigatório | Uso |
|------|------|-------------|-----|
| `AWS_ROLE_ARN_TERRAFORM` | Secret | Sim | ARN da IAM Role que o GitHub assume para rodar Terraform. |
| `TF_VAR_POSTGRES_MASTER_PASSWORD` | Secret | Se usar RDS | Senha do PostgreSQL; passada como `TF_VAR_postgres_master_password`. |
| `AWS_REGION` | Variable | Não (default us-east-1) | Região AWS. |

### Cada repositório de serviço

| Nome | Tipo | Obrigatório | Uso |
|------|------|-------------|-----|
| `AWS_ROLE_ARN_ECR` | Secret | Sim | ARN da IAM Role para push no ECR. |
| `ORCHESTRATOR_REPO_TOKEN` | Secret | Sim | PAT com permissão de enviar `repository_dispatch` no repo do orquestrador. Use escopo mínimo (apenas o repo do orquestrador). |
| `ECR_REPOSITORY_NAME` | Variable | Sim | Nome do repositório no ECR (ex.: `fcg-prod-users-api`). |
| `ORCHESTRATOR_REPO` | Variable | Sim | Repo do orquestrador: `owner/repo` (ex.: `minha-org/Fase3-InfraOrchestrador`). |
| `AWS_REGION` | Variable | Não | Região do ECR. |

Os workflows usam `aws-actions/configure-aws-credentials@v4` com `role-to-assume`; não é necessário configurar `AWS_ACCESS_KEY_ID` nem `AWS_SECRET_ACCESS_KEY` quando OIDC está ativo.

---

## Erro comum: "Not authorized to perform sts:AssumeRoleWithWebIdentity"

- Verifique se o **audience** no IdP é `sts.amazonaws.com`.
- Verifique se a condition `token.actions.githubusercontent.com:sub` corresponde ao repositório correto (`repo:ORG/REPO:*`).
- Confirme que o secret `AWS_ROLE_ARN_TERRAFORM` (ou `AWS_ROLE_ARN_ECR`) contém o ARN completo da role, sem espaços.

Ver também: [README-OPERATIONAL.md](README-OPERATIONAL.md), [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
