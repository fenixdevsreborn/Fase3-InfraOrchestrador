# Módulo Security Groups

Security groups do ALB e das EC2 por serviço (usersapi, gamesapi, paymentsapi).

## Naming

- ALB: `{project_name}-alb-sg`
- EC2 por serviço: `{project_name}-{service}-sg` (ex.: fcg-fenix-usersapi-sg)

## Desenho

- **ALB**: um SG compartilhado. Ingress nas portas configuráveis (ex. 80, 443) a partir de CIDRs (ex. CIDR da VPC para tráfego do API Gateway via VPC Link). Egress **apenas** para os SGs das EC2 das APIs (porta da aplicação); sem egress para 0.0.0.0/0.
- **EC2 por serviço**: um SG por serviço. Ingress apenas (1) do ALB na porta da API e (2) porta 443 para SSM (Run Command / Session Manager). Egress livre (0.0.0.0/0) para pull de imagens e updates.

## Segurança

- **Princípio do menor privilégio**: ALB não tem egress para internet; só para os SGs das APIs.
- **EC2**: recebem tráfego apenas do ALB (app) e SSM (gerenciamento). Em cenários mais restritivos, trocar o ingress SSM 0.0.0.0/0 por VPC endpoints e CIDRs específicos.
- **Tags**: recursos compartilhados (ALB) com Application/Service = shared; cada SG de EC2 com Application/Service = nome do serviço.

## Ingress do ALB

- `alb_ingress_cidr_blocks`: em produção, preferir o CIDR da VPC (ex. `[module.vpc.vpc_cidr_block]`) para que apenas tráfego interno (ex. API Gateway via VPC Link) alcance o ALB. Deixar vazio ou 0.0.0.0/0 só para testes.

## Uso

```hcl
module "security_groups" {
  source = "../../modules/security-groups"

  project_name           = "fcg-fenix"
  environment            = "production"
  vpc_id                 = module.vpc.vpc_id
  services               = ["usersapi", "gamesapi", "paymentsapi"]
  tags_base              = { Project = "fcg-fenix", ManagedBy = "terraform", Environment = "production" }
  alb_ingress_cidr_blocks = [module.vpc.vpc_cidr_block]
  alb_ingress_ports      = [80, 443]
  api_ports              = [80]
}
```
