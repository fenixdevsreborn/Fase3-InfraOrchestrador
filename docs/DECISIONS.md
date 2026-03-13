# Decisões de arquitetura — FCG Infra Orchestrator

Este documento registra as decisões explícitas tomadas para a infraestrutura AWS da FCG Cloud Platform (ambiente acadêmico/demonstrável, baixo custo).

---

## 1. APIs: Lambda container image vs ECS Fargate (nesta fase)

**Decisão: Lambda com container image.**

- **Custo:** Lambda paga por requisição e tempo de execução; sem custo quando ocioso. ECS Fargate tem custo mínimo contínuo (task sempre ativa).
- **Operação:** Menos componentes (sem cluster, service, load balancer); deploy = push da imagem no ECR + atualizar Lambda.
- **Alinhamento:** A notificação já é Lambda (container); manter Games/Payments/Users como Lambda container permite um único padrão de deploy.
- **Limite:** Payload de request 6 MB, timeout até 15 min; para APIs .NET típicas é suficiente. Se no futuro precisar de long-polling ou conexões persistentes, migrar para ECS Fargate.

---

## 2. Estratégia do banco PostgreSQL

**Decisão: RDS PostgreSQL, instância única (single-AZ), classe db.t3.micro (ou db.t4g.micro), armazenamento gp3.**

- **Custo:** db.t3.micro é uma das opções mais baratas; single-AZ evita custo de standby.
- **Destruição:** `terraform destroy` remove a instância; sem backup automático além do retention de 7 dias (opcional). Para demo, `skip_final_snapshot = true` para destruir sem criar snapshot final.
- **Escalabilidade futura:** Pode ativar multi-AZ e aumentar instance class alterando variáveis; opcionalmente Aurora Serverless v2 em fase posterior (custo mínimo maior).
- **Acesso:** Apenas de dentro da VPC (Lambdas em VPC ou APIs em ECS na mesma VPC). Para desenvolvimento local, considerar bastion ou RDS Data API em fase futura.

---

## 3. API Gateway e JWT

**Decisão: API Gateway HTTP API (v2) com JWT authorizer nativo quando o emissor for configurado.**

- **HTTP API:** Mais barato que REST API; suporta JWT authorizer com issuer (URL) e audience.
- **JWT:** Se `jwt_issuer_uri` for preenchido (ex.: Cognito User Pool URL ou endpoint JWKS da Users API), o API Gateway valida o token e repassa o contexto para a integração. Rotas protegidas usam `authorizer_id` no recurso de rota.
- **Nesta fase:** O módulo cria o authorizer quando há issuer; a rota `$default` está sem authorizer (placeholder). Ao adicionar rotas (ex.: `POST /games/{id}/purchase`), associar o `jwt_authorizer_id` às rotas que exigem autenticação.
- **Alternativa:** Lambda authorizer (request) para lógica customizada (claims, múltiplos issuers); deixar para fase futura se necessário.

---

## 4. Observabilidade e logs

**Decisão: CloudWatch Logs como destino central; API Gateway e Lambdas escrevem nos mesmos log groups por serviço.**

- **API Gateway:** Access logs no stage com formato JSON (requestId, ip, method, routeKey, status) para um log group dedicado (`/aws/apigateway/...`).
- **Lambda:** Cada função usa o log group criado pelo módulo (ex.: `/aws/lambda/fcg-prod-notification`); retenção configurável (ex.: 14 dias).
- **Rastreio:** Correlation ID e Trace ID podem ser enviados nos headers pelas aplicações; o API Gateway pode logar headers customizados se o formato for ajustado. X-Ray pode ser habilitado depois nos estágios e nas Lambdas.
- **Métricas:** CloudWatch Metrics já existem para API Gateway e Lambda; dashboards podem ser adicionados como módulo opcional.

---

## 5. Destruição do ambiente após a demo

**Decisão: `terraform destroy` completo; state em backend S3 (opcional) para permitir recriação idempotente.**

- **Ordem:** Terraform remove recursos na ordem de dependências (Lambda event source, depois Lambda, SQS, API Gateway, RDS, VPC, etc.). Não é necessário script de teardown especial.
- **Cuidados:** Bucket S3 com objetos deve ser esvaziado antes (`aws s3 rm s3://bucket --recursive`) ou usar `force_destroy = true` no bucket (incluído no módulo frontend se desejado). ECR com lifecycle policy remove imagens antigas; o repositório em si é removido no destroy.
- **State:** Com backend S3 + DynamoDB, o state persiste após destroy; pode-se rodar `apply` de novo para recriar. Sem backend, o state local é perdido com o destroy; documentar backup do state se necessário.

---

## 6. Resumo de custo (ordem de grandeza, região us-east-1)

| Recurso            | Estimativa (demo, uso leve) |
|--------------------|-----------------------------|
| API Gateway HTTP   | Pay-per-request; ~$0.90/milhão |
| Lambda             | Free tier + pouco além       |
| SQS                | Free tier (1M requests)      |
| ECR                | Armazenamento por GB        |
| RDS db.t3.micro    | ~US$ 15–20/mês              |
| S3                 | Armazenamento + requests    |
| CloudWatch Logs    | Por GB ingerido/arquivado    |

**Total estimado (ambiente prod simples, pouco tráfego):** ~US$ 25–40/mês. Reduzir a zero: `terraform destroy` e desativar recursos que não tenham custo quando ociosos.
