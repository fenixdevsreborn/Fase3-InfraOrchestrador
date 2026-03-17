# Módulo API Gateway HTTP API

API Gateway HTTP API com integração privada via VPC Link para um ALB interno. Inclui NLB como ponte (VPC Link → NLB → ALB).

## Estrutura

- **NLB** (`fcg-fenix-main-nlb`): interno, em subnets privadas; target group com target_type = alb apontando para o ALB.
- **VPC Link** (`fcg-fenix-main-vpclink`): subnets privadas (e opcionalmente security groups); permite que a API Gateway alcance o NLB na VPC.
- **HTTP API** (`fcg-fenix-main-apigw`): rotas ANY para `/users/{proxy+}`, `/games/{proxy+}`, `/payments/{proxy+}` (e variantes exatas `/users`, `/games`, `/payments`).
- **Stage**: `$default` com `auto_deploy = true`.

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
