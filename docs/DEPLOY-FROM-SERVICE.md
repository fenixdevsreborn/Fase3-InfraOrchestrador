# Deploy a partir de atualização de serviço

Este documento descreve como o repositório **Fase3-InfraOrchestrador** recebe eventos dos repositórios de aplicação, atualiza a imagem do serviço e aplica o Terraform (deploy apenas do recurso impactado).

---

## 1. Como o workflow recebe os dados

### Opção A: `repository_dispatch` (recomendado para repos de aplicação em outro repo)

Os repositórios de aplicação (Users API, Games API, Payments API, Notification Lambda) após publicar a imagem no ECR disparam um evento **repository_dispatch** neste repositório:

- **Event type:** `deploy-request`
- **Client payload (JSON):**
  - `service_name` (obrigatório): `users-api` | `games-api` | `payments-api` | `notification-lambda`
  - `image_tag` (obrigatório): tag da imagem no ECR (ex.: SHA curto `a1b2c3d`)
  - `image_uri` (opcional): URI completa `registry/repo:tag`
  - `commit_sha` (opcional): SHA do commit no repo do serviço
  - `environment` (opcional): `prod` | `staging` | `demo` (default `prod`)

Exemplo (do repo de aplicação, via API ou action):

```bash
curl -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/OWNER/Fase3-InfraOrchestrador/dispatches \
  -d '{"event_type":"deploy-request","client_payload":{"service_name":"notification-lambda","image_tag":"a1b2c3d","commit_sha":"abc123","environment":"prod"}}'
```

No GitHub Actions do repo de aplicação, use algo como:

```yaml
- name: Trigger infra orchestrator
  uses: peter-evans/repository-dispatch@v3
  with:
    token: ${{ secrets.ORCHESTRATOR_REPO_TOKEN }}
    repository: owner/Fase3-InfraOrchestrador
    event-type: deploy-request
    client-payload: '{"service_name":"notification-lambda","image_tag":"${{ env.SHA_TAG }}","image_uri":"${{ env.IMAGE_URI }}","commit_sha":"${{ github.sha }}","environment":"prod"}'
```

### Opção B: `workflow_call` (quando o orquestrador chama este workflow de outro workflow)

Outro workflow neste ou em outro repositório pode chamar este workflow como reusable:

```yaml
jobs:
  call-deploy:
    uses: owner/Fase3-InfraOrchestrador/.github/workflows/deploy-from-service-update.yml@main
    with:
      service_name: notification-lambda
      image_tag: a1b2c3d
      image_uri: 123456789.dkr.ecr.us-east-1.amazonaws.com/fcg-prod-notification-lambda:a1b2c3d
      commit_sha: abc123
      environment: prod
    secrets: inherit
```

Os dados chegam em `github.event.inputs` e são normalizados no primeiro step do job.

---

## 2. Estratégia de variáveis de imagem por serviço

### Variáveis Terraform (root)

Cada serviço tem uma variável no módulo root:

| service_name (evento) | Variável Terraform |
|----------------------|--------------------|
| `users-api` | `ecr_image_tag_users_api` |
| `games-api` | `ecr_image_tag_games_api` |
| `payments-api` | `ecr_image_tag_payments_api` |
| `notification-lambda` | `ecr_image_tag_notification_lambda` |

Valores default: `"latest"`. O workflow atualiza **apenas** a variável do serviço que disparou o evento; as demais permanecem no valor atual (arquivo ou default).

### Persistência: arquivo `image_tags.auto.tfvars`

- **Arquivo:** `image_tags.auto.tfvars` (gerado/atualizado pelo workflow).
- **Exemplo:** `image_tags.auto.tfvars.example` (versionado; copiado na primeira execução se o .tfvars não existir).
- **Comportamento:**
  1. O workflow lê ou cria `image_tags.auto.tfvars`.
  2. Atualiza só a linha da variável correspondente ao `service_name` com o `image_tag` recebido.
  3. Roda `terraform plan -var-file=image_tags.auto.tfvars` e `terraform apply -auto-approve tfplan`.
  4. (Opcional) Faz commit e push de `image_tags.auto.tfvars` na branch `main` para persistir o estado das tags entre execuções.

