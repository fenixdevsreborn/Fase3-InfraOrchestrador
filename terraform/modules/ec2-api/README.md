# Módulo EC2 API

Uma instância EC2 privada por serviço. Naming: `fcg-fenix-{service}-ec2`. User data instala Docker e cria `/opt/fcg-fenix/{service}`. A instância é registrada no target group informado.

## Uso

```hcl
module "ec2_usersapi" {
  source                 = "../../modules/ec2-api"
  project_name           = "fcg-fenix"
  environment            = "production"
  service                = "usersapi"
  vpc_id                 = module.vpc.vpc_id
  private_subnet_ids     = module.vpc.private_subnet_ids
  security_group_id      = module.security_groups.usersapi_sg_id
  instance_profile_name  = module.iam_ec2_usersapi.instance_profile_name
  target_group_arn       = module.alb.target_group_arns["usersapi"]
  target_port            = 80
  instance_type          = "t3.micro"
  tags_base              = var.tags_base
}
```

## Outputs

- `instance_id`, `private_ip`, `availability_zone`, `instance_arn`.
