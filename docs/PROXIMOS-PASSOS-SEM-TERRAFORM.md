# Próximos passos — Sem Terraform (roles GitHub e ECR já prontas)

Você já tem:
- Roles do GitHub e do ECR configuradas (OIDC).
- Não vai usar Terraform.

**O que fazer agora:** criar manualmente no console AWS a infraestrutura que as aplicações usam e, em seguida, configurar os repositórios/serviços para apontar para esses recursos.

**Para este projeto, o API Gateway é obrigatório:** é a frente única HTTP para as APIs (Users, Games, Payments). A ordem abaixo já inclui o API Gateway como passo 7.

Use um **prefixo de ambiente** consistente (ex.: `fcg-prod`). Abaixo, onde aparecer `fcg-prod`, troque por seu prefixo se for diferente.

---

## Ordem recomendada

1. **ECR** — para os serviços poderem fazer push das imagens.
2. **CloudWatch Logs** — log group da Lambda de notificação e log group do API Gateway.
3. **SQS** — fila de notificação + DLQ.
4. **IAM Role da Lambda** — permissões para SQS, Logs e SES.
5. **Lambda (notificação)** — função container apontando para a imagem no ECR (a imagem só existirá depois do primeiro push do repositório NotificationLambda).
6. **Event source mapping** — SQS → Lambda.
7. **API Gateway** — obrigatório no projeto: HTTP API (v2) como frente única para as APIs (Users, Games, Payments); CORS, estágio e rota default; opcionalmente JWT authorizer.
8. (Opcional) **Fila SQS + Lambda de processamento de pagamentos** — para alinhar ao TC (processos assíncronos incluindo pagamentos); mesmo padrão dos passos 3–6.
9. (Opcional) **S3 frontend**, **RDS** — se for usar.

No final: configurar **variáveis nos repositórios** (ECR_REPOSITORY_NAME) e **variáveis de ambiente nas aplicações** (URL da fila, **URL base do API Gateway**, etc.).

---

## 1. ECR — Repositórios de imagens

Os workflows dos serviços fazem push para um repositório ECR cujo nome você define na variable **ECR_REPOSITORY_NAME** de cada repositório. Crie os repositórios **antes** do primeiro push.

- **Console:** ECR → Repositories → Create repository.

Crie um repositório para cada serviço (nomes sugeridos, alinhados ao que o Terraform usaria):

| Repositório ECR              | Uso                |
|-----------------------------|--------------------|
| `fcg-prod-notification-lambda` | Fase3-NotificationLambda |
| `fcg-prod-users-api`        | Fase3-UsersAPI     |
| `fcg-prod-games-api`        | Fase3-GamesAPI     |
| `fcg-prod-payments-api`     | Fase3-PaymentsAPI  |

- **Image tag mutability:** Mutable.
- **Scan on push:** habilitado (recomendado).
- (Opcional) **Lifecycle policy:** manter só as últimas 10 imagens para reduzir custo (ex.: rule `imageCountMoreThan` = 10, action `expire`).

Depois, em cada repositório no GitHub (UsersAPI, GamesAPI, PaymentsAPI, NotificationLambda), configure a **variable** `ECR_REPOSITORY_NAME` com o **nome** exato do repositório (ex.: `fcg-prod-users-api`), sem a URL completa.

---

## 2. CloudWatch Logs — Log groups (Lambda e API Gateway)

**Log group da Lambda**

- **Console:** CloudWatch → Log groups → Create log group.
- **Nome:** `/aws/lambda/fcg-prod-notification`
- **Retention:** ex.: 14 days.

Esse nome será usado pela Lambda de notificação que você criar no passo 5.

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

- **CloudWatch Logs:** `logs:CreateLogStream`, `logs:PutLogEvents` no resource do log group:  
  `arn:aws:logs:REGION:ACCOUNT_ID:log-group:/aws/lambda/fcg-prod-notification:*`
- **SQS:** `sqs:ReceiveMessage`, `sqs:DeleteMessage`, `sqs:GetQueueAttributes` no ARN da **fila principal** que você criou.
- **SES:** `ses:SendEmail`, `ses:SendRawEmail` em `*` (ou restringir a identidades verificadas).

Crie uma **custom policy** com um JSON como o abaixo (substitua `REGION`, `ACCOUNT_ID` e o ARN da fila):

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

A função usa **imagem Docker** no ECR. A imagem só existirá depois que o workflow do repositório **Fase3-NotificationLambda** rodar (push na branch configurada) e fizer o primeiro push para o ECR. Você pode criar a função antes e apontar para a tag `latest`; após o primeiro build, atualize a função para usar a nova imagem se necessário.

