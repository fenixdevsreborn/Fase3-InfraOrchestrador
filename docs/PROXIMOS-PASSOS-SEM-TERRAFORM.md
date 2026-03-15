# Próximos passos — Sem Terraform (roles GitHub e ECR já prontas)

Você já tem:
- Roles do GitHub e do ECR configuradas (OIDC).
- Não vai usar Terraform.

**O que fazer agora:** criar manualmente no console AWS a infraestrutura que as aplicações usam e, em seguida, configurar os repositórios/serviços para apontar para esses recursos.

**Para este projeto, o API Gateway é obrigatório:** é a frente única HTTP para as APIs (Users, Games, Payments). A ordem abaixo coloca **ECS Fargate (passo 7)** antes do **API Gateway (passo 8)** para que a Users API já esteja no ar e o JWT Authorizer possa buscar o JWKS.

Use um **prefixo de ambiente** consistente (ex.: `fcg-prod`). Abaixo, onde aparecer `fcg-prod`, troque por seu prefixo se for diferente.

---

## Ordem recomendada

1. **ECR** — para os serviços poderem fazer push das imagens.
2. **CloudWatch Logs** — log group da Lambda de notificação e log group do API Gateway.
3. **SQS** — fila de notificação + DLQ.
4. **IAM Role da Lambda** — permissões para SQS, Logs e SES.
5. **Lambda (notificação)** — função container apontando para a imagem no ECR (a imagem só existirá depois do primeiro push do repositório NotificationLambda).
6. **Event source mapping** — SQS → Lambda.
7. **ECS Fargate** — rodar as APIs como microsserviços (containers). **Obrigatório subir pelo menos a Users API primeiro:** o API Gateway e o JWT Authorizer dependem dela (login e `/.well-known` para o gateway buscar as chaves). Depois, Games e Payments.
8. **API Gateway** — obrigatório: HTTP API (v2) como frente única; CORS, estágio; integrações HTTP para os ALBs do passo 7; **JWT Authorizer com autenticação da Users API** (passo 8.5); rotas públicas (login, .well-known) e protegidas.
9. (Opcional) **Fila SQS + Lambda de processamento de pagamentos** — para alinhar ao TC (processos assíncronos incluindo pagamentos); mesmo padrão dos passos 3–6.
10. (Opcional) **S3 frontend**, **RDS** — se for usar.

No final: configurar **variáveis nos repositórios** (ECR_REPOSITORY_NAME) e **variáveis de ambiente nas aplicações** (URL da fila, **URL base do API Gateway**, etc.).

---

## 1. ECR — Repositórios de imagens

Os workflows dos serviços fazem push para um repositório ECR cujo nome você define na variable **ECR_REPOSITORY_NAME** de cada repositório. Crie os repositórios **antes** do primeiro push.

- **Console:** ECR → Repositories → Create repository.

**Opção A — Repositórios separados por serviço (prefixo de ambiente)**  
Nomes alinhados ao que o Terraform usaria:

| Repositório ECR                 | Uso                     |
|---------------------------------|-------------------------|
| `fcg-prod-notification-lambda`  | Fase3-NotificationLambda |
| `fcg-prod-users-api`           | Fase3-UsersAPI          |
| `fcg-prod-games-api`           | Fase3-GamesAPI          |
| `fcg-prod-payments-api`        | Fase3-PaymentsAPI       |

