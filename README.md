# Documentação operacional — FCG Fenix

Manual de operação da infraestrutura e do pipeline de deploy do projeto FCG Fenix. Use este documento para provisionar infra, rodar Terraform, entender o CI/CD, fazer deploy manual, investigar falhas e seguir convenções de naming e tags.

**Variáveis e configuração:** seção **13** (variáveis do GitHub por repositório) e **14** (variáveis nas EC2 e no Terraform), com passo a passo detalhado.

---

## 1. Visão geral da arquitetura

- **Ambiente:** produção única; não se usa "prod" no nome dos recursos, apenas na tag `Environment`.
- **Repositórios:** 1 repositório de infraestrutura (Terraform + workflows reutilizáveis) e 1 repositório por API: usersapi, gamesapi, paymentsapi.
- **Entrada pública:** API Gateway HTTP API → VPC Link → ALB interno (privado) → target groups por path (`/users/*`, `/games/*`, `/payments/*`) → uma EC2 privada por serviço.
- **Compute:** uma instância EC2 privada por API (`fcg-fenix-usersapi-ec2`, `fcg-fenix-gamesapi-ec2`, `fcg-fenix-paymentsapi-ec2`). Em cada EC2 roda um container Docker (imagem ECR) com API .NET + PostgreSQL no mesmo container (build via `Dockerfile.postgres`).
- **Registry:** um repositório ECR por API (`fcg-fenix-{service}-ecr`).
- **Deploy:** GitHub Actions faz build da imagem, push no ECR e chama o workflow reutilizável do repositório de infraestrutura, que executa deploy remoto na EC2 via **SSM Run Command** (login ECR, atualização de `.env`, `docker compose pull` e `up -d`).
- **Autenticação AWS:** OIDC (GitHub Actions assume role IAM sem chaves estáticas).

Fluxo resumido: **código (API) → build → push ECR → SSM na EC2 → docker compose up**.

---

## 2. Como provisionar a infraestrutura

A infraestrutura é provisionada com **Terraform** no ambiente `production`. O root do Terraform é `terraform/environments/production`.

### Pré-requisitos

1. **Backend remoto (primeira vez)**  
   - Criar bucket S3: `fcg-fenix-tfstate`.  
   - Criar tabela DynamoDB para lock: `fcg-fenix-tfstate-lock` (partition key: `LockID`, tipo String).  
   - Em `terraform/environments/production/backend.tf`, descomentar o bloco `backend "s3"` e ajustar `bucket`, `region` e `dynamodb_table`.

2. **Variáveis**  
   - Copiar `terraform/environments/production/terraform.tfvars.example` para `terraform.tfvars` no mesmo diretório.  
   - Preencher `terraform.tfvars` (região, VPC, subnets, `tags_base`, `github_oidc_org`, `github_oidc_repos`, `instance_type`, `alb_target_port`). Não versionar `terraform.tfvars` se contiver segredos.

3. **Credenciais AWS**  
   - Para execução local: AWS CLI configurado (perfil ou variáveis de ambiente) com permissões para criar os recursos.  
   - Para GitHub Actions: configurar variáveis do repositório (`AWS_REGION`) e o secret ou variável `AWS_ROLE_ARN` da role OIDC com permissões de Terraform e acesso ao backend S3.

### Ordem de provisionamento

1. `terraform init` (no diretório `terraform/environments/production`).  
2. `terraform plan -var-file=terraform.tfvars` para revisar mudanças.  
3. `terraform apply -var-file=terraform.tfvars` (ou usar o workflow **Terraform Apply** no GitHub).

Após o apply, cada EC2 terá user data que instala Docker e cria o diretório `/opt/fcg-fenix/{service}`. É necessário copiar manualmente (ou via automação) os arquivos `docker-compose.yml`, `.env` e opcionalmente `deploy.sh` para cada EC2 nesse path — ver exemplos em `docs/ec2-examples/` e `docs/deploy-estrategia-operacional-ec2.md`.

---

## 3. Como rodar Terraform plan

### No GitHub Actions (recomendado)

- **Workflow:** `Terraform Plan` (`.github/workflows/terraform-plan.yml`).  
- **Gatilho:** pull request para a branch `master` que altera arquivos em `terraform/**` ou o próprio workflow.  
- **Passos:** checkout → Configure AWS (OIDC) → Setup Terraform → `terraform fmt -check` → `terraform init` → `terraform validate` → `terraform plan -no-color -input=false -out=tfplan -var-file=terraform.tfvars`. O log do plan é postado como comentário no PR.  
- **Requisitos:** no repositório de infraestrutura, configurar `vars.AWS_ROLE_ARN` (ou secret) e `vars.AWS_REGION` (opcional, default `us-east-1`). O arquivo `terraform.tfvars` deve existir no ambiente do workflow (por exemplo versionado sem segredos ou injetado por outro meio).

### Local

A partir da raiz do repositório de infraestrutura:

```bash
cd terraform/environments/production
terraform init
terraform plan -var-file=terraform.tfvars
```

Ou, da raiz do repo:

