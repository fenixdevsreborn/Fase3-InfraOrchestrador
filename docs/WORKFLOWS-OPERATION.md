# Workflows operacionais — Terraform (manual)

Este documento descreve os workflows manuais do repositório **Fase3-InfraOrchestrador** para operar a infraestrutura com Terraform: plan, apply e destroy.

---

## 1. Workflows disponíveis

| Workflow | Arquivo | Uso |
|----------|---------|-----|
| **Terraform Plan** | `terraform-plan.yml` | Gerar plano de execução e salvar como artifact para revisão. |
| **Terraform Apply** | `terraform-apply.yml` | Aplicar a infra (completa ou apenas atualizar imagens). |
| **Terraform Destroy** | `terraform-destroy.yml` | Destruir toda a infra do ambiente (exige confirmação). |

Todos são acionados manualmente em **Actions → workflow_dispatch**.

---

## 2. Inputs manuais

### Terraform Plan

| Input | Obrigatório | Descrição |
|-------|-------------|-----------|
| `environment` | Sim | Ambiente: `prod`, `staging` ou `demo`. Default: `prod`. |

### Terraform Apply

| Input | Obrigatório | Descrição |
|-------|-------------|-----------|
| `environment` | Sim | Ambiente: `prod`, `staging` ou `demo`. Default: `prod`. |
| `users_api_image` | Não | Tag da imagem Users API (ex.: `latest`, `a1b2c3d`). Vazio = não altera. |
| `games_api_image` | Não | Tag da imagem Games API. Vazio = não altera. |
| `payments_api_image` | Não | Tag da imagem Payments API. Vazio = não altera. |
| `notification_lambda_image` | Não | Tag da imagem Notification Lambda. Vazio = não altera. |

### Terraform Destroy

| Input | Obrigatório | Descrição |
|-------|-------------|-----------|
| `environment` | Sim | Ambiente a destruir: `prod`, `staging` ou `demo`. Default: `prod`. |
| `confirm_destroy` | Sim | Deve ser exatamente **`DESTROY`** (maiúsculo). Qualquer outro valor faz o job de destroy **não rodar** e apenas exibe mensagem de cancelamento. |

---

## 3. GitHub Secrets e Variables necessários

### Secrets (Settings → Secrets and variables → Actions)

| Secret | Obrigatório | Uso |
|--------|-------------|-----|
| `AWS_ROLE_ARN_TERRAFORM` | Sim (com OIDC) | ARN da IAM Role que o GitHub Actions assume via OIDC para acessar AWS (Terraform state S3, DynamoDB lock, recursos gerenciados). |
| `TF_VAR_POSTGRES_MASTER_PASSWORD` | Se usar RDS | Senha do PostgreSQL; passada como `TF_VAR_postgres_master_password` para o Terraform. Não hardcodar em tfvars. |

Se **não** usar OIDC: configure `AWS_ACCESS_KEY_ID` e `AWS_SECRET_ACCESS_KEY` (não recomendado; preferir OIDC).

### Variables (Settings → Variables)

| Variable | Obrigatório | Exemplo | Uso |
|----------|-------------|---------|-----|
| `AWS_REGION` | Não (default us-east-1) | `us-east-1` | Região AWS usada pelo Terraform/CLI. |

---

## 4. Backend remoto e lock de state

- Configure o **backend remoto** em `backend.tf` (copie de `backend.tf.example`): bucket S3 para state, DynamoDB para lock.
- Os workflows **não** passam `-backend-config`; eles assumem que `terraform init` usa o backend definido em `backend.tf`.
- Com DynamoDB, o state fica travado durante `plan`/`apply`/`destroy`, evitando execuções concorrentes.

---

## 5. Cuidados de segurança

