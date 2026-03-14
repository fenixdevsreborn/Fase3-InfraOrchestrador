# Bootstrap — Backend do Terraform (S3 + DynamoDB)

Este diretório provisiona **apenas** os recursos necessários para o backend remoto do Terraform da FCG:

- **Bucket S3** — armazenamento do state (versionamento e criptografia habilitados)
- **Tabela DynamoDB** — lock do state (chave primária `LockID`)

Execute o bootstrap **uma vez por conta AWS** (ou por região, se usar múltiplas regiões). O state deste próprio Terraform fica em **backend local** (`terraform.tfstate` dentro de `bootstrap/`).

## Ordem de execução

1. **Criar bucket e DynamoDB (este diretório)**
   ```bash
   cd bootstrap
   terraform init
   terraform plan -out=tfplan
   terraform apply tfplan
   ```
2. **Configurar backend por ambiente**  
   Use os outputs para preencher `environments/<env>/backend.hcl` (bucket, key, region, dynamodb_table). A key deve ser diferente por ambiente, por exemplo: `fcg-infra/prod/terraform.tfstate`, `fcg-infra/staging/terraform.tfstate`, `fcg-infra/demo/terraform.tfstate`.
3. **Rodar a stack principal**  
   Na raiz do repositório (ou em cada `environments/<env>/` quando usar root por ambiente), use `terraform init -backend-config=environments/<env>/backend.hcl` e depois `plan`/`apply`.

## Variáveis

| Variável | Obrigatório | Descrição |
|----------|-------------|-----------|
| `state_bucket_name` | Sim | Nome do bucket S3 (globalmente único). Ex: `fcg-terraform-state-123456789012` |
| `project_name` | Não | Prefixo de tags (default: `fcg`) |
| `aws_region` | Não | Região AWS (default: `us-east-1`) |
| `dynamodb_table_name` | Não | Nome da tabela DynamoDB (default: `fcg-terraform-locks`) |
| `tags` | Não | Tags adicionais |

## Exemplo

```bash
cd bootstrap
terraform init
terraform plan -var="state_bucket_name=fcg-terraform-state-123456789012" -out=tfplan
terraform apply tfplan
```

Depois, em `environments/prod/backend.hcl`:

```hcl
bucket         = "fcg-terraform-state-123456789012"
key            = "fcg-infra/prod/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "fcg-terraform-locks"
encrypt        = true
```

## Segurança

- O bucket bloqueia acesso público.
- Criptografia AES256 no S3.
- Versionamento habilitado (permite recuperar versões anteriores do state).
- A IAM Role usada pelo GitHub Actions (OIDC) precisa de permissão em `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`, `s3:ListBucket` no bucket e `dynamodb:*` na tabela (ou o mínimo necessário para lock).

## Destruição

Para remover o bucket e a tabela:

```bash
cd bootstrap
terraform destroy
```

**Atenção:** O bucket deve estar vazio (nenhum state de ambiente ainda referenciando ou objetos apagados). Se a stack principal já estiver usando este backend, migre ou remova os states antes de destruir o bootstrap.