```bash
terraform -chdir=terraform/environments/production init
terraform -chdir=terraform/environments/production plan -var-file=terraform.tfvars
```

---

## 4. Como rodar Terraform apply

### No GitHub Actions

- **Workflow:** `Terraform Apply` (`.github/workflows/terraform-apply.yml`).  
- **Gatilho:** push na branch `master` que altera `terraform/**` ou o próprio workflow, ou execução manual (`workflow_dispatch`).  
- **Ambiente:** usa o environment `production` (pode ser protegido com aprovação).  
- **Passos:** checkout → Configure AWS (OIDC) → Setup Terraform → `terraform init` → `terraform apply -auto-approve -input=false -var-file=terraform.tfvars`.  
- **Requisitos:** mesmo que o plan (`vars.AWS_ROLE_ARN`, `vars.AWS_REGION`, `terraform.tfvars` disponível).

### Local

```bash
cd terraform/environments/production
terraform init
terraform apply -var-file=terraform.tfvars
```

Ou com `-auto-approve` para não pedir confirmação:

```bash
terraform apply -auto-approve -input=false -var-file=terraform.tfvars
```

---

## 5. Como funciona o CI/CD entre os repositórios

- **Repositório de infraestrutura**  
  - Contém Terraform (VPC, ALB, EC2, ECR, IAM, SSM, API Gateway) e o workflow **reutilizável** de deploy em EC2 (`.github/workflows/deploy-ec2.yml`).  
  - Workflows de Terraform: **Terraform Plan** (em PRs) e **Terraform Apply** (em push em `master` ou manual).

- **Repositórios das APIs (usersapi, gamesapi, paymentsapi)**  
  - Cada um tem um workflow de deploy (ex.: `.github/workflows/deploy.yml`) que:  
    1. Dispara em push na branch de deploy (ex.: `junonn/mvp-aws`).  
    2. Roda **testes** (restore, build, test da solution .NET).  
    3. Faz **build** da imagem Docker (`Dockerfile.postgres`) e **push** para o ECR do serviço, com tag = `github.sha`.  
    4. Chama o workflow reutilizável do repositório de infraestrutura (`vars.INFRA_REPO`), passando: `aws_region`, `environment`, `service`, `repository` (URI do ECR), `image_tag` e o secret `AWS_ROLE_ARN`.

- **Workflow reutilizável (deploy-ec2.yml)**  
  - Recebe: `aws_region`, `environment`, `service`, `repository`, `image_tag` e secret `AWS_ROLE_ARN`.  
  - Localiza a EC2 pelo nome (tag `Name` = `fcg-fenix-{service}-ec2`).  
  - Envia um comando SSM (`AWS-RunShellScript`) que na EC2: faz login no ECR, atualiza `ECR_REGISTRY` e `IMAGE_TAG` no `.env` em `/opt/fcg-fenix/{service}`, e executa `docker compose pull` e `docker compose up -d`.  
  - Se não existir `docker-compose.yml`, usa fallback: `docker pull`, `docker stop/rm` do container antigo e `docker run` do novo.

**Variáveis necessárias nos repositórios das APIs:**  
- `vars.INFRA_REPO`: organização/repositório do repo de infra (ex.: `minha-org/fcg-fenix-infra-repo`).  
- `vars.AWS_REGION`: opcional (default `us-east-1`).  
- **Secret** `AWS_ROLE_ARN`: ARN da role OIDC com permissão para SSM SendCommand, ECR e EC2 DescribeInstances (e, no repo de infra, para Terraform/backend S3 quando aplicável).

---

## 6. Como adicionar um novo serviço

1. **Terraform (repositório de infraestrutura)**  
   - Em `terraform/environments/production/locals.tf`: adicionar o novo serviço em `local.services` (ex.: `"newapi"`) e, se houver ALB por path, em `local.alb_path_prefix_to_service` (ex.: `"/new" = "newapi"`).  
   - Replicar módulos por serviço:  
     - `module "ecr"`: já usa `local.services`; garantir que o novo nome esteja em `local.services`.  
     - Criar `module "iam_ec2_newapi"` (fonte: `modules/iam/ec2-api`), com `service = "newapi"` e `ecr_repository_arns = [module.ecr.repository_arns["newapi"]]`.  
     - Criar `module "ec2_newapi"` (fonte: `modules/ec2-api`) com `service = "newapi"`, security group, instance profile e target group do ALB correspondentes.  
   - No módulo `security-groups`: adicionar security group para o novo serviço (ex.: `newapi_sg_id`) e expor como output.  
   - No módulo `alb`: garantir que `path_prefix_to_service` e target groups incluam o novo serviço (normalmente via `local.services` e `local.alb_path_prefix_to_service`).  
   - No módulo `ssm`: incluir o novo serviço em `local.services` se o módulo iterar sobre ela.  
   - Rodar `terraform plan` e `terraform apply`.

2. **EC2 e arquivos no host**  
   - Na nova EC2 (ou no user data), criar `/opt/fcg-fenix/newapi` e colocar `docker-compose.yml`, `.env` e opcionalmente `deploy.sh`, seguindo os exemplos de `docs/ec2-examples/` (copiar de usersapi e ajustar nomes, ECR, `POSTGRES_DB`).

