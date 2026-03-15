# FCG Infra — AWS CDK

Infraestrutura como código com AWS CDK (TypeScript). Stacks para deploy incremental dos microsserviços. **Um único ambiente: produção.**

---

## Passo a passo para subir o projeto na nuvem

### Pré-requisitos

- **Conta AWS** com permissões para criar VPC, ECR, SQS, Lambda, ECS, API Gateway, CloudWatch, etc.
- **Node.js >= 18** (para rodar CDK localmente; no CI usa-se o do GitHub Actions).
- **Git** e acesso ao repositório do orquestrador e aos repositórios dos serviços (UsersAPI, GamesAPI, PaymentsAPI, NotificationLambda).

### Opção A: Deploy manual (local)

1. **Clone o repositório do orquestrador**
   ```bash
   git clone <url-do-Fase3-InfraOrchestrador>
   cd Fase3-InfraOrchestrador
   ```

2. **Instale dependências e faça bootstrap do CDK (uma vez por conta/região)**
   ```bash
   cd cdk
   npm install
   npx cdk bootstrap
   ```
   Configure antes as credenciais AWS (`aws configure` ou variáveis `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`).

3. **Faça o deploy das stacks**
   ```bash
   npx cdk deploy --all --require-approval never
   ```
   Ou por etapa: primeiro `fcg-prod-SharedInfra`, depois as demais na ordem do README.

4. **Envie as imagens Docker para o ECR**  
   Em cada repositório de serviço (Fase3-UsersAPI, Fase3-GamesAPI, Fase3-PaymentsAPI, Fase3-NotificationLambda), configure o ECR (URL/ nome do repositório criado pelo CDK) e rode o workflow de build/publish ou:
   ```bash
   aws ecr get-login-password --region <REGION> | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com
   docker build -t <repo>:latest .
   docker push <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/<repo>:latest
   ```

5. **Atualize os serviços que usam imagens**  
   Após o primeiro push das imagens, o ECS e a Lambda já apontam para `:latest`; um novo deploy do stack correspondente (`fcg-prod-NotificationLambda` ou `fcg-prod-EcsApis`) pode ser feito se precisar forçar atualização.

6. **Valide**  
   Acesse a URL do API Gateway (saída do stack `fcg-prod-ApiGateway`) e teste as rotas (ex.: `/.well-known/openid-configuration`, `/health` nos backends).

### Opção B: Deploy via CI/CD (GitHub Actions)

1. **Configure OIDC e a IAM Role na AWS**  
   Siga [docs/OIDC.md](../docs/OIDC.md) para criar o Identity Provider e uma IAM Role com permissões para CloudFormation e todos os recursos que o CDK cria (VPC, ECR, SQS, Lambda, ECS, API Gateway, CloudWatch, IAM, etc.). Pode ser a mesma role usada pelo Terraform se ela já tiver essas permissões.

2. **Configure o repositório no GitHub**
   - **Secrets:** crie o secret `AWS_ROLE_ARN_CDK` com o ARN da role (ex.: `arn:aws:iam::123456789012:role/github-fcg-cdk`).
   - **Variables (opcional):** `AWS_REGION` = `us-east-1` (ou a região desejada).

3. **Disparar o deploy**
   - **Manual:** no GitHub, aba **Actions** → workflow **CDK Deploy** → **Run workflow** (branch `main`) → **Run workflow**.
   - **Automático (opcional):** o workflow pode ser configurado para rodar no push para `main`; por padrão é apenas manual para evitar deploys acidentais.

4. **Após o primeiro deploy da infra**  
   Nos repositórios dos serviços (UsersAPI, GamesAPI, PaymentsAPI, NotificationLambda), configure as variáveis de ECR e os workflows de build/publish para apontar para os repositórios ECR criados pelo CDK (`fcg-prod-users-api`, `fcg-prod-games-api`, etc.). Depois, faça push das imagens (via workflow ou pipeline de cada serviço).

5. **Valide**  
   Use a URL do API Gateway (exibida no output do workflow ou no console AWS) para testar as rotas.

### Workflows de CI/CD (GitHub Actions)

| Workflow | Gatilho | O que faz |
|----------|---------|-----------|
| **CDK Diff** | Push/PR em `main` quando `cdk/**` muda | Roda `cdk synth` para validar o app. |
| **CDK Deploy** | Manual (Actions → CDK Deploy → Run workflow) | Assume a role AWS (OIDC), faz `cdk bootstrap` se necessário e `cdk deploy --all` (ou uma stack específica). Exige secret `AWS_ROLE_ARN_CDK`. |

---

## Instalação (desenvolvimento local)

```bash
cd cdk
npm install
```

## Bootstrap (uma vez por conta/região)

```bash
npx cdk bootstrap
```

## Stacks e ordem de deploy

| Stack | Descrição |
|-------|-----------|
| **SharedInfra** | VPC, ECR (4 repos), SQS (fila + DLQ), CloudWatch Logs. Deploy primeiro. |
| **NotificationLambda** | Lambda container (imagem ECR), trigger SQS, IAM (SQS, Logs, SES). |
| **EcsApis** | ECS Cluster + Fargate (Users API, Games API, Payments API) com ALB cada. |
| **ApiGateway** | HTTP API (v2), CORS, JWT Authorizer, rotas para os ALBs. |
| **Optional** | RDS PostgreSQL e/ou S3 frontend (só se `-c enableOptional=true`). |

Ordem recomendada:

1. `npx cdk deploy fcg-prod-SharedInfra`
2. Fazer push das imagens Docker para os repositórios ECR criados.
3. `npx cdk deploy fcg-prod-NotificationLambda`
4. `npx cdk deploy fcg-prod-EcsApis`
5. `npx cdk deploy fcg-prod-ApiGateway`

Ou em sequência:

```bash
npx cdk deploy --all
```

## Comandos úteis

- **Listar stacks:** `npx cdk list`
- **Diff:** `npx cdk diff`
- **Synth:** `npx cdk synth`
- **Deploy de uma stack:** `npx cdk deploy fcg-prod-SharedInfra` (ou o ID da stack)

## Contexto disponível (opcional)

| Contexto | Descrição | Default |
|----------|-----------|---------|
| `projectName` | Prefixo do projeto (nome dos stacks: `{projectName}-prod-*`) | fcg |
| `awsRegion` | Região AWS | us-east-1 |
| `createVpc` | Criar VPC (true) ou usar default | true |
| `jwtIssuerUri` | Emissor JWT (vazio = usar URL do API Gateway) | "" |
| `jwtAudience` | Audience JWT | ["fcg-cloud-platform"] |
| `ecrImageTagNotificationLambda` | Tag da imagem Lambda | latest |
| `ecrImageTagUsersApi` | Tag da imagem Users API | latest |
| `ecrImageTagGamesApi` | Tag da imagem Games API | latest |
| `ecrImageTagPaymentsApi` | Tag da imagem Payments API | latest |
| `enableOptional` | Criar stack Optional (RDS + S3) | false |
| `enableRds` | Dentro de Optional: criar RDS | false |
| `enableFrontendBucket` | Dentro de Optional: criar bucket S3 | false |

## Estrutura

```
cdk/
  bin/app.ts       # Entrada do app (ambiente único: produção)
  lib/
    shared-infra-stack.ts
    api-gateway-stack.ts
    notification-lambda-stack.ts
    ecs-apis-stack.ts
    optional-stack.ts
  cdk.json
  package.json
  tsconfig.json
```

## Relação com Terraform

O Terraform neste repositório continua disponível em `modules/` e na raiz. O CDK é a opção recomendada para novo deploy em produção.
