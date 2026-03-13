# Deploy a partir de atualização de serviço — guia completo

Este documento consolida o workflow **deploy-from-service-update**, a estrutura Terraform de imagens, como os repositórios de aplicação disparam o deploy e como fazer rollback.

---

## 1. Workflow YAML completo

O arquivo está em **`.github/workflows/deploy-from-service-update.yml`**.

**Fluxo resumido:**
1. **Trigger:** `repository_dispatch` (event_type `deploy-request`) ou `workflow_call`.
2. **Normalize payload:** lê `service_name`, `image_tag`, `image_uri`, `commit_sha`, `environment` do evento.
3. **Validate service name:** mapeia para a variável Terraform (users-api → ecr_image_tag_users_api, etc.); falha se serviço inválido.
4. **Prepare image_tags.auto.tfvars:** cria ou atualiza o arquivo, alterando **apenas** a linha do serviço recebido.
5. **Terraform Init** (usa backend remoto se configurado em `backend.tf`).
6. **Terraform Validate.**
7. **Terraform Plan** com `-var-file=image_tags.auto.tfvars` e gera `tfplan`.
8. **Terraform Apply -auto-approve** do plano (atualiza só o recurso cuja imagem mudou).
9. **Persist (opcional):** commit + push de `image_tags.auto.tfvars` na branch `main`.
10. **Summary:** exibe serviço, tag, ambiente e exit codes no job.

**Permissões:** `contents: write` (para push do tfvars), `id-token: write` (OIDC AWS).

**Secrets/Variables no orquestrador:** `AWS_ROLE_ARN_TERRAFORM`, `AWS_REGION` (var), `TF_VAR_POSTGRES_MASTER_PASSWORD` (se usar RDS).

---

## 2. Passar imagens para o Terraform: variáveis separadas vs mapa

Foi adotada **variáveis separadas por serviço** (e não um único mapa `service_images`).

| Critério | Variáveis separadas | Mapa `service_images` |
|----------|---------------------|------------------------|
| Atualizar um serviço | Workflow altera só uma variável no arquivo; Terraform aplica só o recurso daquela imagem. | Seria preciso passar o mapa inteiro ou mesclar com state; mais complexo. |
| Rollback | Um único `-var` ou uma linha no tfvars com a tag anterior. | Mesmo problema de “passar mapa completo”. |
| Risco de erro | Alterar uma tag não afeta as outras. | Payload incompleto poderia zerar outras chaves do mapa. |
| Repos de aplicação | Cada repo envia (service_name, image_tag); o workflow atualiza só essa variável. | Mesmo envio, mas o Terraform precisaria de lógica extra. |

**Conclusão:** quatro variáveis (`ecr_image_tag_users_api`, `ecr_image_tag_games_api`, `ecr_image_tag_payments_api`, `ecr_image_tag_notification_lambda`) + arquivo `image_tags.auto.tfvars` (uma linha por serviço). Um **local** `service_image_tags` em `locals.tf` agrega as quatro em um mapa para outputs e uso opcional em módulos.

---

## 3. Estrutura Terraform necessária

### variables.tf (trecho — imagens por serviço)

```hcl
# ------------------------------------------------------------------------------
# Imagens Docker por serviço (uma variável por serviço)
# ------------------------------------------------------------------------------

variable "ecr_image_tag_users_api" {
  description = "Tag da imagem Users API no ECR (ex.: latest ou SHA)."
  type        = string
  default     = "latest"
}

variable "ecr_image_tag_games_api" {
  description = "Tag da imagem Games API no ECR."
  type        = string
  default     = "latest"
}

variable "ecr_image_tag_payments_api" {
  description = "Tag da imagem Payments API no ECR."
  type        = string
  default     = "latest"
}

variable "ecr_image_tag_notification_lambda" {
  description = "Tag da imagem Notification Lambda no ECR."
  type        = string
  default     = "latest"
}
```

### locals.tf (mapa para outputs e módulos)

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

### terraform.tfvars.example (trecho — tags de imagem)

```hcl
# Tags de imagem por serviço (atualizadas por workflows de deploy)
ecr_image_tag_users_api           = "latest"
ecr_image_tag_games_api           = "latest"
ecr_image_tag_payments_api        = "latest"
ecr_image_tag_notification_lambda = "latest"
```

O workflow usa **image_tags.auto.tfvars** (cópia do exemplo ou gerado no primeiro run); não é obrigatório ter essas linhas em `terraform.tfvars`.

### outputs.tf (trecho — imagens para rollback)