3. **Repositório da nova API**  
   - Criar repositório do código da API e workflow de deploy (`.github/workflows/deploy.yml`) no mesmo padrão dos existentes: trigger na branch de deploy, testes, build com `Dockerfile.postgres`, push para o ECR do novo serviço, chamada ao reusable `deploy-ec2.yml` com `service = newapi`.  
   - Configurar no novo repo: `vars.INFRA_REPO`, `vars.AWS_REGION`, secret `AWS_ROLE_ARN`.  
   - Na role OIDC da AWS, incluir o novo repositório em trust policy (e em `github_oidc_repos` no Terraform, se aplicável).

4. **Convenções**  
   - Nome do recurso: `fcg-fenix-newapi-ec2`, `fcg-fenix-newapi-ecr`, `fcg-fenix-newapi-tg`, etc.  
   - Tags: `Application = newapi`, `Service = newapi` (além de `Project`, `ManagedBy`, `Environment`).

---

## 7. Como fazer deploy manual emergencial

Quando o pipeline não está disponível ou é necessário implantar uma tag específica na EC2:

1. **Acesso à EC2**  
   - Via SSM Session Manager (recomendado) ou SSH (se habilitado), usando a instância correta (ver seção 9).

2. **Usar o script `deploy.sh` (se existir em `/opt/fcg-fenix/{service}/`)**  
   ```bash
   cd /opt/fcg-fenix/usersapi   # ou gamesapi, paymentsapi
   ./deploy.sh <commit-sha-ou-tag>
   ```  
   O script atualiza `IMAGE_TAG` no `.env`, faz login no ECR, `docker compose pull` e `docker compose up -d`.

3. **Sem `deploy.sh`**  
   - Editar manualmente o `.env`: `IMAGE_TAG=<tag-desejada>`.  
   - Em seguida:
     ```bash
     cd /opt/fcg-fenix/usersapi
     aws ecr get-login-password --region us-east-1 | sudo docker login --username AWS --password-stdin <account>.dkr.ecr.us-east-1.amazonaws.com
     sudo docker compose pull
     sudo docker compose up -d
     ```

4. **Conferir**  
   - `sudo docker compose ps` e logs: `sudo docker compose logs -f app`.

---

## 8. Como investigar falha de deploy

1. **GitHub Actions (repo da API)**  
   - Ver qual job falhou: **Test**, **Build & Push to ECR** ou **Deploy to EC2 (SSM)**.  
   - Se falhou no **Deploy**: o passo "Deploy via SSM Run Command" mostra o `CommandId`. Anotar o `CommandId` e o `instance_id` do job.

2. **Console AWS**  
   - **SSM → Run Command → Command history**: localizar o comando pelo `CommandId` ou pelo comentário "Deploy {service} from GitHub Actions". Abrir a invocação na instância e ver **Output** e **Status** (Success / Failed / Timed Out etc.).

3. **Na EC2 (SSM Session ou SSH)**  
   - Verificar se o diretório e arquivos existem:
     ```bash
     ls -la /opt/fcg-fenix/usersapi/
     ```
     Deve haver `docker-compose.yml` e `.env`.  
   - Ver logs do Docker:
     ```bash
     cd /opt/fcg-fenix/usersapi
     sudo docker compose logs -f app
     ```
   - Verificar se a imagem foi puxada e se o container está rodando:
     ```bash
     sudo docker images
     sudo docker compose ps
     ```
   - Testar login no ECR (a instância usa IAM role para ECR):
     ```bash
     aws ecr get-login-password --region us-east-1 | sudo docker login --username AWS --password-stdin <account>.dkr.ecr.us-east-1.amazonaws.com
     ```

4. **Causas comuns**  
   - EC2 sem `docker-compose.yml` ou `.env` em `/opt/fcg-fenix/{service}`.  
   - Role da EC2 sem permissão para ECR (pull).  
   - Instância não encontrada: tag `Name` diferente de `fcg-fenix-{service}-ec2` ou instância parada.  
   - SSM Agent desatualizado ou instância fora do inventário SSM (sem role com `ssm:UpdateInstanceInformation` etc.).  
   - Falha no health check do ALB (app não responde na porta configurada no target group).

---

## 9. Como localizar a EC2 certa por tags

As EC2 são nomeadas e tagadas de forma consistente. Para achar a instância de um serviço:

- **Nome (tag `Name`):** `fcg-fenix-{service}-ec2`  
  Ex.: `fcg-fenix-usersapi-ec2`, `fcg-fenix-gamesapi-ec2`, `fcg-fenix-paymentsapi-ec2`.

**AWS CLI (exemplo usersapi):**

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=fcg-fenix-usersapi-ec2" "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].[InstanceId,PrivateIpAddress,Tags[?Key==`Name`].Value|[0]]' \
  --output table
```

Por tags de governança:

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=fcg-fenix" "Name=tag:Service,Values=usersapi" "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].InstanceId' --output text
```

