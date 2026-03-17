# GitHub Actions — FCG Fenix Infra

Workflows do repositório de infraestrutura: Terraform (plan/apply) e deploy remoto em EC2 via SSM. Autenticação na AWS via **OIDC** (sem chaves estáticas).

---

## 1. terraform-plan.yml

**Papel:** Rodar `terraform plan` em **pull requests** que alterem `terraform/**` ou o próprio workflow.

- **Trigger:** `pull_request` na branch `master`.
- **OIDC:** Assume a role informada em `vars.AWS_ROLE_ARN` (configurar em Settings → Variables do repositório).
- **Passos:** checkout → configurar AWS (OIDC) → setup Terraform → `terraform fmt -check` → `terraform init` → `terraform validate` → `terraform plan` com `-out=tfplan` e `-var-file=terraform.tfvars`.
- **Comentário no PR:** Comenta no PR o resultado do plan (format, init, validate, plan) e o log do plan em `<details>`.

**Configuração:** Criar variável de repositório `AWS_ROLE_ARN` (ARN da role OIDC). Opcional: `AWS_REGION` (default `us-east-1`). A role precisa de permissão para ler o backend do Terraform (ex.: S3 do state) e para `terraform plan`.

---

## 2. terraform-apply.yml

**Papel:** Aplicar mudanças de infraestrutura na **branch master** (ou execução manual), em ambiente protegido.

- **Trigger:** `push` na branch `master` (com alterações em `terraform/**` ou no workflow) ou `workflow_dispatch`.
- **Ambiente:** `environment: production` — use ambiente protegido no GitHub (Settings → Environments) para exigir aprovação manual se quiser.
- **OIDC:** Mesma role em `vars.AWS_ROLE_ARN`.
- **Passos:** checkout → configurar AWS → setup Terraform → `terraform init` → `terraform apply -auto-approve` com `-var-file=terraform.tfvars`.

**Configuração:** Mesmas variáveis do plan. A role precisa de permissão para aplicar Terraform (leitura/escrita nos recursos gerenciados e no state).

---

## 3. deploy-ec2.yml (reusable)

**Papel:** Deploy remoto em uma EC2 por serviço via **SSM Run Command**. Pensado para ser chamado pelos repositórios das APIs (usersapi, gamesapi, paymentsapi) após build e push da imagem para o ECR.

- **Trigger:** Apenas `workflow_call` — não roda sozinho; outro workflow chama este.
- **Inputs:** `aws_region`, `environment`, `service`, `repository` (URI do ECR), `image_tag`.
- **Secrets:** `AWS_ROLE_ARN` (obrigatório) — o **repositório chamador** deve ter esse secret; a role precisa de `ssm:SendCommand` e `ec2:DescribeInstances` (para obter o instance ID pelo tag `Name=fcg-fenix-{service}-ec2`).
- **Passos:**
  1. Configurar AWS (OIDC).
  2. Obter instance ID da EC2 pelo tag `fcg-fenix-{service}-ec2`.
  3. Enviar comando SSM `AWS-RunShellScript`: na EC2, login no ECR, pull da imagem com `image_tag`, e restart (docker compose se existir `docker-compose.yml` em `/opt/fcg-fenix/{service}`, senão `docker run`).

**Exemplo de chamada (no repo da API):**

```yaml
jobs:
  deploy:
    uses: org/fcg-fenix-infra-repo/.github/workflows/deploy-ec2.yml@master
    with:
      aws_region: us-east-1
      environment: production
      service: usersapi
      repository: 123456789012.dkr.ecr.us-east-1.amazonaws.com/fcg-fenix-usersapi-ecr
      image_tag: abc123
    secrets:
      AWS_ROLE_ARN: ${{ secrets.AWS_ROLE_ARN }}
```

---

## OIDC e variáveis

- **Repositório de infra:** Configurar `AWS_ROLE_ARN` (e opcionalmente `AWS_REGION`) em Settings → Variables.
- **Repositórios das APIs:** Configurar o **secret** `AWS_ROLE_ARN` (mesmo ARN da role de deploy) para poder chamar o reusable workflow.
- A role (`fcg-fenix-githubactions-role`) deve ter trust policy permitindo o `subject` do OIDC (ex.: `repo:org/fcg-fenix-infra-repo:ref:refs/heads/master` e os repos das APIs conforme necessário).