```hcl
output "service_image_tags" {
  description = "Tag de imagem por serviço (estado aplicado). Use para rollback."
  value       = local.service_image_tags
}

output "service_image_uris" {
  description = "URI completa (repositório:tag) por serviço."
  value       = { for k, url in module.ecr.repository_urls : k => "${url}:${local.service_image_tags[k]}" }
}
```

### Uso nos módulos

O único recurso que hoje usa imagem é a **Notification Lambda**. Exemplo em `main.tf`:

```hcl
module "notification_lambda" {
  source              = "./modules/notification-lambda"
  ecr_repository_url  = module.ecr.repository_urls["notification-lambda"]
  image_tag           = var.ecr_image_tag_notification_lambda
  # ...
}
```

Quando houver módulos para users-api, games-api ou payments-api, o padrão é o mesmo: `image_tag = var.ecr_image_tag_<serviço>` (ou `local.service_image_tags["<serviço>"]`).

---

## 4. Como o serviço chama este workflow

Os repositórios de aplicação (Users API, Games API, Payments API, Notification Lambda) **não** chamam o workflow diretamente por nome; eles disparam um **repository_dispatch** no repositório do orquestrador. O GitHub aciona o workflow que está com `on.repository_dispatch.types: [deploy-request]`.

### No repositório do serviço (ex.: Users API)

No workflow **publish-image** (ou equivalente), após o push da imagem no ECR:

```yaml
- name: Trigger Fase3-InfraOrchestrador
  uses: peter-evans/repository-dispatch@v3
  with:
    token: ${{ secrets.ORCHESTRATOR_REPO_TOKEN }}
    repository: owner/Fase3-InfraOrchestrador
    event-type: deploy-request
    client-payload: |
      {
        "service_name": "users-api",
        "image_tag": "a1b2c3d",
        "image_uri": "123456789012.dkr.ecr.us-east-1.amazonaws.com/fcg-prod-users-api:a1b2c3d",
        "commit_sha": "a1b2c3d4e5f6789012345678901234567890abcd",
        "environment": "prod"
      }
```

- **ORCHESTRATOR_REPO_TOKEN:** PAT com permissão para enviar `repository_dispatch` ao repo do orquestrador.
- **repository:** `owner/Fase3-InfraOrchestrador` (variable no repo do serviço).
- **event-type:** deve ser **`deploy-request`** (igual ao `types` no orquestrador).
- **client_payload:** JSON com os campos que o workflow do orquestrador lê em `github.event.client_payload`.

O orquestrador recebe o evento, normaliza o payload, atualiza só a variável do `service_name` em `image_tags.auto.tfvars`, roda init → validate → plan → apply e atualiza apenas a imagem daquele serviço.

---

## 5. Rollback usando uma imagem anterior

### Saber o que está em produção

No clone do **Fase3-InfraOrchestrador** (ou via API/CI):

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

Guarde essa saída (ou o artifact do último apply) para saber a tag anterior de cada serviço.

### Rollback de um único serviço

**Opção A — Terraform apply com `-var` (recomendado)**

Se a Notification Lambda em produção está com a tag `f7e8d9c` e a tag estável anterior era `e6d5c4b`:

```bash
terraform apply -auto-approve \
  -var-file=image_tags.auto.tfvars \
  -var="ecr_image_tag_notification_lambda=e6d5c4b"
```

Ou, se você usar só o arquivo, altere **apenas** a linha do serviço em `image_tags.auto.tfvars` e rode:

```bash
terraform apply -auto-approve -var-file=image_tags.auto.tfvars
```

**Opção B — Workflow manual terraform-apply**

No repositório **Fase3-InfraOrchestrador**, dispare o workflow **Terraform Apply** (manual) e preencha o input da imagem do serviço com a **tag anterior** (ex.: `notification_lambda_image = e6d5c4b`). Os outros inputs podem ficar vazios. O workflow atualiza só essa tag no arquivo e aplica.

**Opção C — Novo repository_dispatch (rollback automatizado)**

Se você tiver um workflow ou script que envia `repository_dispatch` com a tag desejada (ex.: tag anterior guardada em variável), use o mesmo evento `deploy-request` e payload com `image_tag` = tag anterior. O deploy-from-service-update vai aplicar essa tag da mesma forma.

### Boas práticas

- Manter no ECR as últimas N imagens (lifecycle policy) para não perder a tag de rollback.
- Registrar `terraform output service_image_tags` após cada apply (artifact ou variável) para saber o estado atual sem depender só do arquivo no repo.