**Console AWS:** EC2 → Instances → filtros por tag: `Name = fcg-fenix-usersapi-ec2` ou `Service = usersapi` e `Project = fcg-fenix`.

O **SSM Session Manager** lista as instâncias por nome; escolha a que tiver o `Name` correspondente ao serviço.

---

## 10. Como restaurar ou validar o Postgres em Docker

Cada serviço roda Postgres dentro do mesmo container da API (imagem `Dockerfile.postgres`). O dado persiste em volume nomeado (ex.: `users_pgdata`) mapeado em `/var/lib/postgresql/data`.

### Validar conectividade e estado

- **Dentro do container (usuário padrão e DB usersapi):**
  ```bash
  sudo docker exec fcg-fenix-usersapi pg_isready -U postgres -d fcg_users
  ```
- **Abrir psql:**
  ```bash
  sudo docker exec -it fcg-fenix-usersapi psql -U postgres -d fcg_users -c '\l'
  ```

Para **gamesapi** e **paymentsapi**, trocar o nome do container e o banco: `fcg-fenix-gamesapi` / `fcg_games`, `fcg-fenix-paymentsapi` / `fcg_payments`.

### Backup (dump)

```bash
sudo docker exec fcg-fenix-usersapi pg_dump -U postgres -d fcg_users > backup_users_$(date +%Y%m%d_%H%M).sql
```

### Restore

```bash
# Copiar o .sql para dentro do container ou usar stdin
cat backup_users_20250101_1200.sql | sudo docker exec -i fcg-fenix-usersapi psql -U postgres -d fcg_users
```

Ou com `pg_restore` se o backup for custom/directory format.

### Observação

O volume do Postgres fica em `/var/lib/docker/volumes/...` no host. Não remover o volume ao fazer `docker compose down` se quiser manter os dados; use `docker compose down` sem `-v`. Migrações da aplicação .NET rodam no startup da API; ao subir nova imagem, o volume persiste e as migrações são aplicadas sobre os dados existentes.

---

## 11. Convenções de naming

- **Padrão:** `fcg-fenix-{aplicacao-ws}-{identificador}`  
  - Tudo em minúsculas, sem acento, sem espaço, separado por hífen.  
  - **aplicacao-ws:** nome curto do serviço (ex.: `usersapi`, `gamesapi`, `paymentsapi`) ou `main` para recursos compartilhados.  
  - **identificador:** tipo do recurso (ex.: `ec2`, `ecr`, `tg`, `sg`, `role`, `profile`).

**Exemplos:**

| Recurso        | Nome                         |
|----------------|------------------------------|
| EC2 usersapi  | `fcg-fenix-usersapi-ec2`     |
| ECR usersapi  | `fcg-fenix-usersapi-ecr`      |
| Target group  | `fcg-fenix-usersapi-tg`       |
| Security group| `fcg-fenix-usersapi-sg`       |
| IAM role      | `fcg-fenix-usersapi-role`     |
| Instance profile | `fcg-fenix-usersapi-profile` |
| ALB (compartilhado) | `fcg-fenix-main-alb`   |
| VPC           | `fcg-fenix-main-vpc`          |

Não se usa "prod" no nome dos recursos; o ambiente é indicado pela tag `Environment`.

Detalhes em `docs/01-arquitetura-e-convencoes.md` e `CONVENTIONS.md`.

---

## 12. Convenções de tags

Tags obrigatórias em recursos AWS (governança e billing):

| Tag          | Valor                                      | Uso                |
|-------------|--------------------------------------------|--------------------|
| **Project** | `fcg-fenix`                                | Agrupamento        |
| **ManagedBy** | `terraform`                              | Indica IaC         |
| **Environment** | `production`                          | Ambiente           |
| **Application** | `usersapi` / `gamesapi` / `paymentsapi` | Serviço            |
| **Service** | `usersapi` / `gamesapi` / `paymentsapi`    | Mesmo que Application |

Recursos compartilhados (ex.: VPC, ALB) podem usar `Application = shared`, `Service = shared`. Recursos do GitHub Actions: `Application = githubactions`, `Service = githubactions`.

**Regra:** o **nome** do recurso identifica o recurso; as **tags** servem para governança, custo e automação. Manter nomes e tags alinhados ao padrão acima.

No Terraform, as tags base vêm de `var.tags_base` e são complementadas por módulos (ex.: `Application`, `Service`) em `terraform/environments/production/locals.tf` e nos módulos.

---

## 13. Variáveis do GitHub (repositórios)

Cada repositório precisa de **Variables** e **Secrets** configurados em **Settings → Secrets and variables → Actions**. O valor de **AWS_ROLE_ARN** é o ARN de uma IAM Role criada com OIDC (GitHub); na **seção 13.4** há JSON prontos para criar essa role e suas políticas.

### 13.1 Repositório de infraestrutura (Fase3-InfraOrchestrador)

Usado pelos workflows **Terraform Plan**, **Terraform Apply** e pelo **Deploy EC2 (reusable)** quando chamado pelos repos das APIs (o reusable recebe o secret repassado pelo caller).

