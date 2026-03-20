# Terraform — FCG Fenix

Estrutura Terraform do repositório de infraestrutura. Ver **docs/terraform-blueprint.md** para o blueprint completo (módulos, ordem, variáveis, outputs).

## Como executar

O root do Terraform é `terraform/environments/production`. A partir da raiz do repositório:

```bash
cd terraform/environments/production
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

Ou, a partir da raiz do repo:

```bash
terraform -chdir=terraform/environments/production init
terraform -chdir=terraform/environments/production plan -var-file=terraform.tfvars
terraform -chdir=terraform/environments/production apply -var-file=terraform.tfvars
```

## Antes do primeiro apply (backend remoto + CI)

1. **Bootstrap do backend (uma vez):** No GitHub → Actions → **Terraform Bootstrap (Backend S3 + DynamoDB)** → Run workflow. Isso cria o bucket `fcg-fenix-tfstate` e a tabela `fcg-fenix-tfstate-lock` na AWS. O backend já está habilitado em `environments/production/backend.tf`.
2. **Variáveis em CI:** Para Plan/Apply no GitHub Actions, use uma das opções:
   - **Secret `TFVARS_B64`:** conteúdo do `terraform.tfvars` em base64 (Settings → Secrets → TFVARS_B64). Ex.: `base64 -w0 terraform.tfvars` (Linux) e colar o resultado no secret.
   - **Ou** commitar `terraform.tfvars` no repositório (apenas se não tiver segredos).
3. **Local:** Copiar `terraform.tfvars.example` para `terraform.tfvars` e preencher (não versionar se tiver segredos).

## Destruir a infra (parar custos)

- **GitHub Actions:** workflow **Terraform Destroy (manual)** — só `workflow_dispatch`, com confirmação `DESTROY` e opção de plan sem aplicar. Ver README raiz do repositório, seção *Destruir infraestrutura*.
- **CLI:** `terraform plan -destroy` e `terraform destroy -var-file=terraform.tfvars` em `environments/production`.

## Lock do state (`Error acquiring the state lock`)

O backend S3 usa a tabela DynamoDB **`fcg-fenix-tfstate-lock`**. Um **apply/plan/destroy** interrompido (cancelamento no Actions, timeout, crash) pode deixar o lock **sem ser liberado**.

1. **Confirme** que **nenhum** workflow Terraform está em execução no GitHub Actions (Apply, Destroy, Plan em outra PR).
2. **Libere o lock** com a mesma pasta e credenciais que o CI usa:

   ```bash
   cd terraform/environments/production
   terraform init
   terraform force-unlock LOCK_ID
   ```

   Substitua `LOCK_ID` pelo UUID que aparece na mensagem de erro (ex.: `52ef7aef-6370-9fe0-2d18-e5f8567dd4dd`). O comando pede confirmação (`yes`).

3. **Não** use `-lock=false` no CI — dois applies ao mesmo tempo corrompem o state.

**Alternativa (console AWS):** DynamoDB → tabela `fcg-fenix-tfstate-lock` → localizar o item cujo `LockID` contém `production/terraform.tfstate` e apagar **só** se tiver certeza de que ninguém está rodando Terraform.

## Módulos

- `vpc` — VPC, subnets, IGW, NAT, route tables
- `security-groups` — SGs do ALB e das EC2
- `ecr` — Repositórios ECR por serviço
- `iam/github-oidc` — Role para GitHub Actions (OIDC)
- `iam/ec2-api` — Role + instance profile por API
- `ec2-api` — EC2 privada por API
- `alb` — ALB interno, listener, target groups
- `api-gateway` — HTTP API + VPC Link
- `ssm` — Parameter Store por serviço

Os arquivos `main.tf` dos módulos estão em modo blueprint (TODO); implementar conforme o blueprint.
