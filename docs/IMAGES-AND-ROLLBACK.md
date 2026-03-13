# Imagens por serviço e estratégia de rollback

Este documento descreve a modelagem Terraform para **imagens Docker por serviço**, como os módulos consomem essas imagens, como usar `-var` nos workflows e a **estratégia de rollback**.

---

## 1. Modelagem escolhida: variáveis separadas por serviço

Foi adotada **uma variável por serviço** (e não um único mapa `service_images`) pelos seguintes motivos:

| Critério | Variáveis separadas | Mapa único |
|----------|---------------------|------------|
| **Atualizar um serviço** | Passar só `-var ecr_image_tag_notification_lambda=x`; os outros vêm de tfvars/state | Precisaria passar o mapa inteiro ou ler state e mesclar |
| **Múltiplos repositórios** | Cada repo envia um par (serviço, tag); o workflow altera só essa variável | Mesmo envio, mas o Terraform precisaria de lógica extra para “merge” no map |
| **Rollback** | Um único `-var` com a tag anterior | Mesmo merge/state |
| **Risco de erro** | Alterar uma variável não afeta as outras | Risco de sobrescrever o mapa e zerar outras tags se o workflow passar map incompleto |
| **Clareza** | Cada serviço explícito em variables.tf e tfvars | Um bloco só; menos explícito por serviço |

**Conclusão:** variáveis separadas (`ecr_image_tag_users_api`, `ecr_image_tag_games_api`, `ecr_image_tag_payments_api`, `ecr_image_tag_notification_lambda`) com **local map** em `locals.tf` (`service_image_tags`) para outputs e uso opcional em módulos.

---

## 2. Estrutura Terraform

### variables.tf

Cada serviço tem uma variável string, default `"latest"`:

```hcl
variable "ecr_image_tag_users_api"           { type = string, default = "latest" }
variable "ecr_image_tag_games_api"           { type = string, default = "latest" }
variable "ecr_image_tag_payments_api"        { type = string, default = "latest" }
variable "ecr_image_tag_notification_lambda" { type = string, default = "latest" }
```

### locals.tf

Agregação para outputs e referência única:

```hcl
locals {
  service_image_tags = {
    "users-api"           = var.ecr_image_tag_users_api
    "games-api"           = var.ecr_image_tag_games_api
    "payments-api"        = var.ecr_image_tag_payments_api
    "notification-lambda" = var.ecr_image_tag_notification_lambda
  }
}
```

### terraform.tfvars.example

Inclui as quatro variáveis com valor `"latest"` e comentário de exemplo com `-var` para um único serviço.

### outputs.tf

- **service_image_tags:** mapa serviço → tag (estado aplicado; útil para rollback).
- **service_image_uris:** mapa serviço → `repositório:tag` (URI completa).

---

## 3. Como os módulos consomem as imagens

Cada recurso que usa imagem ECR recebe:

1. **URL do repositório** (sem tag): `module.ecr.repository_urls["<service>"]`
2. **Tag da imagem:** a variável correspondente (ou `local.service_image_tags["<service>"]`)

### Exemplo: Notification Lambda (já implementado)

```hcl
module "notification_lambda" {
  source              = "./modules/notification-lambda"
  ecr_repository_url  = module.ecr.repository_urls["notification-lambda"]
  image_tag           = var.ecr_image_tag_notification_lambda   # ou local.service_image_tags["notification-lambda"]
  # ...
}
```

O módulo `notification-lambda` monta `image_uri = "${var.ecr_repository_url}:${var.image_tag}"`.

### Padrão para novos serviços (Users, Games, Payments)

Quando houver módulo ECS/Lambda para esses serviços, usar o mesmo padrão:

```hcl
# Exemplo futuro: users-api como Lambda ou ECS
module "users_api" {
  source             = "./modules/users-api"   # ou ECS
  ecr_repository_url = module.ecr.repository_urls["users-api"]
  image_tag          = var.ecr_image_tag_users_api
  # ...
}
```

Ou, se preferir o local map:

```hcl
  image_tag = local.service_image_tags["users-api"]
```

Os dois são equivalentes; variável direta deixa explícito qual serviço é.

---

## 4. Exemplos de uso com `-var`

### Atualizar só a Notification Lambda

```bash
terraform apply -auto-approve \
  -var="ecr_image_tag_notification_lambda=a1b2c3d" \
  -var-file=image_tags.auto.tfvars
```

Ou, sem var-file, os outros serviços ficam com default `"latest"` (cuidado se já estiverem com outra tag no state):

```bash
terraform apply -auto-approve \
  -var-file=terraform.tfvars \
  -var="ecr_image_tag_notification_lambda=a1b2c3d"
```

### Atualizar só a Users API

```bash
terraform apply -auto-approve \
  -var-file=image_tags.auto.tfvars \
  -var="ecr_image_tag_users_api=v2.0.1"
```

### Aplicar com arquivo de tags (recomendado em CI)

O workflow lê/gera `image_tags.auto.tfvars` e aplica com:

```bash
terraform apply -auto-approve -var-file=image_tags.auto.tfvars
```

Assim todas as tags vêm do arquivo (persistido ou gerado pelo workflow).

---

## 5. Estratégia de rollback

### 5.1 Saber o que está em produção

Após cada apply (ou periodicamente):

```bash
terraform output -json service_image_tags
```

Exemplo de saída:

```json
{
  "users-api": "latest",
  "games-api": "a1b2c3d",
  "payments-api": "latest",
  "notification-lambda": "f7e8d9c"
}
```

Guarde essa saída (ou use `terraform output -json service_image_tags > deployed-tags.json`) para saber a tag anterior de cada serviço.

### 5.2 Rollback de um único serviço

Se a **Notification Lambda** com tag `f7e8d9c` falhou e a tag estável anterior era `e6d5c4b`:

```bash
terraform apply -auto-approve \
  -var-file=image_tags.auto.tfvars \
  -var="ecr_image_tag_notification_lambda=e6d5c4b"
```

Ou atualize apenas a linha correspondente em `image_tags.auto.tfvars` e rode:

```bash
terraform apply -auto-approve -var-file=image_tags.auto.tfvars
```

### 5.3 Rollback via workflow manual

No **terraform-apply.yml**, informe no input do serviço a desejada a **tag anterior** (ex.: `notification_lambda_image = e6d5c4b`) e execute o workflow. Os outros inputs podem ficar vazios.

### 5.4 Boas práticas

- **Retenção de imagens no ECR:** política de lifecycle que mantém as últimas N imagens (ex.: 10) para permitir rollback sem recriar build.
- **Registro do que foi aplicado:** salvar `terraform output service_image_tags` em artifact ou variável após cada deploy (ex.: no workflow de apply).
- **Tag semântica ou SHA:** usar tags imutáveis (SHA do commit ou versão) facilita identificar a versão estável para voltar.

---

## 6. Resumo

| Item | Implementação |
|------|----------------|
| **Modelagem** | Variável por serviço + `local.service_image_tags` em locals.tf |
| **Arquivos** | variables.tf, locals.tf, terraform.tfvars.example, outputs.tf (service_image_tags, service_image_uris) |
| **Módulos** | Recebem `ecr_repository_url` do módulo ECR e `image_tag` da variável (ou do local map) |
| **Apply** | `-var-file=image_tags.auto.tfvars` e opcionalmente `-var ecr_image_tag_<serviço>=tag` para um só |
| **Rollback** | Aplicar novamente com a tag anterior em `-var` ou em image_tags.auto.tfvars; consultar `terraform output service_image_tags` para saber o estado atual |