| Tipo    | Nome            | Obrigatório | Descrição |
|---------|-----------------|-------------|-----------|
| Variable | `AWS_REGION`   | Não         | Região AWS (ex.: `us-east-1`). Default nos workflows: `us-east-1` se não definido. |
| Variable | `AWS_ROLE_ARN` | Sim         | ARN da role IAM que o GitHub Actions assume via OIDC (Terraform plan/apply: acesso a S3/DynamoDB, AWS APIs; deploy-ec2: recebido como secret do repo que chama). |

**Passo a passo — Repositório de infraestrutura:**

1. Abra o repositório no GitHub → **Settings** → **Secrets and variables** → **Actions**.
2. Aba **Variables**:
   - **New repository variable**: nome `AWS_REGION`, valor `us-east-1` (ou a região do ambiente).
   - **New repository variable**: nome `AWS_ROLE_ARN`, valor o ARN da role OIDC (ex.: `arn:aws:iam::123456789012:role/fcg-fenix-githubactions-role`).
3. Não é necessário criar **Secrets** no repo de infra para Terraform (os workflows usam `vars.AWS_ROLE_ARN`). O reusable `deploy-ec2.yml` usa `secrets.AWS_ROLE_ARN` **repassado pelo repositório que chama** (cada API repassa seu secret).
4. Salve. Os workflows **Terraform Plan** (em PR) e **Terraform Apply** (push em `master` ou manual) passarão a usar essas variáveis.

---

### 13.2 Repositórios das APIs (UsersAPI, GamesAPI, PaymentsAPI)

Cada um dos três repositórios (UsersAPI, GamesAPI, PaymentsAPI) deve ter as mesmas **variáveis e secrets** abaixo para o workflow de **deploy** (`.github/workflows/deploy.yml`) funcionar. O workflow **publish-image** (se usado) pode usar variáveis adicionais.

| Tipo    | Nome               | Obrigatório | Descrição |
|---------|--------------------|-------------|-----------|
| Variable | `INFRA_REPO`      | Sim         | Repositório de infra no formato `owner/repo` (ex.: `sua-org/Fase3-InfraOrchestrador`). Usado para chamar o reusable `/.github/workflows/deploy-ec2.yml@master`. |
| Variable | `AWS_REGION`      | Não         | Região AWS (ex.: `us-east-1`). Default nos workflows: `us-east-1`. |
| Secret   | `AWS_ROLE_ARN`    | Sim         | ARN da role IAM OIDC com permissão para ECR (push), SSM SendCommand e EC2 DescribeInstances. O mesmo ARN pode ser usado para os três repos se a trust policy permitir. |

**Passo a passo — Cada repositório de API (UsersAPI, GamesAPI, PaymentsAPI):**

1. Abra o repositório no GitHub → **Settings** → **Secrets and variables** → **Actions**.
2. Aba **Variables**:
   - **New repository variable**: nome `INFRA_REPO`, valor `SEU_OWNER/Fase3-InfraOrchestrador` (ex.: `minha-org/Fase3-InfraOrchestrador`). Substituir pelo owner real do repositório de infraestrutura.
   - **New repository variable** (opcional): nome `AWS_REGION`, valor `us-east-1`.
3. Aba **Secrets**:
   - **New repository secret**: nome `AWS_ROLE_ARN`, valor o ARN da role OIDC que tem permissão para ECR e SSM (ex.: `arn:aws:iam::123456789012:role/fcg-fenix-githubactions-role`). Pode ser a mesma role do repo de infra, desde que a trust policy inclua este repositório e a role tenha as políticas de ECR + SSM + EC2.
4. Salve. O deploy (push na branch de deploy) passará a conseguir fazer push no ECR e chamar o reusable de deploy na EC2.

**Se usar o workflow publish-image (opcional):** pode ser necessário também `vars.ECR_REPOSITORY_NAME` e `secrets.AWS_ROLE_ARN_ECR` conforme o workflow; para o deploy principal (deploy.yml) basta `INFRA_REPO`, `AWS_REGION` e `AWS_ROLE_ARN`.

---

### 13.3 Resumo — Onde configurar cada item

| Item            | Infra (Terraform) | Infra (deploy reusable) | UsersAPI / GamesAPI / PaymentsAPI |
|-----------------|-------------------|--------------------------|-----------------------------------|
| `AWS_REGION`    | Variable (opcional) | Herda do caller        | Variable (opcional)              |
| `AWS_ROLE_ARN`  | Variable (obrigatório para plan/apply) | Recebido como secret do caller | Secret (obrigatório) |
| `INFRA_REPO`    | —                 | —                        | Variable (obrigatório)            |

---

### 13.4 Role OIDC — JSON prontos para criar a role e políticas

A variável/secret **AWS_ROLE_ARN** refere-se a uma **IAM Role** (não a um IAM User) que o GitHub Actions assume via OIDC. Abaixo estão os JSON prontos para criar essa role no console AWS (ou via Terraform/CloudFormation).

