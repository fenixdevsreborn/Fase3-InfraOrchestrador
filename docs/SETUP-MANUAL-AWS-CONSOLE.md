# Passo a passo — Configuração manual no console AWS

Este guia descreve como criar **manualmente no console da AWS** tudo o que o projeto precisa para rodar na cloud, quando o **gatilho (trigger) do repositório InfraOrchestrador está desativado**. Depois de seguir estes passos, você poderá rodar o Terraform (local ou via GitHub Actions) e os serviços poderão publicar imagens no ECR e disparar o orquestrador.

---

## Visão geral do que será criado

| # | Onde | O que criar |
|---|------|-------------|
| 1 | S3 | Bucket para state do Terraform (versionamento + criptografia) |
| 2 | DynamoDB | Tabela para lock do state |
| 3 | IAM | Identity provider OIDC (GitHub) |
| 4 | IAM | Role para o orquestrador (Terraform) |
| 5 | IAM | Role para cada serviço (push ECR) — uma por repo |
| 6 | Local | Preencher `environments/<env>/backend.hcl` |
| 7 | GitHub | Secrets e variables (orquestrador + cada serviço) |

A infraestrutura da aplicação (VPC, ECR, Lambda, SQS, API Gateway, RDS, etc.) **não** é criada no console: ela é criada pelo **Terraform** quando você rodar **Terraform Apply** (manual ou via workflow). Este guia prepara apenas o que o Terraform e o CI/CD precisam **antes** do primeiro apply.

---

## Pré-requisitos

- Conta AWS ativa.
- Acesso ao console AWS (ou IAM com permissões para S3, DynamoDB, IAM).
- ID da conta AWS (menu do console, canto superior direito, ou `aws sts get-caller-identity`).
- Nome da **organização** e dos **repositórios** no GitHub (ex.: `minha-org/Fase3-InfraOrchestrador`, `minha-org/Fase3-UsersAPI`).

---

## Passo 1 — Bucket S3 para o state do Terraform

1. No console AWS: **S3** → **Create bucket**.
2. **Bucket name:** use um nome **globalmente único**. Sugestão: `fcg-terraform-state-ACCOUNT-ID` (substitua `ACCOUNT-ID` pelo ID da sua conta, ex.: `fcg-terraform-state-123456789012`).
3. **Region:** escolha a região onde vai rodar a infra (ex.: `us-east-1`). Anote; será usada no `backend.hcl`.
4. **Block Public Access:** deixe **Block all public access** marcado.
5. **Bucket Versioning:** ative **Enable** (necessário para o backend remoto do Terraform).
6. **Default encryption:** ative **Server-side encryption** com **SSE-S3** (AES-256). Opcional: marque **Bucket Key**.
7. Crie o bucket.

**Resumo:** você vai precisar do **nome do bucket** e da **região** para o Passo 6.

---

## Passo 2 — Tabela DynamoDB para lock do state

1. No console AWS: **DynamoDB** → **Create table**.
2. **Table name:** `fcg-terraform-locks` (ou outro nome; anote para o `backend.hcl`).
3. **Partition key:** nome `LockID`, tipo **String**.
4. **Table settings:** **On-demand** (Pay per request).
5. Crie a tabela.

**Resumo:** você vai precisar do **nome da tabela** para o Passo 6.

---

## Passo 3 — Identity provider OIDC (GitHub → AWS)

1. No console AWS: **IAM** → **Identity providers** → **Add provider**.
2. **Provider type:** OpenID Connect.
3. **Provider URL:** `https://token.actions.githubusercontent.com`
4. **Audience:** `sts.amazonaws.com`
5. **Add provider**.

Isso permite que o GitHub Actions solicite credenciais temporárias na AWS sem access key. Só é necessário criar **uma vez** por conta.

---

## Passo 4 — IAM Role para o orquestrador (Terraform)

Esta role será assumida pelo repositório **Fase3-InfraOrchestrador** quando rodar Terraform (plan/apply/destroy).

### 4.1 Criar a role

1. **IAM** → **Roles** → **Create role**.
2. **Trusted entity type:** **Custom trust policy**.
3. **Custom trust policy:** cole o JSON abaixo e **substitua**:
   - `ACCOUNT_ID` → ID da sua conta AWS (ex.: `123456789012`).
   - `ORG` → organização ou usuário dono do repositório no GitHub (ex.: `minha-org`).
   - `REPO` → nome do repositório do orquestrador: `Fase3-InfraOrchestrador`.

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

Exemplo com valores preenchidos:  
`"token.actions.githubusercontent.com:sub": "repo:minha-org/Fase3-InfraOrchestrador:*"`