- **Console:** Lambda → Create function.
- **Option:** Container image.
- **Name:** `fcg-prod-notification`.
- **Image:** URI da imagem no ECR, ex.:  
  `ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com/fcg-prod-notification-lambda:latest`  
  (substitua ACCOUNT_ID e REGION; use a tag que o workflow publicar, ex.: `latest` ou o SHA do commit).
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

- **Console:** Lambda → sua função `fcg-prod-notification` → **Configuration** → **Triggers** → **Add trigger**.
- **Source:** SQS.
- **SQS queue:** selecione a fila principal de notificação.
- **Batch size:** 10 (ou o que fizer sentido).
- Salvar.

A partir daí, mensagens na fila disparam a Lambda automaticamente.

---

## 7. API Gateway (obrigatório no projeto)

O projeto exige um **API Gateway HTTP API (v2)** como frente única para as APIs (Users, Games, Payments). Configure conforme abaixo, alinhado ao módulo Terraform do orquestrador.

**Relação entre API Gateway, fila SQS e Lambda de notificação**

- A **fila SQS** e a **Lambda de notificação** não são “recursos dentro” do API Gateway: a Lambda é acionada **pela fila** (trigger SQS → Lambda). O API Gateway é a frente HTTP para chamadas síncronas (Users, Games, Payments).
- Para o fluxo de notificação ficar **também** atrás do mesmo API: crie uma **rota** (ex.: `POST /notify`) cuja integração seja uma **Lambda de enqueue** que envia a mensagem para a fila SQS. O cliente chama o API Gateway → essa Lambda grava na fila → a fila dispara a **Lambda de notificação** (a que processa e envia e-mail). Assim a “entrada” de notificação fica no API Gateway; a fila e a Lambda de notificação continuam sendo o fluxo assíncrono (passo 7.7).

### 7.1 Criar a API

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

### 7.2 Integração padrão (placeholder)

Enquanto as rotas reais (Users, Games, Payments) não forem criadas, use uma integração HTTP de exemplo para a rota `$default`:

- Na API criada: **Integrations** → **Create integration**.
- **Integration type:** HTTP endpoint (ou “HTTP”).
- **URL:** `https://httpbin.org/anything` (placeholder).
- **Method:** ANY (ou GET).
- **Integration name:** ex. `default-http`.
- **Create**.

### 7.3 Rota $default

- **Routes** → **Create**.
- **Method:** `ANY` (ou **GET** se o console não tiver ANY).
- **Path:** `$default` (rota catch-all; se o console não aceitar, crie uma rota como `/` ou `/{proxy+}` e depois ajuste).
- **Integration:** selecione a integração criada acima (ex.: `default-http`).
- **Create**.

### 7.4 Stage e Invoke URL

- **Stages** → o API Gateway HTTP API já cria um stage **$default**.
- Abra o stage **$default** e anote a **Invoke URL** (ex.: `https://xxxxxxxxxx.execute-api.us-east-1.amazonaws.com`).  
  Essa URL é a **base** que as aplicações e o frontend devem usar (ex.: `API_GATEWAY_URL` ou `ApiBaseUrl`).

### 7.5 Access logs (opcional mas recomendado)

- **Stages** → **$default** → **Logs/Tracing**.
- **CloudWatch Logs:** Enable.
- **Log group:** selecione ou informe o ARN do log group criado no passo 2: `/aws/apigateway/fcg-prod-http-api`.
- Para o API Gateway poder escrever nesse log group, é necessário uma **resource policy** no CloudWatch. No CloudWatch → **Log groups** → selecione `/aws/apigateway/fcg-prod-http-api` → **Resource policy** (ou use IAM): adicione uma policy que permita `logs:CreateLogDelivery` com **Principal** `apigateway.amazonaws.com` no ARN do log group (formato `arn:aws:logs:REGION:ACCOUNT_ID:log-group:/aws/apigateway/fcg-prod-http-api:*`). No console, isso às vezes é configurado ao marcar “Enable” nos access logs do stage.

### 7.6 JWT Authorizer (opcional)

Se o projeto usar autenticação JWT (ex.: Cognito ou sua Users API como emissor):

- **Authorization** (ou **Authorizers**) → **Create authorizer**.
- **Type:** JWT.
- **Identity source:** `$request.header.Authorization`.
- **Issuer URI:** URL do emissor (ex.: Cognito User Pool ou `https://sua-users-api/.well-known/openid-configuration`).
- **Audience:** ex.: `fcg-cloud-platform` (ou a lista que as APIs esperam).

Depois, associe o authorizer às rotas que precisam de proteção (nas rotas que você criar para Users, Games, Payments).