**Pré-requisito:** ter configurado o **IdP OIDC do GitHub** na conta AWS: IAM → Identity providers → Add provider → OpenID Connect, URL `https://token.actions.githubusercontent.com`, audience `sts.amazonaws.com`. Se ainda não existir, crie o provider antes de criar a role.

**Passo a passo resumido:** (1) Criar uma nova role IAM; (2) Em "Trust relationships", usar o **Trust policy** abaixo; (3) Anexar ou criar uma policy inline com o **Permission policy** abaixo; (4) Copiar o ARN da role e colar em `AWS_ROLE_ARN` no GitHub.

---

#### Trust policy (relacionamento de confiança da role)

Permite que apenas o GitHub Actions dos repositórios listados assuma a role. Substitua `SUA_ORG` pelo owner/organização do GitHub (ex.: `minha-org` ou `meu-usuario`). Para restringir a um único repositório, use apenas o primeiro `Condition` com `StringLike` em `token.actions.githubusercontent.com:sub`.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::CONTA_AWS:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:SUA_ORG/Fase3-InfraOrchestrador:*"
        },
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        }
      }
    },
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::CONTA_AWS:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringLike": {
          "token.actions.githubusercontent.com:sub": [
            "repo:SUA_ORG/Fase3-UsersAPI:*",
            "repo:SUA_ORG/Fase3-GamesAPI:*",
            "repo:SUA_ORG/Fase3-PaymentsAPI:*"
          ]
        },
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
```

- **CONTA_AWS:** substituir pelo ID numérico da conta AWS (ex.: `123456789012`).
- **SUA_ORG:** substituir pelo owner/organização do GitHub. Se os nomes dos repositórios forem outros, ajuste (ex.: `minha-org/Fase3-InfraOrchestrador`).
- Se o IdP OIDC tiver outro nome (ex.: com prefixo), use o ARN correto em `Federated`.

Para **uma única role** usada por infra e pelos três repos de API, use os dois `Statement` acima (um para o repo de infra, outro para os três repos de API). Para roles separadas, use só o bloco correspondente.

---

#### Escopo da permission policy — quem usa o quê

A **mesma role** (e a mesma **permission policy** abaixo) atende a **todos** estes repositórios:

| Repositório | Uso da role |
|-------------|-------------|
| **Fase3-InfraOrchestrador** | Terraform plan/apply (state S3, lock DynamoDB, APIs AWS, IAM) e execução do workflow reutilizável `deploy-ec2.yml` quando chamado pelas APIs. |
| **Fase3-UsersAPI** | Deploy: push da imagem no ECR → chamada ao reusable `deploy-ec2.yml` (SSM + EC2). |
| **Fase3-GamesAPI** | Deploy: push da imagem no ECR → chamada ao reusable `deploy-ec2.yml` (SSM + EC2). |
| **Fase3-PaymentsAPI** | Deploy: push da imagem no ECR → chamada ao reusable `deploy-ec2.yml` (SSM + EC2). |

Resumo por bloco da policy (Sid): **TerraformState**, **TerraformLock**, **TerraformAWS**, **TerraformIAM** (e PassRole/CreateSLR) → só Infra. **ECRPush** / **ECRPushRepos** e **DeployEC2SSM** / **DeployEC2Describe** → Infra (quando roda o reusable) e os três repos de API (Users, Games, Payments). **Lambda** (se incluir) → opcional, para atualizar função como a notification-lambda.

---

#### Permission policy (política de permissões da role)

Uma única policy que cobre **Terraform** (plan/apply, state S3/DynamoDB, APIs AWS, IAM com restrições para PassRole e CreateServiceLinkedRole), **deploy** (ECR push, SSM SendCommand, EC2 DescribeInstances) e, opcionalmente, atualização de Lambda. Ajuste os ARNs (CONTA_AWS, REGIAO, nomes de bucket/tabela/ECR) conforme seu ambiente.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TerraformState",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::fcg-fenix-tfstate",
        "arn:aws:s3:::fcg-fenix-tfstate/*"
      ]
    },
    {
      "Sid": "TerraformLock",
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem",
        "dynamodb:ConditionCheckItem",
        "dynamodb:BatchGetItem",
        "dynamodb:BatchWriteItem",
        "dynamodb:DescribeTable"
      ],
      "Resource": "arn:aws:dynamodb:REGIAO:CONTA_AWS:table/fcg-fenix-tfstate-lock"
    },
    {
      "Sid": "TerraformAWS",
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "ecr:*",
        "ssm:*",
        "elasticloadbalancing:*",
        "apigateway:*",
        "logs:*",
        "s3:*",
        "dynamodb:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TerraformIAM",
      "Effect": "Allow",
      "NotAction": [
        "iam:PassRole",
        "iam:CreateServiceLinkedRole"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TerraformIAMPassRole",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": [
            "ec2.amazonaws.com",
            "elasticloadbalancing.amazonaws.com",
            "lambda.amazonaws.com",
            "apigateway.amazonaws.com",
            "ecs-tasks.amazonaws.com",
            "ecs.amazonaws.com"
          ]
        }
      }
    },
    {
      "Sid": "TerraformIAMCreateSLR",
      "Effect": "Allow",
      "Action": "iam:CreateServiceLinkedRole",
      "Resource": [
        "arn:aws:iam::CONTA_AWS:role/aws-service-role/ec2.amazonaws.com/*",
        "arn:aws:iam::CONTA_AWS:role/aws-service-role/elasticloadbalancing.amazonaws.com/*"
      ],
      "Condition": {
        "StringEquals": {
          "iam:AWSServiceName": [
            "ec2.amazonaws.com",
            "elasticloadbalancing.amazonaws.com"
          ]
        }
      }
    },
    {
      "Sid": "DeployEC2SSM",
      "Effect": "Allow",
      "Action": [
        "ssm:SendCommand",
        "ssm:GetCommandInvocation",
        "ssm:ListCommands"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DeployEC2Describe",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus",
        "ec2:DescribeTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ECRPush",
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ECRPushRepos",
      "Effect": "Allow",
      "Action": [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": [
        "arn:aws:ecr:REGIAO:CONTA_AWS:repository/fcg-fenix-usersapi-ecr",
        "arn:aws:ecr:REGIAO:CONTA_AWS:repository/fcg-fenix-gamesapi-ecr",
        "arn:aws:ecr:REGIAO:CONTA_AWS:repository/fcg-fenix-paymentsapi-ecr"
      ]
    }
  ]
}
```