**Opção B — Formato usado pelos workflows atuais (repositório único com path)**  
Os workflows têm default `ECR_REPOSITORY_NAME = fcg/fase03` (NotificationLambda) ou `fcg/fase03/{service_name}` (UsersAPI, GamesAPI, PaymentsAPI). No ECR, nomes com **/** são um único repositório com path (ex.: `fcg/fase03`). Crie **um** repositório:

| Repositório ECR   | Uso                                                                 |
|-------------------|---------------------------------------------------------------------|
| `fcg/fase03`      | Todos: NotificationLambda (tags `notification-lambda-latest`, etc.), UsersAPI, GamesAPI, PaymentsAPI (tags por serviço ou subpath conforme o workflow de cada repo). |

Confirme no README de cada serviço (ex.: `Fase3-UsersAPI/.github/workflows/README.md`) o formato exato: UsersAPI/GamesAPI/PaymentsAPI usam `fcg/fase03/users-api`, `fcg/fase03/games-api`, `fcg/fase03/payments-api`; NotificationLambda usa `fcg/fase03` com tags `notification-lambda-latest` e `notification-lambda-<sha>`.

- **Image tag mutability:** Mutable.
- **Scan on push:** habilitado (recomendado).
- (Opcional) **Lifecycle policy:** manter só as últimas 10 imagens para reduzir custo (ex.: rule `imageCountMoreThan` = 10, action `expire`).

Depois, em cada repositório no GitHub (UsersAPI, GamesAPI, PaymentsAPI, NotificationLambda), configure a **variable** `ECR_REPOSITORY_NAME` com o **nome** exato do repositório (ex.: `fcg-prod-users-api` na opção A, ou `fcg/fase03` / `fcg/fase03/users-api` na opção B), sem a URL completa do registry.

---

## 2. CloudWatch Logs — Log groups (Lambda e API Gateway)

**Log group da Lambda**

- **Console:** CloudWatch → Log groups → Create log group.
- **Nome:** `/aws/lambda/fcg-prod-notification` ou, se for usar o nome de função **fenix-notification-lambda** (passo 5), use `/aws/lambda/fenix-notification-lambda`.
- **Retention:** ex.: 14 days.

Esse nome será usado pela Lambda de notificação que você criar no passo 5. (A AWS também pode criar o log group automaticamente no primeiro run da função, com o nome `/aws/lambda/<nome-da-função>`.)

**Log group do API Gateway** (para access logs; use no passo 7)

- **Create log group** de novo.
- **Nome:** `/aws/apigateway/fcg-prod-http-api`
- **Retention:** 14 days.

---

## 3. SQS — Fila de notificação e DLQ

**Fila principal**

- **Console:** SQS → Create queue.
- **Type:** Standard.
- **Name:** `fcg-prod-fcg-notification-events` (ou `fcg-prod-notification-events`).
- **Visibility timeout:** 60 seconds.
- **Message retention:** 1 day (86400 seconds).
- **Receive message wait time:** 20 seconds (long polling).
- **Anote:** URL e ARN da fila (você vai usar na Lambda e nas apps que publicam mensagens).

**Dead-letter queue (recomendado)**

- **Create queue** → Standard.
- **Name:** `fcg-prod-fcg-notification-events-dlq` (ou `fcg-prod-notification-events-dlq`).
- **Message retention:** 14 days (1209600 seconds).

**Redrive policy na fila principal**

- Edite a fila principal → **Dead-letter queue** → Enable.
- **Choose queue:** selecione a DLQ criada acima.
- **Maximum receives:** 3.

---

## 4. IAM Role da Lambda de notificação

A Lambda precisa de uma role que permita: escrever no CloudWatch Logs, consumir mensagens da fila SQS e enviar e-mail (SES).

- **Console:** IAM → Roles → Create role.
- **Trusted entity:** AWS service → Lambda.
- **Role name:** ex. `fcg-prod-notification-lambda-role`.

**Permissões (custom policy ou policies anexadas):**

- **CloudWatch Logs:** `logs:CreateLogStream`, `logs:PutLogEvents` no resource do log group (use o mesmo nome da função):  
  `arn:aws:logs:REGION:ACCOUNT_ID:log-group:/aws/lambda/fcg-prod-notification:*`  
  ou, se a função for `fenix-notification-lambda`: `...log-group:/aws/lambda/fenix-notification-lambda:*`
- **SQS:** `sqs:ReceiveMessage`, `sqs:DeleteMessage`, `sqs:GetQueueAttributes` no ARN da **fila principal** que você criou.
- **SES:** `ses:SendEmail`, `ses:SendRawEmail` em `*` (ou restringir a identidades verificadas).

Crie uma **custom policy** com um JSON como o abaixo (substitua `REGION`, `ACCOUNT_ID`, o ARN da fila e, se a função for `fenix-notification-lambda`, o path do log group por `/aws/lambda/fenix-notification-lambda`):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["logs:CreateLogStream", "logs:PutLogEvents"],
      "Resource": "arn:aws:logs:REGION:ACCOUNT_ID:log-group:/aws/lambda/fcg-prod-notification:*"
    },
    {
      "Effect": "Allow",
      "Action": ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"],
      "Resource": "ARN_DA_FILA_SQS"
    },
    {
      "Effect": "Allow",
      "Action": ["ses:SendEmail", "ses:SendRawEmail"],
      "Resource": "*"
    }
  ]
}
```

Anexe essa policy à role da Lambda.

---

## 5. Lambda — Função de notificação (container)

A função usa **imagem Docker** no ECR. A imagem só existirá depois que o workflow do repositório **Fase3-NotificationLambda** rodar (push na branch configurada) e fizer o primeiro push para o ECR. Você pode criar a função antes e apontar para a tag que o workflow usar; após o primeiro build, o **workflow atualiza a função automaticamente** (`aws lambda update-function-code`) se o nome da função coincidir com o configurado no workflow.

- **Console:** Lambda → Create function.
- **Option:** Container image.
- **Name:** use **`fenix-notification-lambda`** se quiser que o workflow atual da NotificationLambda atualize a função sozinho após cada push; caso contrário, qualquer nome (ex.: `fcg-prod-notification`) e você atualiza a imagem manualmente ou ajusta o workflow.
- **Image:** URI da imagem no ECR. Exemplos:
  - Com repositório por serviço: `ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com/fcg-prod-notification-lambda:latest`
  - Com repositório único (workflow atual): `ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com/fcg/fase03:notification-lambda-latest`  
  (substitua ACCOUNT_ID e REGION; a variable `ECR_REPOSITORY_NAME` no repo NotificationLambda define o repo; a tag publicada pelo workflow é **notification-lambda-latest**).
- **Execution role:** use a role criada no passo 4.
- **Memory:** ex. 256 MB.
- **Timeout:** ex. 30 s.

**Permissão para a fila SQS invocar a Lambda**

- **Configuration** → **Permissions** → **Resource-based policy statements** → Add permission (ou via IAM):
  - **Principal:** `sqs.amazonaws.com`
  - **Action:** `lambda:InvokeFunction`
  - **Source ARN:** ARN da fila SQS principal.

Sem isso, a Lambda não será chamada quando chegarem mensagens na fila.

---

## 6. Event source mapping — SQS → Lambda

- **Console:** Lambda → sua função (ex.: `fenix-notification-lambda` ou `fcg-prod-notification`) → **Configuration** → **Triggers** → **Add trigger**.
- **Source:** SQS.
- **SQS queue:** selecione a fila principal de notificação.
- **Batch size:** 10 (ou o que fizer sentido).
- Salvar.

A partir daí, mensagens na fila disparam a Lambda automaticamente.

---

## 7. ECS Fargate — rodar as APIs (antes do API Gateway)

**Por que este passo vem antes do API Gateway?** O JWT Authorizer do API Gateway usa a **Users API** como emissor de tokens: o gateway busca o JWKS em `/.well-known/openid-configuration` e `/.well-known/jwks.json`. Essas rotas encaminham para a Users API. Por isso a **Users API precisa estar no ar (ECS Fargate) antes** de criar o API Gateway e o authorizer — senão não há de onde buscar as chaves.

Subir as APIs como **containers sempre ativos** (microsserviços): cada API é um **serviço ECS** atrás de um **Application Load Balancer (ALB)**; no passo 8, o API Gateway fará integração HTTP para cada ALB.

**Ordem sugerida:** subir **primeiro a Users API** (obrigatório para o authorizer). Em seguida, Games e Payments.

**Pré-requisitos**

- **VPC** com subnets públicas e privadas (ou use a VPC padrão da conta).
- **Imagens no ECR** já disponíveis (push pelos workflows dos repositórios UsersAPI, GamesAPI, PaymentsAPI — passo 1).
- (Opcional) **RDS** e **fila SQS** criados nos passos 2–3, se as APIs precisarem de banco e fila desde o primeiro deploy.

---

### 7.1 VPC

- **Console:** VPC → **Your VPCs** (ou use a **default VPC**).
- Se criar uma nova: **Create VPC** → nome ex.: `fcg-prod-vpc`, CIDR ex.: `10.0.0.0/16`. Crie **subnets**: pelo menos 2 **públicas** (para os ALBs) e 2 **privadas** (para as tasks ECS), em AZs diferentes. Associe uma **Internet Gateway** à VPC e configure as **route tables** (subnets públicas com rota 0.0.0.0/0 para o IGW; subnets privadas com rota para um **NAT Gateway** se as tasks precisarem de saída para internet, ex.: pull do ECR).
- **Anote** o ID da VPC e os IDs das subnets (públicas e privadas) — você usará na Task Definition e no Serviço ECS.

---

### 7.2 ECS Cluster

- **Console:** ECS → **Clusters** → **Create cluster**.
- **Cluster name:** `fcg-prod-cluster` (ou com seu prefixo).
- **Infrastructure:** AWS Fargate (serverless). **Create**.

---

### 7.3 Para cada API (Users, Games, Payments) — comece pela Users API

Repita o bloco abaixo para **Users API**, depois **Games API**, depois **Payments API**. Troque nomes e imagens conforme a tabela:

| API         | Nome do ALB (ex.)        | Target group (ex.)        | Imagem ECR (ex.)                          |
|------------|---------------------------|----------------------------|-------------------------------------------|
| Users API  | `fcg-prod-users-alb`      | `fcg-prod-users-tg`       | `ACCOUNT.dkr.ecr.REGION.amazonaws.com/fcg-prod-users-api:latest`   |
| Games API  | `fcg-prod-games-alb`      | `fcg-prod-games-tg`       | `ACCOUNT.dkr.ecr.REGION.amazonaws.com/fcg-prod-games-api:latest`  |
| Payments API | `fcg-prod-payments-alb` | `fcg-prod-payments-tg`   | `ACCOUNT.dkr.ecr.REGION.amazonaws.com/fcg-prod-payments-api:latest` |

#### 7.3.1 Task Definition

- **Console:** ECS → **Task definitions** → **Create new task definition** → **Create new revision**.
- **Task definition family:** ex. `fcg-prod-users-api` (ou `fcg-prod-games-api`, `fcg-prod-payments-api`).
- **Launch type:** AWS Fargate.
- **Task role:** crie ou use uma role que permita acesso a Secrets Manager, SQS, etc., se a API precisar. Para apenas ECR + CloudWatch Logs, a **Execution role** já cobre (acesso ao ECR para pull da imagem).
- **Task size:** **0.5 vCPU**, **1 GB** memory (mínimo Fargate; aumente se necessário).
- **Container - Add container:**
  - **Name:** ex. `users-api` (ou `games-api`, `payments-api`).
  - **Image URI:** a URI da imagem no ECR (ex.: `123456789012.dkr.ecr.us-east-1.amazonaws.com/fcg-prod-users-api:latest`). Use a mesma região e conta.
  - **Port mappings:** **Container port** = porta que a API escuta (ex.: **8080** para .NET/ASP.NET Core).
  - **Environment variables (optional):** adicione as que a aplicação precisa. Exemplos:
    - **ConnectionStrings__DefaultConnection** (ou o nome que a API usa) = connection string do RDS, se já tiver.
    - **SQS_NOTIFICATION_QUEUE_URL** = URL da fila SQS de notificação (passo 3).
    - **ApiBaseUrl** = deixe em branco ou com placeholder por enquanto; após criar o API Gateway (passo 8), atualize a task definition com a Invoke URL e faça novo deploy do serviço.
    - Para comunicação direta entre serviços na VPC (opcional): **USERS_SERVICE_URL**, **GAMES_SERVICE_URL**, **PAYMENTS_SERVICE_URL** = `http://<dns-do-alb-correspondente>` (preencha depois de criar os ALBs).
  - **Log configuration:** **awslogs**; **Log group** = crie um ex.: `/ecs/fcg-prod-users-api` (ou use o padrão `/ecs/<family>`); **Region** = sua região.
- **Create**.

#### 7.3.2 Application Load Balancer (ALB)

- **Console:** EC2 → **Load Balancing** → **Load Balancers** → **Create Load Balancer**.
- Escolha **Application Load Balancer**.
- **Name:** ex. `fcg-prod-users-alb` (ou `fcg-prod-games-alb`, `fcg-prod-payments-alb`).
- **Scheme:** **Internet-facing** (para o API Gateway chamar pela internet) ou **Internal** (se for usar VPC Link no passo 8; mais avançado).
- **Network mapping:** selecione a **VPC** e as **subnets** (use as **públicas** para internet-facing).
- **Security groups:** crie um novo ou use existente. **Inbound rules:** permitir **HTTP (80)** e, se usar HTTPS, **HTTPS (443)** de **0.0.0.0/0** (ou restrinja ao prefixo do API Gateway se souber; para simplificar, 0.0.0.0/0).
- **Listeners and routing:** **Add listener** → **HTTP :80** (ou HTTPS :443 se tiver certificado). **Default action:** **Forward to** → crie um **New target group**:
  - **Target type:** IP (para Fargate) ou **Instance** (se usasse EC2).
  - **Target group name:** ex. `fcg-prod-users-tg`.
  - **Protocol:** HTTP, **Port:** **8080** (a porta do container).
  - **VPC:** mesma da ALB. **Health check path:** ex. `/health` ou `/` (conforme o que a API expõe).
- **Create load balancer**.
- **Anote o DNS name** do ALB (ex.: `fcg-prod-users-alb-1234567890.us-east-1.elb.amazonaws.com`) — você usará no **passo 8.8** para criar a integração HTTP no API Gateway.

#### 7.3.3 Security group das tasks

- **Console:** EC2 → **Security Groups** → **Create security group**.
- **Name:** ex. `fcg-prod-users-api-sg` (ou `fcg-prod-games-api-sg`, etc.).
- **VPC:** mesma usada no cluster e no ALB.
- **Inbound rules:** **Add rule** → **Type:** Custom TCP; **Port:** **8080**; **Source:** o **security group do ALB** (para que só o ALB possa acessar as tasks). **Save**.
- **Outbound:** deixe o default (0.0.0.0/0) se as tasks precisarem acessar internet (ECR, RDS em outra subnet, SQS, etc.).

#### 7.3.4 Serviço ECS

- **Console:** ECS → **Clusters** → `fcg-prod-cluster` → **Services** → **Create**.
- **Compute options:** **Launch type** = **Fargate**.
- **Task Definition:** família e revisão criadas em 7.3.1 (ex.: `fcg-prod-users-api:latest`).
- **Service name:** ex. `fcg-prod-users-api` (ou `fcg-prod-games-api`, etc.).
- **Number of tasks:** ex. **1** (para demo; aumente para alta disponibilidade).
- **Networking:**
  - **VPC:** a mesma do passo 7.1.
  - **Subnets:** selecione as **subnets privadas** (para as tasks não ficarem expostas diretamente).
  - **Security group:** o criado em 7.3.3 (ex.: `fcg-prod-users-api-sg`).
  - **Public IP:** **Turn off** (tasks em subnets privadas; se não tiver NAT Gateway, ative **Turn on** e use subnets públicas para as tasks poderem fazer pull do ECR).
- **Load balancing:** **Load balancer type** = **Application Load Balancer**. Selecione o ALB e o **target group** criados em 7.3.2. **Container to load balance:** selecione o container (ex.: `users-api`) e a porta **8080**.
- **Create**.

Aguarde o serviço estabilizar (task em estado **RUNNING** e target group **healthy**). Repita **7.3.1 a 7.3.4** para **Games API** e **Payments API**.

---

### 7.4 Variáveis de ambiente e comunicação entre microsserviços

- **ApiBaseUrl:** depois que o **passo 8 (API Gateway)** estiver concluído, edite cada **Task Definition** (nova revisão), adicione ou atualize a variável **ApiBaseUrl** = Invoke URL do API Gateway (ex.: `https://xxxxxxxxxx.execute-api.us-east-1.amazonaws.com`). Em seguida, **Update** o **Service** correspondente para usar a nova revisão da task definition (ECS → Service → Update → nova revisão → Deploy). Assim as chamadas entre microsserviços podem usar o gateway (ex.: Games API chama `ApiBaseUrl/users/me`).
- **Comunicação direta na VPC (opcional):** se preferir que Games chame Users sem passar pelo API Gateway, configure nas task definitions variáveis como **USERS_SERVICE_URL** = `http://fcg-prod-users-alb-xxxxx.us-east-1.elb.amazonaws.com`, **GAMES_SERVICE_URL**, **PAYMENTS_SERVICE_URL**, e use-as no código das APIs.

---

### 7.5 Resumo e próximo passo

- **Resumo:** você deve ter 1 cluster, 3 task definitions, 3 ALBs, 3 target groups, 3 security groups (ALB + tasks por API), 3 serviços ECS. Cada ALB com um **DNS name** anotado.
- **Próximo:** siga para o **passo 8 — API Gateway**. Lá você criará a API, o JWT Authorizer (que dependerá da Users API já estar respondendo em `/.well-known`) e as integrações/rotas apontando para os ALBs (passo 8.8).

Detalhes das integrações HTTP e rotas no API Gateway (path override, rotas públicas/protegidas): **passo 8.8**.

---

## 8. API Gateway (obrigatório no projeto)

O projeto exige um **API Gateway HTTP API (v2)** como frente única para as APIs (Users, Games, Payments). Os backends (ALBs) já foram criados no **passo 7 (ECS Fargate)**; aqui você cria a API, as integrações HTTP para cada ALB, o JWT Authorizer e as rotas.

**Relação entre API Gateway, fila SQS e Lambda de notificação**

- A **fila SQS** e a **Lambda de notificação** não são “recursos dentro” do API Gateway: a Lambda é acionada **pela fila** (trigger SQS → Lambda). O API Gateway é a frente HTTP para chamadas síncronas (Users, Games, Payments).
- Para o fluxo de notificação ficar **também** atrás do mesmo API: crie uma **rota** (ex.: `POST /notify`) cuja integração seja uma **Lambda de enqueue** que envia a mensagem para a fila SQS. O cliente chama o API Gateway → essa Lambda grava na fila → a fila dispara a **Lambda de notificação** (a que processa e envia e-mail). Assim a “entrada” de notificação fica no API Gateway; a fila e a Lambda de notificação continuam sendo o fluxo assíncrono (passo 8.7).

### 8.1 Criar a API

- **Console:** API Gateway → **Create API**.
- Escolha **HTTP API** (não REST API) → **Build**.
- **API name:** `fcg-prod-api`
- **Description:** FCG Cloud Platform HTTP API (opcional).
- **CORS:** marque **Configure CORS** e use:
  - **Access-Control-Allow-Origin:** `*` (ou liste origens específicas).
  - **Access-Control-Allow-Headers:** `authorization`, `content-type`, `x-correlation-id`, `x-api-key`.
  - **Access-Control-Allow-Methods:** GET, POST, PUT, PATCH, DELETE, OPTIONS.
  - **Access-Control-Max-Age:** 300.
- **Next** → **Create**.

### 8.2 Integração padrão (placeholder)

Enquanto as rotas reais (Users, Games, Payments) não forem criadas, use uma integração HTTP de exemplo para a rota `$default`:

- Na API criada: **Integrations** → **Create integration**.
- **Integration type:** HTTP endpoint (ou “HTTP”).
- **URL:** `https://httpbin.org/anything` (placeholder).
- **Method:** ANY (ou GET).
- **Integration name:** ex. `default-http`.
- **Create**.

### 8.3 Rota $default

- **Routes** → **Create**.
- **Method:** `ANY` (ou **GET** se o console não tiver ANY).
- **Path:** `$default` (rota catch-all; se o console não aceitar, crie uma rota como `/` ou `/{proxy+}` e depois ajuste).
- **Integration:** selecione a integração criada acima (ex.: `default-http`).
- **Create**.

### 8.4 Stage e Invoke URL

- **Stages** → o API Gateway HTTP API já cria um stage **$default**.
- Abra o stage **$default** e anote a **Invoke URL** (ex.: `https://xxxxxxxxxx.execute-api.us-east-1.amazonaws.com`).  
  Essa URL é a **base** que as aplicações e o frontend devem usar (ex.: `API_GATEWAY_URL` ou `ApiBaseUrl`). Use essa mesma URL como **Issuer** do JWT no passo 8.5.

### 8.5 JWT Authorizer — autenticação da Users API (obrigatório para este projeto)

A autenticação do API Gateway deve usar a **Users API** como emissor de tokens (login na própria plataforma, sem Cognito). Configure o JWT Authorizer **antes** de criar as rotas de Users, Games e Payments, para já associar o authorizer às rotas protegidas.

**No console:** API Gateway → sua API → **Authorization** (ou **Authorizers**) → **Create authorizer**.

| Campo | Valor |
|-------|--------|
| **Name** | `fcg-jwt-users` |
| **Type** | JWT |
| **Identity source** | `$request.header.Authorization` |
| **Issuer** | **Invoke URL** do API Gateway (ex.: `https://xxxxxxxxxx.execute-api.us-east-1.amazonaws.com`), **sem** barra final. Deve ser igual ao claim `iss` que a Users API coloca no token ao fazer login. |
| **Audience** | `fcg-cloud-platform` (ou o valor configurado na Users API ao emitir o token) |

**Na Users API (variável de ambiente / config):** configure o emissor do token (`iss`) para ser exatamente essa **Invoke URL** do API Gateway, para o gateway aceitar o token. A Users API deve expor `/.well-known/openid-configuration` e `/.well-known/jwks.json` (OIDC discovery e JWKS); o API Gateway usa o Issuer para buscar as chaves e validar a assinatura.

**Rotas públicas (sem authorizer):** não associe o JWT authorizer a estas rotas — deixe como "NONE" ou sem authorizer:
- **POST** `/auth/login` (ou `/users/auth/login` conforme o path que encaminha para a Users API) — obtenção do token.
- **GET** `/.well-known/openid-configuration` e **GET** `/.well-known/jwks.json` — discovery OIDC e JWKS (encaminhe para a Users API).
- **POST** `/notify` (se existir) — conforme necessidade.

**Rotas protegidas (com authorizer):** ao criar as rotas de Users, Games e Payments (passo 8.8 ou "Depois do API Gateway"), associe o authorizer **fcg-jwt-users** a todas as rotas que exigem autenticação (ex.: `/users/me`, `/users/{proxy+}`, `/games`, `/games/{proxy+}`, `/payments`, `/payments/{proxy+}`). Assim apenas requisições com `Authorization: Bearer <token>` válido (emitido pela Users API) passam.

Configuração detalhada (issuer, audience, rotas por método, scopes): ver [API-GATEWAY-JWT-AUTHORIZER.md](API-GATEWAY-JWT-AUTHORIZER.md).

### 8.6 Access logs (opcional mas recomendado)

- **Stages** → **$default** → **Logs/Tracing**.
- **CloudWatch Logs:** Enable.
- **Log group:** selecione ou informe o ARN do log group criado no passo 2: `/aws/apigateway/fcg-prod-http-api`.
- Para o API Gateway poder escrever nesse log group, é necessário uma **resource policy** no CloudWatch. No CloudWatch → **Log groups** → selecione `/aws/apigateway/fcg-prod-http-api` → **Resource policy** (ou use IAM): adicione uma policy que permita `logs:CreateLogDelivery` com **Principal** `apigateway.amazonaws.com` no ARN do log group (formato `arn:aws:logs:REGION:ACCOUNT_ID:log-group:/aws/apigateway/fcg-prod-http-api:*`). No console, isso às vezes é configurado ao marcar “Enable” nos access logs do stage.

### 8.7 Rota de notificação no API Gateway (fila + Lambda no mesmo API)

Para que “enviar notificação” seja um endpoint HTTP do mesmo API Gateway (em vez de só as aplicações enviarem direto para a URL da fila SQS), faça o seguinte.

1. **Lambda de enqueue (só envia para SQS)**  
   Crie uma **segunda** função Lambda (ex.: nome `fcg-prod-notify-enqueue`) que:
   - Recebe o evento do API Gateway (body, headers).
   - Envia uma mensagem para a **fila SQS** (URL da fila em variável de ambiente) com `SendMessage`.
   - Retorna 202 ou 200 com um JSON de confirmação.  
   Essa Lambda precisa de uma role com permissão **sqs:SendMessage** no ARN da fila de notificação e **logs:CreateLogStream**, **logs:PutLogEvents** no log group dela.

2. **Integração no API Gateway**  
   No mesmo HTTP API (`fcg-prod-api`): **Integrations** → **Create integration** → **Lambda** → selecione a Lambda `fcg-prod-notify-enqueue`. Payload version 2.0.

3. **Rota no API Gateway**  
   **Routes** → **Create** → por exemplo:
   - **Method:** `POST`
   - **Path:** `/notify` (ou `/notifications`)
   - **Integration:** a integração da Lambda de enqueue criada acima.

4. **Permissão para o API Gateway invocar a Lambda**  
   Na Lambda `fcg-prod-notify-enqueue`, adicione uma **resource-based policy** permitindo `lambda:InvokeFunction` com **Principal** `apigateway.amazonaws.com` (ou o ARN do API Gateway / do stage, conforme a documentação AWS).

Fluxo final: **Cliente → API Gateway (POST /notify) → Lambda enqueue → SQS → Lambda de notificação** (a do passo 5). A fila e a Lambda de notificação passam a ser “parte” do desenho do API Gateway no sentido de que a entrada HTTP está no mesmo API.

### Depois do API Gateway

- **Anote a Invoke URL** e configure nas aplicações (variável de ambiente **ApiBaseUrl** ou equivalente) e no frontend.
- Quando for conectar as APIs reais (Users, Games, Payments), crie **novas integrações** (HTTP backend ou Lambda) e **novas rotas** apontando para as URLs ou Lambdas corretas. **Autenticação:** deixe **rotas públicas** (login, `/.well-known/*`) **sem** JWT authorizer; nas **rotas protegidas** (ex.: `/users/me`, `/users/{proxy+}`, `/games`, `/payments`), associe o authorizer **fcg-jwt-users** (passo 8.5). As APIs já rodam no **passo 7 (ECS Fargate)**; as integrações HTTP no gateway apontam para os ALBs do passo 7 — ver **8.8**.
- Se criou a rota **POST /notify**, o frontend ou outras apps podem enviar notificações via `ApiBaseUrl/notify` em vez de precisar da URL da fila SQS.

### 8.8 Conectar os backends do passo 7 (integrações e rotas no API Gateway)

As APIs já estão no ar no **passo 7 (ECS Fargate)**; cada uma tem um ALB. Use os **DNS names** dos ALBs que você anotou no passo 7.

**Integrações e rotas no API Gateway**
   - **Integrations** → Create integration → **HTTP**.
     - Users: URL = `http://fcg-prod-users-alb-xxxxx.us-east-1.elb.amazonaws.com` (ou `https://` se configurou certificado no ALB). Integration name ex.: `users-backend`.
     - Repetir para Games e Payments com seus ALB URLs.
   - **Routes** → Create (respeitando autenticação da Users API — passo 8.5):
     - **Rotas públicas (sem authorizer):** `POST /auth/login` (ou `/users/auth/login` → Users backend), `GET /.well-known/openid-configuration`, `GET /.well-known/jwks.json` (→ Users backend). Não associe o JWT authorizer a essas rotas.
     - **Rotas protegidas (com authorizer fcg-jwt-users):** Method `ANY`, Path `/users`, Integration = `users-backend`, **Authorization** = `fcg-jwt-users`; Method `ANY`, Path `/users/{proxy+}`, Integration = `users-backend`, **Authorization** = `fcg-jwt-users`. Idem para `/games`, `/games/{proxy+}` (integration Games) e `/payments`, `/payments/{proxy+}` (integration Payments), sempre com authorizer.
     - Assim o login e o discovery ficam abertos; o restante exige token emitido pela Users API.
   - Se a API espera o path **sem** o prefixo (ex.: Users espera `/auth/login` e não `/users/auth/login`), use **Path override** na integração: em "Additional settings" da integração HTTP, defina o path override para reescrever (ex.: para `/users/{proxy+}` enviar ao backend como `/{proxy}`). Assim o backend recebe `/auth/login` quando o cliente chama `ApiBaseUrl/users/auth/login`.

**Comunicação entre microsserviços**
   - **Opção A — Via API Gateway:** Em cada container, configure **ApiBaseUrl** = Invoke URL do API Gateway. Quando a Games API precisar chamar a Users API, faça `GET ApiBaseUrl/users/me` (ou o path que você definiu). Todas as chamadas entre serviços passam pelo API Gateway (um único ponto de auth, logs e throttling).
   - **Opção B — Direto na VPC (menor latência):** Configure em cada app variáveis como **USERS_SERVICE_URL** = `http://fcg-prod-users-alb-xxxxx...`, **GAMES_SERVICE_URL**, **PAYMENTS_SERVICE_URL**. Assim Games chama Users em `USERS_SERVICE_URL/me` sem passar pelo API Gateway. Exige que os ALBs sejam acessíveis de dentro da VPC (já são, se as tasks estão na mesma VPC). Para não expor ALBs na internet, use ALBs internos (subnets privadas) e VPC Link no API Gateway (HTTP API suporta private integration com VPC Link).

**Resumo (passo 7 + 8.8)**

- **Rodar as imagens:** passo 7 (ECS Fargate) — cluster, serviço + ALB por API.
- **Incluir no API Gateway (8.8):** integrações HTTP para cada ALB do passo 7; rotas públicas (login, .well-known) e protegidas (com authorizer 8.5).
- **Comportamento entre microsserviços:** chamadas via ApiBaseUrl (após criar o gateway) ou URLs internas dos ALBs.

---

## 9. (Opcional) Fila + Lambda de processamento de pagamentos (alinhamento ao TC)

O TC Fase 3 pede funções serverless para processos assíncronos, **incluindo processamento de pagamentos**. Para alinhar:

- **Fila SQS:** crie uma fila ex.: `fcg-prod-payment-events` (e opcionalmente DLQ).
- **Lambda de processamento:** função que consome mensagens dessa fila (atualiza status de pagamento, notifica, etc.); event source mapping SQS → Lambda.
- **Quem enfileira:** a API de Pagamentos (ou a rota no API Gateway) grava eventos na fila; a Lambda é acionada pelo **gatilho em evento** (mensagem na fila).

Assim você terá dois fluxos assíncronos com gatilhos: **notificações** (SQS notificação → Lambda notificação) e **pagamentos** (SQS pagamentos → Lambda pagamentos). A configuração no console segue o mesmo padrão dos passos 3–6 (fila, role, Lambda, event source mapping).

## 10. (Opcional) S3 frontend, RDS

- **S3 frontend:** se tiver frontend estático, crie um bucket, configure como website (index/error) e, se for acessar pelo browser, use CloudFront na frente com OAC e origem no S3.
- **RDS:** se as APIs usarem PostgreSQL, crie a instância RDS (VPC, security groups, subnets) e anote o endpoint. As aplicações precisarão da connection string (host, port, database, user, password).

---

## Configuração nos repositórios e nas aplicações

**GitHub (cada serviço que faz push para ECR)**

- **Variable** `ECR_REPOSITORY_NAME`: nome exato do repositório ECR (ex.: `fcg-prod-notification-lambda`, `fcg-prod-users-api` na opção de repos separados; ou `fcg/fase03`, `fcg/fase03/users-api` etc. na opção usada pelos workflows atuais).
- **Variable** `AWS_REGION`: mesma região dos recursos (ex.: `us-east-1`).
- **Variable** `ORCHESTRATOR_REPO` e secret **`ORCHESTRATOR_REPO_TOKEN`**: usados pelo workflow para disparar o orquestrador via `repository_dispatch` (deploy-request) após o push; se não usar Terraform/orquestrador, o push e a atualização da Lambda (quando o nome é `fenix-notification-lambda`) já funcionam sem esses valores.

**Aplicações (variáveis de ambiente / config)**

- **URL da fila SQS:** as apps que publicam eventos de notificação precisam da **URL** da fila SQS (ex.: `https://sqs.REGION.amazonaws.com/ACCOUNT_ID/fila-name`). Configure na aplicação (variável de ambiente ou appsettings).
- **API Gateway (obrigatório):** configure a **URL base** do API Gateway (Invoke URL do stage `$default`) em todas as apps e no frontend que consomem as APIs (ex.: variável `ApiBaseUrl` ou `API_GATEWAY_URL`).
- **Banco:** se usar RDS, configure connection string (host, port, database, user, password) nas APIs que acessam o PostgreSQL.

---

## Resumo rápido

| Já feito        | Próximo (ordem) |
|-----------------|------------------|
| Roles GitHub + ECR | 1. ECR → 2. Log groups → 3. SQS + DLQ → 4. IAM role Lambda → 5. Lambda notificação → 6. Trigger SQS → **7. ECS Fargate** (Users API primeiro, depois Games/Payments) → **8. API Gateway** (integrações HTTP para os ALBs do 7, JWT com Users API) → 9. (Opc.) SQS + Lambda pagamentos → 10. (Opc.) S3, RDS. Depois: `ECR_REPOSITORY_NAME` e env vars (fila, API Gateway URL, DB). Para alinhar ao TC: considerar passo 9, X-Ray, audit logs e desenho de arquitetura (ver seção “Alinhamento com o Tech Challenge”). |

Depois do primeiro **push** no repositório **Fase3-NotificationLambda** (branch que dispara o workflow), a imagem estará no ECR. Se a Lambda tiver o nome **fenix-notification-lambda**, o workflow já executa `aws lambda update-function-code` após o push, e a função passará a usar a nova imagem automaticamente (tag **notification-lambda-latest** no repositório definido por `ECR_REPOSITORY_NAME`). Se você criou a Lambda com outro nome ou outro repositório/tag, atualize a configuração da função manualmente para a URI correta.

Para dúvidas sobre nomes e políticas exatas, os módulos Terraform em `modules/` servem de referência (notification-lambda, sqs, ecr, cloudwatch-logs).

---

## Alinhamento com o Tech Challenge — Fase 3 (TC 10NETT)

Este trecho mapeia o guia ao enunciado do **Tech Challenge Fase 3** (FIAP Cloud Games) e sugere melhorias para deixar o fluxo e a infraestrutura totalmente alinhados ao documento do desafio.

### O que já está alinhado

| Requisito do TC Fase 3 | Como este guia atende |
|------------------------|------------------------|
| **Três microsserviços** (Usuários, Jogos, Pagamentos) | ECR e APIs separadas (users-api, games-api, payments-api); todas atrás do API Gateway. |
| **Funções serverless para processos assíncronos (envio de notificações)** | Lambda de notificação acionada por **gatilho em evento** (SQS → Lambda); fila + DLQ. |
| **Gatilhos em eventos para acionar funções automaticamente** | Event source mapping SQS → Lambda (passo 6); mensagem na fila = evento que dispara a Lambda. |
| **API Gateway para gerenciar requisições dos microsserviços** | API Gateway HTTP API (v2) como frente única; rotas para Users, Games, Payments; rota POST /notify (passo 8.7). |
| **Segurança entre acessos** | JWT Authorizer com **autenticação da Users API** (passo 8.5); rotas públicas (login, .well-known) e protegidas; CORS e headers configurados. |
| **Logs** | CloudWatch Log groups para Lambda e API Gateway; access logs do API. |

### Fluxo de comunicação (resumo para documentação/entregáveis)

Para o **fluxo de comunicação dos microsserviços** e o **desenho de arquitetura** pedidos nos entregáveis, você pode descrever assim:

- **Síncrono (via API Gateway):** Cliente → API Gateway → microsserviço (Users / Games / Payments), cada um em sua rota (ex.: `/users`, `/games`, `/payments`).
- **Assíncrono — notificações:** Cliente ou microsserviço → API Gateway `POST /notify` → Lambda enqueue → **SQS** → **Lambda de notificação** (envio de e-mail). Ou: microsserviço envia direto para a URL da fila SQS; a fila dispara a Lambda (gatilho em evento).
- **Assíncrono — pagamentos (recomendado para alinhar ao TC):** ver “Processamento de pagamentos” abaixo.

### Melhorias sugeridas para alinhar 100% ao TC

1. **Processamento de pagamentos como serverless assíncrono**  
   O TC pede funções serverless para processos assíncronos, **incluindo processamento de pagamentos**. Hoje o guia cobre só **notificações**. Sugestão:
   - Criar uma **segunda fila SQS** (ex.: `fcg-prod-payment-events`) e uma **Lambda de processamento de pagamentos** (ou usar a Payments API para enfileirar e uma Lambda para consumir).
   - Fluxo: API Gateway (ex.: `POST /payments`) ou Games API grava mensagem na fila de pagamentos → **gatilho SQS** → Lambda processa pagamento (atualiza status, notifica, etc.). Assim “processamento de pagamentos” fica explícito como processo assíncrono com gatilho em evento, igual às notificações.
   - No guia: o **passo 8** descreve a fila SQS e a Lambda de processamento de pagamentos; use o mesmo padrão dos passos 3–6 e, se quiser entrada HTTP única, crie uma rota no API Gateway (ex.: POST /payments/process) que enfileira na fila de pagamentos.

2. **Event sourcing / audit logs**  
   O TC exige “event sourcing ou equivalente (temporal tables, audit logs)” para registrar mudanças no estado do sistema. O guia não cita isso. Sugestão:
   - Incluir um passo ou nota: **audit logs** (ex.: tabela de eventos no RDS, DynamoDB ou CloudWatch Logs com formato estruturado) onde cada microsserviço registra eventos relevantes (usuário criado, jogo comprado, pagamento processado, notificação enviada).
   - Ou **temporal tables** no PostgreSQL (se usar RDS) para histórico de mudanças nas tabelas críticas.
   - Na documentação/README: descrever onde os eventos de negócio são persistidos e como consultar o histórico.

3. **Rastreamento distribuído (Traces)**  
   O TC pede “observabilidade com logs e **rastreamento distribuído (Traces)**”. O guia fala de CloudWatch Logs, mas não de traces. Sugestão:
   - Habilitar **AWS X-Ray** no API Gateway (stage → Logs/Tracing → Enable X-Ray tracing) e nas Lambdas (configuração da função → Enable Active tracing). Assim as requisições que passam pelo API Gateway e pelas Lambdas geram traces distribuídos no X-Ray.
   - No guia: adicionar um item em “Depois do API Gateway” ou em “Observabilidade”: ativar X-Ray no API Gateway e nas funções Lambda usadas no fluxo.

4. **Segurança (JWT)**  
   O TC diz “Garantir segurança entre os acessos para os microsserviços”; Neste guia o JWT já está obrigatório (passo 8.5, Users API como emissor):
   - **JWT Authorizer** com Users API como emissor; rotas públicas (login, .well-known) sem authorizer; demais rotas exigem token emitido pela Users API. Documentar no README a proteção entre microsserviços.

5. **Desenho de arquitetura (entregável)**  
   O TC pede “Desenho de arquitetura representando o fluxo de funcionamento”. Sugestão:
   - Incluir no README ou na documentação um **diagrama** (Miro, draw.io, ou figura) com: Cliente → API Gateway → microsserviços (Users, Games, Payments); fluxo assíncrono: API Gateway ou app → SQS (notificação) → Lambda notificação; e, se implementar, SQS (pagamentos) → Lambda pagamentos; indicar também CloudWatch Logs e, se usar, X-Ray.

6. **Resumo no próprio guia**  
   No início ou no resumo rápido, deixar explícito:
   - **Microsserviços:** 3 (Users, Games, Payments) atrás do API Gateway.
   - **Serverless assíncrono:** notificações (SQS → Lambda) e, sugerido, pagamentos (SQS → Lambda).
   - **Gatilhos em eventos:** SQS como evento que aciona as Lambdas.
   - **API Gateway:** gerencia e protege todas as requisições HTTP dos microsserviços (e opcionalmente a entrada de notificação/pagamento).

Com essas melhorias, o fluxo (incluindo SQS e Lambdas) fica alinhado ao documento do TC Fase 3 e aos entregáveis (fluxo de comunicação, desenho de arquitetura, observabilidade e event sourcing/audit).