### 7.7 Rota de notificação no API Gateway (fila + Lambda no mesmo API)

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
- Quando for conectar as APIs reais (Users, Games, Payments), crie **novas integrações** (HTTP backend ou Lambda) e **novas rotas** (ex.: `GET /users`, `POST /games`) apontando para as URLs ou Lambdas corretas.
- Se criou a rota **POST /notify**, o frontend ou outras apps podem enviar notificações via `ApiBaseUrl/notify` em vez de precisar da URL da fila SQS.

---

## 8. (Opcional) Fila + Lambda de processamento de pagamentos (alinhamento ao TC)

O TC Fase 3 pede funções serverless para processos assíncronos, **incluindo processamento de pagamentos**. Para alinhar:

- **Fila SQS:** crie uma fila ex.: `fcg-prod-payment-events` (e opcionalmente DLQ).
- **Lambda de processamento:** função que consome mensagens dessa fila (atualiza status de pagamento, notifica, etc.); event source mapping SQS → Lambda.
- **Quem enfileira:** a API de Pagamentos (ou a rota no API Gateway) grava eventos na fila; a Lambda é acionada pelo **gatilho em evento** (mensagem na fila).

Assim você terá dois fluxos assíncronos com gatilhos: **notificações** (SQS notificação → Lambda notificação) e **pagamentos** (SQS pagamentos → Lambda pagamentos). A configuração no console segue o mesmo padrão dos passos 3–6 (fila, role, Lambda, event source mapping).

## 9. (Opcional) S3 frontend, RDS

- **S3 frontend:** se tiver frontend estático, crie um bucket, configure como website (index/error) e, se for acessar pelo browser, use CloudFront na frente com OAC e origem no S3.
- **RDS:** se as APIs usarem PostgreSQL, crie a instância RDS (VPC, security groups, subnets) e anote o endpoint. As aplicações precisarão da connection string (host, port, database, user, password).

---

## Configuração nos repositórios e nas aplicações

**GitHub (cada serviço que faz push para ECR)**

- **Variable** `ECR_REPOSITORY_NAME`: nome exato do repositório ECR (ex.: `fcg-prod-notification-lambda`, `fcg-prod-users-api`).
- **Variable** `AWS_REGION`: mesma região dos recursos (ex.: `us-east-1`).

**Aplicações (variáveis de ambiente / config)**

- **URL da fila SQS:** as apps que publicam eventos de notificação precisam da **URL** da fila SQS (ex.: `https://sqs.REGION.amazonaws.com/ACCOUNT_ID/fila-name`). Configure na aplicação (variável de ambiente ou appsettings).
- **API Gateway (obrigatório):** configure a **URL base** do API Gateway (Invoke URL do stage `$default`) em todas as apps e no frontend que consomem as APIs (ex.: variável `ApiBaseUrl` ou `API_GATEWAY_URL`).
- **Banco:** se usar RDS, configure connection string (host, port, database, user, password) nas APIs que acessam o PostgreSQL.

---

## Resumo rápido

| Já feito        | Próximo (ordem) |
|-----------------|------------------|
| Roles GitHub + ECR | 1. ECR (4 repos) → 2. Log groups → 3. SQS notificação + DLQ → 4. IAM role Lambda → 5. Lambda notificação (ECR) → 6. Trigger SQS → **7. API Gateway** → 8. (Opc.) SQS + Lambda pagamentos (TC) → 9. (Opc.) S3, RDS. Depois: `ECR_REPOSITORY_NAME` e env vars (fila, API Gateway URL, DB). Para alinhar ao TC: considerar passo 8, X-Ray, audit logs e desenho de arquitetura (ver seção “Alinhamento com o Tech Challenge”). |

Depois do primeiro **push** no repositório **Fase3-NotificationLambda** (branch que dispara o workflow), a imagem estará no ECR. Se a Lambda já estiver apontando para `fcg-prod-notification-lambda:latest`, ela passará a usar essa imagem; caso tenha criado com outra tag, atualize a configuração da função para a tag correta.

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
| **API Gateway para gerenciar requisições dos microsserviços** | API Gateway HTTP API (v2) como frente única; rotas para Users, Games, Payments; rota POST /notify (passo 7.7). |
| **Segurança entre acessos** | JWT Authorizer opcional (passo 7.6); CORS e headers configurados. |
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
   O TC diz “Garantir segurança entre os acessos para os microsserviços”; nos requisitos técnicos, JWT é opcional. Para reforçar a segurança:
   - Tratar o **JWT Authorizer** (passo 7.6) como **recomendado** para rotas de Users, Games e Pagamentos, não apenas opcional, e documentar no README como está a proteção entre microsserviços (quem chama o API Gateway precisa de token válido).

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
