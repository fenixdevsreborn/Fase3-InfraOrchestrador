# Módulo ALB

ALB interno, listener na porta 80, target groups (um por serviço) e listener rules por path.

## Roteamento

- `path_prefix_to_service`: mapa path prefix → service (ex.: `"/users"` → `usersapi`). No ALB são criadas condições para `{path}/*` e `{path}`.
- Default action do listener: fixed-response 404.

## Uso

```hcl
module "alb" {
  source                  = "../../modules/alb"
  project_name            = "fcg-fenix"
  environment             = "production"
  vpc_id                  = module.vpc.vpc_id
  private_subnet_ids      = module.vpc.private_subnet_ids
  alb_security_group_id   = module.security_groups.alb_sg_id
  services                = ["usersapi", "gamesapi", "paymentsapi"]
  path_prefix_to_service  = { "/users" = "usersapi", "/games" = "gamesapi", "/payments" = "paymentsapi" }
  target_port             = 80
  tags_base               = var.tags_base
}
```

## Outputs

- `alb_dns_name`, `alb_arn`, `listener_arn`, `target_group_arns` (map service → ARN).
