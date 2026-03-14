# Guia de Bootstrap — Backend do Terraform

Este guia descreve como criar, uma vez por conta AWS, o bucket S3 e a tabela DynamoDB usados como backend remoto do Terraform (state e lock). Depois disso, cada ambiente (prod, staging, demo) usa uma **key de state diferente** no mesmo bucket.

---

## Pré-requisitos

- **AWS:** Conta ativa, credenciais configuradas (AWS CLI ou variáveis de ambiente) para o usuário/role que rodará o bootstrap.
- **Terraform:** >= 1.5.0 instalado localmente.

---

## Ordem de execução

### 1. Criar bucket S3 e tabela DynamoDB (bootstrap)

O diretório `bootstrap/` contém Terraform que cria apenas:

- Bucket S3 com versionamento e criptografia (AES256), bloqueio de acesso público.
- Tabela DynamoDB com chave primária `LockID` (String), billing PAY_PER_REQUEST.

O state deste Terraform fica **local** em `bootstrap/terraform.tfstate` (não usa S3).

```bash
cd bootstrap
terraform init
terraform plan -var="state_bucket_name=fcg-terraform-state-SEU-ACCOUNT-ID" -out=tfplan
terraform apply tfplan
```

Substitua `SEU-ACCOUNT-ID` pelo ID da conta AWS (o nome do bucket deve ser globalmente único). Ex.: `fcg-terraform-state-123456789012`.

### 2. Preencher backend.hcl por ambiente

Para cada ambiente (prod, staging, demo), edite o arquivo `environments/<env>/backend.hcl` e preencha:

- **bucket** — mesmo nome usado no bootstrap (ex.: `fcg-terraform-state-123456789012`).
- **dynamodb_table** — nome da tabela (default do bootstrap: `fcg-terraform-locks`).
- **key** — já está definida por ambiente (`fcg-infra/prod/terraform.tfstate`, etc.); não altere a key.
- **region** e **encrypt** — já preenchidos.

Você pode obter os valores com:

```bash
cd bootstrap
terraform output -raw state_bucket_name
terraform output -raw dynamodb_table_name
```

Remova qualquer placeholder `REPLACE-WITH-ACCOUNT-ID` do `backend.hcl` e coloque o nome real do bucket.

### 3. Rodar a stack principal

Na **raiz** do repositório:

```bash
export TF_VAR_environment=prod
terraform init -backend-config=environments/prod/backend.hcl
terraform plan -out=tfplan
terraform apply tfplan
```

Ou use os scripts: `./scripts/plan.sh prod` e `./scripts/apply.sh prod`. Os workflows do GitHub Actions fazem o init com `-backend-config=environments/${{ inputs.environment }}/backend.hcl` automaticamente.

---

## Checklist de bootstrap

- [ ] Bucket S3 criado (bootstrap) com versionamento e criptografia.
- [ ] Tabela DynamoDB criada com chave `LockID`.
- [ ] `environments/prod/backend.hcl` (e staging/demo) preenchidos com bucket e dynamodb_table reais, sem placeholder.
- [ ] IAM Role do GitHub (OIDC) com permissão no bucket (s3:GetObject, PutObject, DeleteObject, ListBucket) e na tabela (dynamodb:* para lock).

---

## Destruição do bootstrap

Só destrua o bootstrap se não houver mais nenhum state da stack principal usando esse bucket. Esvazie o bucket (ou remova os objetos das keys em uso) e depois:

```bash
cd bootstrap
terraform destroy
```

Ver também: [bootstrap/README.md](../bootstrap/README.md).