- **Não** commitar `terraform.tfvars` ou `image_tags.auto.tfvars` com segredos; usar secrets para senhas e variáveis sensíveis.
- **OIDC:** usar `AWS_ROLE_ARN_TERRAFORM` com trust policy restrita ao repositório (e opcionalmente à branch `main`) reduz o uso de chaves de longa duração.
- **Logs:** o Terraform pode imprimir valores em plan/apply; evite passar dados sensíveis como variáveis em claro nos inputs dos workflows (use secrets).
- **Destroy:** o workflow exige o input `confirm_destroy` = `"DESTROY"` (maiúsculo); recomenda-se ainda **environment protection rules** (ver abaixo).

---

## 6. Evitar destruição indevida

1. **Confirmação no workflow:** o campo `confirm_destroy` obriga a digitar exatamente `DESTROY` (maiúsculo); caso contrário, o job de destroy não executa.
2. **Environment protection (recomendado):** em Settings → Environments → crie um environment (ex.: `production`) e associe ao workflow **terraform-destroy** (ou à branch que ele usa). Ative **Required reviewers** para que um humano aprove a execução antes de rodar.
3. **Branch protection:** restringir a execução de `terraform-destroy.yml` apenas na branch `main` (no `on.workflow_dispatch` não há branch por padrão; o workflow roda no branch a partir do qual foi disparado). Considere documentar: “Sempre rodar destroy a partir de `main` após pull request aprovado.”
4. **Documentar:** avisar a equipe que destroy é irreversível e que deve ser usado apenas para descomissionar ambiente.

---

## 7. Exemplos de uso

### Gerar e revisar um plan (prod)

1. Actions → **Terraform Plan** → **Run workflow**.
2. Escolha **environment**: `prod`.
3. Após a conclusão, baixe o artifact **tfplan-prod-&lt;run_id&gt;** (contém `tfplan`, `plan.txt`, `plan.log`) para revisar o plano.

### Aplicar a infra completa (staging)

1. Actions → **Terraform Apply** → **Run workflow**.
2. **environment**: `staging`.
3. Deixe os campos de imagem vazios.
4. O workflow roda `terraform apply -auto-approve` com o state e tfvars atuais.

### Atualizar apenas a imagem da Notification Lambda (prod)

1. Actions → **Terraform Apply** → **Run workflow**.
2. **environment**: `prod`.
3. **notification_lambda_image**: `a1b2c3d` (tag desejada).
4. Demais imagens: vazio.
5. O workflow atualiza `image_tags.auto.tfvars` só para a Lambda e aplica.

### Destruir o ambiente demo

1. Actions → **Terraform Destroy** → **Run workflow**.
2. **environment**: `demo`.
3. **confirm_destroy**: digite exatamente `DESTROY` (maiúsculo).
4. Clique em **Run workflow**. O job rodará `terraform destroy -auto-approve`.

Se digitar qualquer outro valor em `confirm_destroy`, o job de destroy **não** roda e a run exibe que a ação foi cancelada.

---

## 8. Passo a passo — usar Plan / Apply / Destroy manualmente

### Plan (só visualizar mudanças)

1. No GitHub: **Actions** → selecione **Terraform Plan**.
2. Clique em **Run workflow**.
3. Escolha **environment** (prod, staging ou demo).
4. Clique em **Run workflow** (botão verde).
5. Aguarde o fim da execução. Veja o log do step **Terraform Plan** e, se quiser, baixe o artifact com o plano (tfplan, plan.txt, plan.log).

### Apply (aplicar ou atualizar infra)

1. **Actions** → **Terraform Apply** → **Run workflow**.
2. Escolha **environment**.
3. (Opcional) Preencha um ou mais campos de imagem (`users_api_image`, `games_api_image`, `payments_api_image`, `notification_lambda_image`) para atualizar apenas essas tags. Deixe vazios para não alterar.
4. **Run workflow**. O workflow roda init → validate → apply -auto-approve.

### Destroy (destruir ambiente)

1. **Actions** → **Terraform Destroy** → **Run workflow**.
2. Escolha **environment** (o ambiente que será destruído).
3. No campo **confirm_destroy**, digite exatamente: **DESTROY** (tudo maiúsculo).
4. **Run workflow**. Se a confirmação estiver correta, o job executa init e destroy -auto-approve. Se não, outro job exibe “Destroy cancelado” e nada é alterado.