- **CONTA_AWS:** ID da conta (ex.: `123456789012`).
- **REGIAO:** ex.: `us-east-1` (em `dynamodb:Resource` e `ecr:Resource`).

**Quem usa o quê (Infra + UsersAPI + GamesAPI + PaymentsAPI):** Terraform (state, lock, APIs, IAM) → só **Fase3-InfraOrchestrador**. ECR (auth + push nos três repositórios) e SSM/EC2 (deploy) → **Infra** (quando executa o reusable) e **Fase3-UsersAPI**, **Fase3-GamesAPI**, **Fase3-PaymentsAPI**. Os blocos **TerraformIAMPassRole** e **TerraformIAMCreateSLR** seguem as recomendações da AWS (evitar `iam:PassRole` e `iam:CreateServiceLinkedRole` com curinga em Action/Resource). Se precisar atualizar uma Lambda (ex.: notification-lambda) pela mesma role, adicione um Statement com `lambda:UpdateFunctionCode` e o ARN da função.

**Nome sugerido da role:** `fcg-fenix-githubactions-role`. Após criar a role, use o ARN (ex.: `arn:aws:iam::123456789012:role/fcg-fenix-githubactions-role`) em **Variables** ou **Secrets** do GitHub conforme a seção 13.1 e 13.2.

---

## 14. Variáveis nos projetos AWS (EC2 e Terraform)

### 14.1 Variáveis na EC2 (arquivo `.env` por serviço)

Cada EC2 tem um diretório `/opt/fcg-fenix/{service}` com o arquivo `.env` lido pelo `docker-compose`. O pipeline de deploy atualiza apenas `ECR_REGISTRY` e `IMAGE_TAG`; as demais devem estar configuradas na primeira preparação da EC2.

**Variáveis obrigatórias no `.env` (por serviço):**

| Variável         | Descrição | Exemplo (usersapi) |
|------------------|-----------|---------------------|
| `ECR_REGISTRY`   | URI do repositório ECR (sem tag) | `123456789012.dkr.ecr.us-east-1.amazonaws.com/fcg-fenix-usersapi-ecr` |
| `IMAGE_TAG`      | Tag da imagem (atualizada pelo SSM no deploy) | `latest` ou um `github.sha` |
| `POSTGRES_USER`  | Usuário do Postgres (interno ao container) | `postgres` |
| `POSTGRES_PASSWORD` | Senha do Postgres | Valor seguro (não versionar) |
| `POSTGRES_DB`    | Nome do banco | `fcg_users` (usersapi), `fcg_games` (gamesapi), `fcg_payments` (paymentsapi) |

**Passo a passo — Preparar `.env` em cada EC2 (por serviço):**

1. Conectar na EC2 (SSM Session Manager ou SSH) e ir ao diretório do serviço:
   ```bash
   cd /opt/fcg-fenix/usersapi   # ou gamesapi, paymentsapi
   ```
2. Criar ou editar o arquivo `.env` (ex.: `sudo nano .env` ou copiar de `docs/ec2-examples/usersapi/.env.example`).
3. Preencher com os valores corretos:
   - **ECR_REGISTRY:** obter no console AWS (ECR → repositório → View push commands) ou no output do Terraform `module.ecr.repository_urls["usersapi"]` (ou o nome do repo). Formato: `{conta}.dkr.ecr.{região}.amazonaws.com/fcg-fenix-{service}-ecr`.
   - **IMAGE_TAG:** pode iniciar com `latest`; o pipeline sobrescreve com o `github.sha` a cada deploy.
   - **POSTGRES_***: definir usuário, senha forte e nome do banco conforme a tabela acima.
4. Salvar e garantir permissões adequadas (ex.: `chmod 600 .env` se necessário). Não versionar `.env`.
5. Repetir para as outras EC2 (gamesapi, paymentsapi), alterando o path, `ECR_REGISTRY` e `POSTGRES_DB`.

