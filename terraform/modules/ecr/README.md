# Módulo ECR

Um repositório ECR por serviço. Naming: `fcg-fenix-{service}-ecr`.

## Uso

```hcl
module "ecr" {
  source       = "../../modules/ecr"
  project_name = "fcg-fenix"
  environment  = "production"
  services     = ["usersapi", "gamesapi", "paymentsapi"]
  tags_base    = { Project = "fcg-fenix", ManagedBy = "terraform", Environment = "production" }
}
```

## Outputs

- `repository_urls` — mapa service → URL (para docker push)
- `repository_arns` — mapa service → ARN (para políticas IAM de pull)