4. **Next**.
5. **Add permissions:** anexe políticas que permitam ao Terraform:
   - Ler/escrever no **bucket S3** do state e na **tabela DynamoDB** de lock.
   - Criar/alterar/remover os recursos que o Terraform provisiona: **VPC, EC2, Lambda, ECR, API Gateway, SQS, RDS, S3 (frontend), CloudWatch Logs, IAM** (roles/policies usadas pela Lambda), etc.

   **Opção A (mais simples para ambiente de estudo/demo):** anexe a managed policy **AdministratorAccess**.  
   **Opção B (recomendado para produção):** crie uma **custom policy** com as ações necessárias para os serviços acima (S3, DynamoDB, ec2, lambda, ecr, apigateway, sqs, rds, logs, iam, etc.). Exemplo mínimo para o backend:

   - S3: `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`, `s3:ListBucket` no bucket do state.
   - DynamoDB: `dynamodb:GetItem`, `dynamodb:PutItem`, `dynamodb:DeleteItem`, `dynamodb:BatchGetItem`, `dynamodb:BatchWriteItem`, `dynamodb:ConditionCheckItem` na tabela de lock.

   E as permissões equivalentes para os recursos que o Terraform cria (Lambda, ECR, API Gateway, etc.). Consulte a documentação do Terraform AWS provider se quiser restringir ao mínimo.

6. **Next** → nome da role, ex.: `github-fcg-terraform` → **Create role**.
7. **Copie o ARN da role** (ex.: `arn:aws:iam::123456789012:role/github-fcg-terraform`). Esse valor será o secret **AWS_ROLE_ARN_TERRAFORM** no GitHub (Passo 7).

---

## Passo 5 — IAM Role para cada serviço (push no ECR)

Para cada repositório que publica imagem no ECR (Fase3-UsersAPI, Fase3-GamesAPI, Fase3-PaymentsAPI, Fase3-NotificationLambda), crie **uma role** com trust no **repositório daquele serviço**.

### 5.1 Por repositório de serviço

