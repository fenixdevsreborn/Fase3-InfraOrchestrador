# Módulo API Gateway HTTP API

API Gateway HTTP API com integração privada via VPC Link para um ALB interno. Inclui NLB como ponte (VPC Link → NLB → ALB).

## Estrutura

- **NLB** (`fcg-fenix-main-nlb`): interno, em subnets privadas; target group com target_type = alb apontando para o ALB.
- **VPC Link** (`fcg-fenix-main-vpclink`): subnets privadas (e opcionalmente security groups); permite que a API Gateway alcance o NLB na VPC.
- **HTTP API** (`fcg-fenix-main-apigw`): rotas ANY para `/users/{proxy+}`, `/games/{proxy+}`, `/payments/{proxy+}` (e variantes exatas `/users`, `/games`, `/payments`).
- **Stage**: `$default` com `auto_deploy = true`.
- **Observabilidade (automático):**
  - **Access logs** → CloudWatch Log Group `/aws/apigateway/{project}-main-http-access` (formato JSON com variáveis `$context.*`).
  - **Resource policy** no log group permitindo `apigateway.amazonaws.com` gravar (condição `SourceArn` na API).
  - **Métricas de rota detalhadas** (`detailed_metrics_enabled = true`) e **log de execução** na rota padrão (`logging_level = INFO` por padrão). **Data trace** (corpo request/response) fica **desligado** por padrão (`api_gateway_data_trace_enabled`); ative só se necessário (custo e dados sensíveis).

Variáveis opcionais: `api_gateway_access_log_retention_days`, `api_gateway_detailed_metrics_enabled`, `api_gateway_route_logging_level` (`ERROR` \| `INFO` \| `OFF`), `api_gateway_data_trace_enabled`.

### Autorização JWT (Users API)

- **Importante:** na criação do authorizer, a **AWS chama** `{issuer}/.well-known/openid-configuration`. Se retornar 404 ou JSON inválido, o `terraform apply` **falha**. Por isso `jwt_authorizer_enabled` vem **false** por padrão: suba a Users API com `Jwt__Issuer` e `ASPNETCORE_PATHBASE=/users` alinhados ao issuer, teste a URL no browser/curl, e só então defina `jwt_authorizer_enabled = true` e rode outro apply.
- **Authorizer** `JWT` no API Gateway valida `Authorization: Bearer` com **issuer** + **audience** e chaves via **OIDC discovery** (`{issuer}/.well-known/openid-configuration`).
- **Rotas protegidas (default):** `/games`, `/games/{proxy+}`, `/payments`, `/payments/{proxy+}`.
- **Rotas sem JWT no gateway:** `/users` e `/users/{proxy+}` (login `auth/login`, OIDC, health, etc.).
- **Webhook público:** `POST /payments/payments/webhooks/provider` (sem JWT), alinhado a `ASPNETCORE_PATHBASE=/payments` na Payments API; se a app **não** usar PathBase, ajuste essa rota no `main.tf` do módulo para `POST /payments/webhooks/provider`.
- **Issuer:** se `users_api_jwt_issuer` estiver vazio, usa `https://{api-id}.execute-api.{região}.amazonaws.com/users`. A **Users API** deve ter `Jwt__Issuer` idêntico e expor `.well-known` sob esse prefixo (tipicamente `ASPNETCORE_PATHBASE=/users`).
- **Audience:** default `["fcg-cloud-platform"]` — alinhar com `Jwt__Audience` nas três APIs.

## Path forwarding e observações críticas

Ver documento **docs/terraform-apigateway-path-observations.md**.

Resumo:
- Stage **$default**: o path na URL de invocação **não** inclui o nome do stage; o path enviado ao backend é o mesmo recebido (ex.: `/users/123` → ALB recebe `/users/123`).
- Se usar stage nomeado (ex.: `v1`): a URL seria `.../v1/users/123` e o backend receberia `/v1/users/123` a menos que se use **parameter mapping** para reescrever o path (ex.: `overwrite:path` = `$request.path` com transformação para remover o prefixo do stage).
- Recomendação: manter **$default** para evitar reescrita de path; rotas no ALB devem coincidir com as rotas expostas na API Gateway (`/users/*`, `/games/*`, `/payments/*`).

## Uso

```hcl
module "api_gateway" {
  source = "../../modules/api-gateway"

  project_name         = local.project_name
  environment          = local.environment
  vpc_id               = module.vpc.vpc_id
  private_subnet_ids   = module.vpc.private_subnet_ids
  alb_arn              = module.alb.alb_arn
  alb_listener_port    = 80
  route_paths          = { "/users" = "usersapi", "/games" = "gamesapi", "/payments" = "paymentsapi" }
  tags_base            = var.tags_base
}
```

## Outputs

- `api_id`, `api_endpoint`, `invoke_url`, `vpc_link_id`, `nlb_dns_name`, `stage_name`.
- `access_log_group_name`, `access_log_group_arn` — access logs no CloudWatch.
- `jwt_authorizer_id`, `users_jwt_issuer_effective` — authorizer JWT e issuer efetivo (para `.env` na EC2).