Exemplos completos de `.env` por serviço estão em `docs/ec2-examples/{usersapi|gamesapi|paymentsapi}/.env.example`.

---

### 14.2 Variáveis do Terraform (terraform.tfvars)

O ambiente **production** usa variáveis definidas em `terraform/environments/production/variables.tf` e valores em `terraform.tfvars` (não versionado quando houver segredos).

**Variáveis que o projeto Terraform deve ter (terraform.tfvars):**

| Variável                 | Tipo   | Obrigatório | Descrição |
|--------------------------|--------|-------------|-----------|
| `aws_region`             | string | Não         | Região AWS (default: `us-east-1`). |
| `vpc_cidr`               | string | Sim         | CIDR da VPC (ex.: `10.0.0.0/16`). |
| `availability_zones`     | list(string) | Sim   | AZs (ex.: `["us-east-1a", "us-east-1b"]`). |
| `public_subnet_cidrs`    | list(string) | Sim   | CIDRs das subnets públicas (ordem = AZs). |
| `private_subnet_cidrs`   | list(string) | Sim   | CIDRs das subnets privadas (ordem = AZs). |
| `tags_base`              | object | Sim         | `Project`, `ManagedBy`, `Environment`. |
| `github_oidc_org`        | string | Sim         | Organização ou owner do GitHub para OIDC. |
| `github_oidc_repos`      | list(string) | Sim   | Lista de repos que podem assumir a role OIDC. |
| `instance_type`          | string | Não         | Tipo da EC2 (default: `t3.micro`). |
| `alb_target_port`        | number | Não        | Porta do target no ALB (default: `80`). |

**Passo a passo — Configurar Terraform (projeto AWS) para o ambiente production:**

1. Ir ao diretório do Terraform:
   ```bash
   cd terraform/environments/production
   ```
2. Copiar o exemplo de variáveis:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```
3. Editar `terraform.tfvars` e preencher:
   - **aws_region:** ex.: `"us-east-1"`.
   - **vpc_cidr:** ex.: `"10.0.0.0/16"`.
   - **availability_zones:** ex.: `["us-east-1a", "us-east-1b"]`.
   - **public_subnet_cidrs** e **private_subnet_cidrs:** ex.: `["10.0.1.0/24", "10.0.2.0/24"]` e `["10.0.10.0/24", "10.0.11.0/24"]`.
   - **tags_base:** `Project = "fcg-fenix"`, `ManagedBy = "terraform"`, `Environment = "production"`.
   - **github_oidc_org:** organização ou usuário do GitHub (ex.: `"minha-org"`).
   - **github_oidc_repos:** lista dos repositórios permitidos na trust policy da role OIDC (ex.: `["minha-org/Fase3-InfraOrchestrador", "minha-org/Fase3-UsersAPI", ...]`).
   - **instance_type** e **alb_target_port:** opcional; usar defaults se não precisar alterar.
4. Não versionar `terraform.tfvars` se contiver dados sensíveis (adicionar ao `.gitignore` se necessário).
5. Para rodar no GitHub Actions: o workflow espera que `terraform.tfvars` exista no repositório (sem segredos) ou que os valores sejam injetados por outro meio (ex.: environment secrets). Se usar apenas local, manter `terraform.tfvars` apenas na máquina local.

Referência completa: `terraform/environments/production/terraform.tfvars.example` e `terraform/environments/production/variables.tf`.

---

### 14.3 Resumo — Onde cada variável é usada

| Contexto        | Onde fica        | Usado por |
|-----------------|------------------|-----------|
| GitHub (Infra)  | Settings → Actions → Variables / (opcional) Secrets | Terraform Plan, Terraform Apply |
| GitHub (APIs)   | Settings → Actions → Variables + Secrets | deploy.yml (build, push ECR, chamada ao reusable) |
| EC2             | `/opt/fcg-fenix/{service}/.env` | docker-compose na EC2; SSM atualiza ECR_REGISTRY e IMAGE_TAG |
| Terraform       | `terraform/environments/production/terraform.tfvars` | terraform plan/apply (local ou GitHub) |

---

## Referências rápidas

- **Variáveis GitHub e AWS (passo a passo):** seções **13** e **14** deste documento. **Role OIDC (trust policy + permission policy em JSON):** seção **13.4**.  
- **Estratégia de deploy (EC2, compose, .env, SSM, rollback, Postgres):** `docs/deploy-estrategia-operacional-ec2.md`  
- **Exemplos de arquivos para EC2:** `docs/ec2-examples/` (README + docker-compose, .env.example, deploy.sh por serviço)  
- **Arquitetura e convenções:** `docs/01-arquitetura-e-convencoes.md`  
- **Resumo de convenções:** `CONVENTIONS.md`  
- **Blueprint Terraform (módulos ECR, ALB, EC2, IAM):** `docs/terraform-blueprint-ecr-alb-ec2-iam.md`  
- **Terraform (como rodar):** `terraform/README.md`