1. **IAM** → **Roles** → **Create role**.
2. **Trusted entity type:** **Custom trust policy**.
3. **Custom trust policy:** mesmo JSON do Passo 4.1, mas em `repo:ORG/REPO:*` use o **repositório do serviço** (ex.: `repo:minha-org/Fase3-UsersAPI:*`).
4. **Add permissions:** a role precisa de:
   - **ECR:** `ecr:GetAuthorizationToken` (em `*`).
   - **ECR (repositórios):** `ecr:BatchCheckLayerAvailability`, `ecr:GetDownloadUrlForLayer`, `ecr:PutImage`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload`, `ecr:BatchGetImage` nos repositórios ECR que esse serviço vai usar (ou em `*` para simplificar).

   **Opção simples:** anexe a managed policy **AmazonEC2ContainerRegistryPowerUser** (permite push/pull nas imagens; não permite criar/deletar repositórios). Ou crie uma custom policy restrita aos ARNs dos repositórios ECR.

5. Nome sugerido por serviço: `github-fcg-users-api-ecr`, `github-fcg-games-api-ecr`, etc.
6. **Create role** e **copie o ARN**. Esse ARN será o secret **AWS_ROLE_ARN_ECR** no **repositório daquele serviço** (Passo 7).

Repita para **Fase3-GamesAPI**, **Fase3-PaymentsAPI** e **Fase3-NotificationLambda** (cada um com sua role e trust no repo correspondente).

---

## Passo 6 — Preencher backend.hcl (no repositório local)

O Terraform precisa saber **onde** está o state e **onde** está a tabela de lock. Isso é configurado em `environments/<env>/backend.hcl`.

1. Abra no editor os arquivos:
   - `environments/prod/backend.hcl`
   - `environments/staging/backend.hcl` (se usar staging)
   - `environments/demo/backend.hcl` (se usar demo)
2. Substitua os valores:
   - **bucket** → nome do bucket criado no Passo 1 (ex.: `fcg-terraform-state-123456789012`).
   - **dynamodb_table** → nome da tabela do Passo 2 (ex.: `fcg-terraform-locks`).
   - **region** → região do bucket (ex.: `us-east-1`).
   - **key** → já está definida por ambiente (`fcg-infra/prod/terraform.tfstate`, etc.); normalmente não precisa alterar.
   - **encrypt** → deixe `true`.

Exemplo final para `environments/prod/backend.hcl`:

```hcl
bucket         = "fcg-terraform-state-123456789012"
key            = "fcg-infra/prod/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "fcg-terraform-locks"
encrypt        = true
```

Remova qualquer placeholder como `REPLACE-WITH-ACCOUNT-ID`.

---

## Passo 7 — Configurar GitHub (Secrets e Variables)

### 7.1 No repositório **Fase3-InfraOrchestrador**

- **Settings** → **Secrets and variables** → **Actions**.

| Nome | Tipo | Valor |
|------|------|--------|
| `AWS_ROLE_ARN_TERRAFORM` | Secret | ARN da role criada no Passo 4 (ex.: `arn:aws:iam::123456789012:role/github-fcg-terraform`) |
| `TF_VAR_POSTGRES_MASTER_PASSWORD` | Secret | Senha do PostgreSQL (só se for usar RDS; o Terraform usa como `TF_VAR_postgres_master_password`) |

Variables (opcional):

| Nome | Valor |
|------|--------|
| `AWS_REGION` | Região AWS (ex.: `us-east-1`). Se não definir, os workflows usam `us-east-1`. |

### 7.2 Em cada repositório de serviço (UsersAPI, GamesAPI, PaymentsAPI, NotificationLambda)

- **Settings** → **Secrets and variables** → **Actions**.

Secrets:

| Nome | Valor |
|------|--------|
| `AWS_ROLE_ARN_ECR` | ARN da role **desse** serviço criada no Passo 5 |
| `ORCHESTRATOR_REPO_TOKEN` | PAT (Personal Access Token) do GitHub com permissão para enviar `repository_dispatch` no repositório do orquestrador |

Variables:

| Nome | Valor |
|------|--------|
| `ECR_REPOSITORY_NAME` | Nome do repositório no ECR **desse** serviço. Será definido **depois** do primeiro Terraform Apply (output `ecr_repository_urls`). Até lá pode usar o padrão do Terraform, ex.: `fcg-prod-users-api` (ajuste `prod` e o sufixo conforme ambiente e módulo ECR). |
| `ORCHESTRATOR_REPO` | Repositório do orquestrador no formato `owner/repo` (ex.: `minha-org/Fase3-InfraOrchestrador`) |
| `AWS_REGION` | (Opcional) Região do ECR (ex.: `us-east-1`) |

O **ECR_REPOSITORY_NAME** deve ser exatamente o nome do repositório ECR que o Terraform criar para aquele serviço (ex.: `fcg-prod-users-api`). Após o primeiro apply, confira em **Terraform outputs** ou no console ECR.

---

## Ordem recomendada após o setup manual

1. **Commit** das alterações em `backend.hcl` (se estiver usando controle de versão).
2. **Rodar Terraform** no orquestrador:
   - **Local:**  
     `terraform init -backend-config=environments/prod/backend.hcl`  
     `terraform plan -out=tfplan`  
     `terraform apply tfplan`
   - **GitHub Actions:** workflow **Terraform Plan** → revisar → workflow **Terraform Apply** (com environment `prod` ou o desejado).
3. **Anotar os outputs** do Terraform (ex.: `ecr_repository_urls`, `api_gateway_endpoint`).
4. **Ajustar** em cada serviço a variable `ECR_REPOSITORY_NAME` para o nome correto do repositório ECR.
5. Quando quiser reativar o deploy automático: reative o workflow **Deploy from service update** (e o gatilho que chama o orquestrador) no repositório InfraOrchestrador.

---

## Checklist rápido

- [ ] Bucket S3 criado (versionamento + criptografia); nome anotado.
- [ ] Tabela DynamoDB criada (chave `LockID`); nome anotado.
- [ ] Identity provider OIDC configurado (`token.actions.githubusercontent.com`, audience `sts.amazonaws.com`).
- [ ] Role do orquestrador criada (trust no repo `ORG/Fase3-InfraOrchestrador`); permissões Terraform (S3 state, DynamoDB lock + recursos a provisionar); ARN anotado.
- [ ] Role por serviço criada (trust no repo do serviço); permissão ECR; ARN anotado por repo.
- [ ] `environments/<env>/backend.hcl` preenchido (bucket, dynamodb_table, region) para cada ambiente usado.
- [ ] GitHub: secret `AWS_ROLE_ARN_TERRAFORM` no orquestrador; secret `TF_VAR_POSTGRES_MASTER_PASSWORD` se usar RDS.
- [ ] GitHub: em cada serviço, `AWS_ROLE_ARN_ECR`, `ORCHESTRATOR_REPO_TOKEN`, variables `ECR_REPOSITORY_NAME` e `ORCHESTRATOR_REPO`.
- [ ] Primeiro `terraform apply` executado; outputs conferidos; `ECR_REPOSITORY_NAME` ajustado nos serviços.

---

## Se você não vai usar Terraform

Depois de criar bucket, DynamoDB, OIDC e roles (ou só as roles do GitHub/ECR), se a infra for **toda** manual no console, use:

→ **[PROXIMOS-PASSOS-SEM-TERRAFORM.md](PROXIMOS-PASSOS-SEM-TERRAFORM.md)** — ordem do que criar (ECR, SQS, Lambda, etc.) e o que configurar nos repositórios e nas aplicações.

---

## Referências

- **Bootstrap (Terraform):** [BOOTSTRAP.md](BOOTSTRAP.md) — equivalente em Terraform do Passo 1 e 2.
- **OIDC e roles:** [OIDC.md](OIDC.md) — detalhes de trust policy e políticas.
- **Operação do dia a dia:** [README-OPERATIONAL.md](README-OPERATIONAL.md) — plan, apply, destroy, rollback, erros comuns.