**Vantagens:** Terraform vê sempre o conjunto completo de tags; apenas o recurso cuja imagem mudou é alterado no plan/apply; custo baixo e reaproveitamento da infra existente.

### Alternativa: `-var` dinâmico

Em vez de arquivo, pode-se passar apenas a variável do serviço:

```bash
terraform plan -var="ecr_image_tag_notification_lambda=$IMAGE_TAG" -out=tfplan
```

Problema: as outras três variáveis passariam a ser o default (`"latest"`), sobrescrevendo o que já está aplicado. Por isso a abordagem recomendada é **atualizar um único arquivo** (`image_tags.auto.tfvars`) com todas as tags e usar `-var-file` nesse arquivo.

---

## 3. Estrutura Terraform que suporta isso

- **Root:** `variables.tf` declara as quatro variáveis `ecr_image_tag_*` (default `"latest"`).
- **Módulo notification-lambda:** recebe `image_tag` e usa `image_uri = "${var.ecr_repository_url}:${var.image_tag}"`. O root passa `var.ecr_image_tag_notification_lambda`.
- **APIs (users, games, payments):** quando houver recurso (ECS/Lambda) que use imagem ECR, o módulo deve receber a tag correspondente e montar a `image_uri` da mesma forma.
- **Backend:** usar backend remoto (ex.: S3 + DynamoDB) em `backend.tf` para state e lock; o workflow usa o mesmo state em todas as execuções.

Estrutura sugerida:

```
Fase3-InfraOrchestrador/
├── .github/workflows/
│   └── deploy-from-service-update.yml
├── main.tf                    # módulos ecr, notification_lambda, etc.
├── variables.tf               # ecr_image_tag_* + demais
├── image_tags.auto.tfvars     # gerado/atualizado pelo workflow (não versionar se sensível)
├── image_tags.auto.tfvars.example
├── backend.tf                 # S3 + DynamoDB (copiar de backend.tf.example)
├── terraform.tfvars           # demais variáveis (ambiente, projeto, etc.)
└── modules/
    ├── notification-lambda/   # usa var.image_tag
    └── ...
```

---

## 4. Integração com os repositórios de aplicação

Fluxo resumido:

1. **Repo de aplicação** (ex.: Notification Lambda): push na `main` → CI → build da imagem → push no ECR com tag = SHA (e opcionalmente `latest`) → **repository_dispatch** para `Fase3-InfraOrchestrador` com `event_type: deploy-request` e `client_payload: { service_name, image_tag, ... }`.
2. **Fase3-InfraOrchestrador:** workflow `deploy-from-service-update.yml` é acionado → normaliza payload → valida `service_name` → atualiza `image_tags.auto.tfvars` para esse serviço → `terraform init` → `terraform plan -var-file=image_tags.auto.tfvars` → `terraform apply -auto-approve` → (opcional) commit do `image_tags.auto.tfvars`.

Secrets/variáveis nos **repos de aplicação**:

- `ORCHESTRATOR_REPO_TOKEN`: PAT com permissão para disparar `repository_dispatch` no repo do orquestrador.
- `ORCHESTRATOR_REPO`: ex. `owner/Fase3-InfraOrchestrador`.

Secrets/variáveis no **Fase3-InfraOrchestrador**:

- `AWS_ROLE_ARN_TERRAFORM`: (OIDC) role AWS para Terraform acessar S3, ECR, Lambda, etc.
- `AWS_REGION`: (variable) ex. `us-east-1`.
- `TF_VAR_POSTGRES_MASTER_PASSWORD`: (secret) se usar RDS e variável de ambiente para senha.

---

## 5. Outputs do workflow

O job `deploy` expõe:

- `service_updated`: serviço cuja imagem foi atualizada.
- `image_tag_applied`: tag aplicada.
- `environment`: ambiente usado.
- `plan_exit_code` / `apply_exit_code`: códigos de saída do plan e do apply.

Úteis para workflows que chamam este via `workflow_call` ou para inspeção na Summary da run.
