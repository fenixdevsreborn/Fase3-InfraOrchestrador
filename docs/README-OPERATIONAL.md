# FCG Cloud Platform — Guia operacional

Este guia explica, de forma prática e em linguagem acessível, como a infraestrutura e os deploys funcionam na FCG Cloud Platform e o que você precisa fazer no dia a dia. Se você está começando, leia na ordem: visão geral → checklists → detalhes.

---

## Visão geral em 4 passos

1. **Cada serviço (Users API, Games API, Payments API, Notification Lambda)** tem um workflow de **CI** (build + testes) e um de **publicar imagem**. Quando o código vai para a branch `main`, o repositório do serviço faz o **build** da imagem Docker e envia (**push**) para o **ECR** (registro de imagens da AWS).
2. **Depois do push**, o mesmo workflow do serviço **avisa o orquestrador** (este repositório) enviando um evento `deploy-request` com o nome do serviço e a tag da imagem.
3. **O orquestrador** (Fase3-InfraOrchestrador) recebe esse evento, atualiza a variável Terraform daquele serviço e roda **terraform plan** e **terraform apply**. Assim, só a imagem daquele serviço é atualizada na infra.
4. **Terraform** é quem realmente faz o **deploy**: ele compara o estado atual com o desejado e atualiza os recursos na AWS (por exemplo, a Lambda passa a usar a nova imagem).

Nenhum deploy é feito “na mão” no console da AWS para as imagens dos serviços: tudo passa por **build → ECR → orquestrador → Terraform**.

---

## Como cada serviço faz build

Cada repositório de aplicação (Fase3-UsersAPI, Fase3-GamesAPI, Fase3-PaymentsAPI, Fase3-NotificationLambda) tem:

- **Workflow de CI** (`ci.yml`): roda em todo **push** e **pull request** na branch principal. Faz:
  - `dotnet restore`
  - `dotnet build -c Release`
  - `dotnet test -c Release`  
  Objetivo: garantir que o código compila e os testes passam. **Não publica imagem nem faz deploy.**

- **Workflow de publicar imagem** (`publish-image.yml`): roda quando há **push na branch `main`**. Faz:
  - Login na AWS (via OIDC, sem senha no código)
  - Login no ECR
  - **Build** da imagem Docker (`docker build` com o Dockerfile do repositório)
  - **Push** da imagem para o ECR com tag = SHA curto do commit (ex.: `a1b2c3d`)
  - Em produção, também faz push da tag `latest`
  - **Disparo** do orquestrador (próxima seção)

Ou seja: o **build** da aplicação acontece no GitHub Actions do próprio repositório do serviço; a imagem é construída com Docker e enviada para o ECR.

---

## Como a imagem é enviada para o ECR

1. O workflow **Publish image** do serviço usa **OIDC** para assumir uma **IAM Role** na AWS (secret `AWS_ROLE_ARN_ECR` no repositório do serviço). Com isso, não é necessário guardar access key no GitHub.
2. O passo **Login to ECR** usa a ação `aws-actions/amazon-ecr-login`; o Actions obtém um token temporário e faz `docker login` no registro ECR.
3. **Região:** a variable `AWS_REGION` define a região do ECR. Se não estiver definida, o padrão é **`us-east-1`** (Virginia). Todos os workflows (UsersAPI, GamesAPI, PaymentsAPI, NotificationLambda) usam esse mesmo default.
4. **Nome do repositório ECR:** vem da variable `ECR_REPOSITORY_NAME`. Se não estiver definida, o padrão é **`fcg/fase03`**. Para usar outro repositório (ex.: `fcg-prod-users-api`), defina a variable no repositório do serviço. O nome deve ser o mesmo que o Terraform criou no orquestrador (output `ecr_repository_urls` ou nome do recurso).
5. A imagem é construída e enviada com:
   - **Tag principal:** SHA curto do commit (ex.: `a1b2c3d`)
   - **Tag `latest`:** apenas em ambiente prod (configurável por variable `ENVIRONMENT`)

Se o push para o ECR falhar, confira: OIDC configurado no repositório do serviço, role com permissão de `ecr:PutImage` (e demais permissões ECR), e, se não usar o padrão, variable `ECR_REPOSITORY_NAME` igual ao nome do repositório no ECR.

---

## Como o orquestrador recebe a atualização

Depois de fazer o push da imagem, o workflow do **serviço** chama a API do GitHub para disparar um evento no repositório **Fase3-InfraOrchestrador**:

- **Tipo de evento:** `repository_dispatch` com `event_type: deploy-request`
- **Payload (exemplo):** `service_name`, `image_tag`, `image_uri`, `commit_sha`, `environment`

No orquestrador, o workflow **Deploy from service update** está configurado com `on.repository_dispatch.types: [deploy-request]`. Quando o evento chega:

1. O workflow **normaliza** o payload (vindo de `repository_dispatch` ou de `workflow_call`).
2. **Valida** o `service_name` (só aceita: users-api, games-api, payments-api, notification-lambda).
3. **Atualiza** o arquivo `image_tags.auto.tfvars`: altera **apenas** a linha da variável daquele serviço para a nova tag (ex.: `ecr_image_tag_users_api = "a1b2c3d"`).
4. Roda **terraform init**, **validate**, **plan** e **apply** com esse arquivo.
5. O Terraform atualiza só o recurso cuja imagem mudou (por exemplo, a função Lambda da notificação).

Para o serviço poder disparar esse evento, ele precisa de um **PAT** (Personal Access Token) com permissão de enviar `repository_dispatch` no repositório do orquestrador — configurado como secret **ORCHESTRATOR_REPO_TOKEN** no repositório do **serviço**, e a variable **ORCHESTRATOR_REPO** (ex.: `sua-org/Fase3-InfraOrchestrador`).

---

## Como o Terraform faz o deploy

O Terraform não “sabe” sozinho que uma nova imagem foi publicada. Ele age em dois cenários:

- **Deploy automático (após evento do serviço):** o workflow **Deploy from service update** atualiza `image_tags.auto.tfvars` e roda `terraform plan` e `terraform apply`. O Terraform lê as variáveis (incluindo as tags de imagem), compara com o state e atualiza apenas o recurso cuja imagem mudou (ex.: Lambda com nova `image_uri`).
- **Deploy manual:** alguém roda o workflow **Terraform Apply** (ou `terraform apply` local) com as variáveis desejadas; o Terraform aplica a infra ou só as mudanças de imagem informadas.

Em ambos os casos, o “deploy” é: **terraform apply** (ou aplicação do plano gerado por `terraform plan`). O Terraform envia para a AWS as alterações necessárias (por exemplo, nova imagem na Lambda). Não há um script separado de “deploy”: o deploy **é** o apply do Terraform.

---

## Como rodar Terraform plan manual

Para **só ver** o que mudaria, sem aplicar nada:

1. No GitHub: repositório **Fase3-InfraOrchestrador** → **Actions**.
2. Selecione o workflow **Terraform Plan**.
3. Clique em **Run workflow**.
4. Escolha o **environment** (prod, staging ou demo).
5. Clique no botão verde **Run workflow**.
6. Quando terminar, abra a run e veja o log do step **Terraform Plan**. Se quiser, baixe o **artifact** (tfplan, plan.txt, plan.log) para revisar o plano.

Nada é alterado na AWS; o plan só mostra a diferença entre o state atual e a configuração atual (incluindo `image_tags.auto.tfvars` e variáveis de ambiente).

---

## Como rodar Terraform apply manual

Para **aplicar** a infra (toda ou só atualizar imagens):

1. **Actions** → **Terraform Apply** → **Run workflow**.
2. Escolha o **environment** (prod, staging ou demo).
3. (Opcional) Preencha um ou mais campos de imagem:
   - **users_api_image**
   - **games_api_image**
   - **payments_api_image**
   - **notification_lambda_image**  
   Deixe vazio para não alterar a tag daquele serviço.
4. Clique em **Run workflow**.

O workflow faz: init → validate → apply -auto-approve. Se você informou alguma tag de imagem, ele atualiza o `image_tags.auto.tfvars` (ou o equivalente) e aplica; caso contrário, aplica o estado já definido nos arquivos/state.

---

## Como rodar Terraform destroy manual

Para **destruir** todo o ambiente (remover recursos da AWS):

1. **Actions** → **Terraform Destroy** → **Run workflow**.
2. Escolha o **environment** que será destruído (prod, staging ou demo).
3. No campo **confirm_destroy**, digite **exatamente**: `DESTROY` (tudo em maiúsculo).
4. Clique em **Run workflow**.

Se a confirmação estiver correta, o workflow roda **terraform init** e **terraform destroy -auto-approve**. Se digitar qualquer outra coisa, um job “Destroy não confirmado” aparece e **nada** é destruído.

**Atenção:** destroy é irreversível. Use só quando for descomissionar o ambiente. Recomenda-se usar **Environment protection rules** (required reviewers) para o workflow de destroy.

---

## Como fazer rollback para uma imagem anterior

Se uma nova imagem de um serviço deu problema e você quer voltar para a versão anterior:

1. **Descubra a tag que estava antes:**  
   No orquestrador, você pode consultar o state ou o último `terraform output` (ou artifact do último apply). Exemplo:
   ```bash
   terraform output -json service_image_tags
   ```
   Ou use um arquivo/artifact onde sua equipe guarda as tags aplicadas.

2. **Volte para essa tag:**
   - **Pelo GitHub Actions:** **Terraform Apply** → Run workflow → no campo daquele serviço (ex.: **notification_lambda_image**), coloque a **tag anterior** (ex.: `e6d5c4b`). Deixe os outros vazios. Execute. O Terraform atualiza só aquele serviço para a imagem antiga.
   - **Pelo Terraform local:**  
     Altere só a linha do serviço em `image_tags.auto.tfvars` para a tag anterior e rode:
     ```bash
     terraform apply -auto-approve -var-file=image_tags.auto.tfvars
     ```
     Ou use `-var` para um único serviço:
     ```bash
     terraform apply -auto-approve -var-file=image_tags.auto.tfvars -var="ecr_image_tag_notification_lambda=e6d5c4b"
     ```

A imagem antiga precisa ainda existir no ECR (não ter sido apagada por política de lifecycle). Por isso é importante manter retenção de algumas imagens no ECR.

---

## GitHub Secrets e Variables necessários

### No repositório **Fase3-InfraOrchestrador** (orquestrador)

| Nome | Tipo | Obrigatório | Uso |
|------|------|-------------|-----|
| `AWS_ROLE_ARN_TERRAFORM` | Secret | Sim (com OIDC) | ARN da IAM Role que o GitHub assume via OIDC para rodar Terraform (acessar S3 do state, DynamoDB, criar/alterar recursos na AWS). |
| `TF_VAR_POSTGRES_MASTER_PASSWORD` | Secret | Se usar RDS | Senha do PostgreSQL; passada como `TF_VAR_postgres_master_password` para o Terraform. Não coloque em tfvars commitados. |
| `AWS_REGION` | Variable | Não (default us-east-1) | Região AWS usada pelo Terraform. |

Se **não** usar OIDC: seria necessário usar secrets `AWS_ACCESS_KEY_ID` e `AWS_SECRET_ACCESS_KEY` (não recomendado).

### Em cada repositório de **serviço** (Users API, Games API, etc.)

| Nome | Tipo | Obrigatório | Uso |
|------|------|-------------|-----|
| `AWS_ROLE_ARN_ECR` | Secret | Sim (para publicar imagem) | ARN da IAM Role para OIDC; a role precisa de permissão para push no ECR. |
| `ORCHESTRATOR_REPO_TOKEN` | Secret | Sim (para disparar deploy) | PAT com permissão de enviar `repository_dispatch` no repositório do orquestrador. |
| `ECR_REPOSITORY_NAME` | Variable | Sim (para publish) | Nome do repositório no ECR (ex.: `fcg-prod-users-api`), igual ao criado pelo Terraform. |
| `ORCHESTRATOR_REPO` | Variable | Sim (para trigger) | Repositório do orquestrador no formato `owner/repo` (ex.: `minha-org/Fase3-InfraOrchestrador`). |
| `AWS_REGION` | Variable | Não | Região do ECR (ex.: `us-east-1`). |
| `SERVICE_NAME` | Variable | Depende do workflow | Nome do serviço no payload (ex.: `users-api`). Pode estar fixo no workflow. |
| `ENVIRONMENT` | Variable | Não | Ambiente (ex.: `prod`) para lógica condicional (ex.: push da tag `latest`). |

---

## Como configurar OIDC entre GitHub e AWS

OIDC permite que o GitHub Actions **assuma uma IAM Role** na AWS sem precisar de access key fixa. Passos em linguagem prática:

### 1. Criar o IdP OIDC no IAM (uma vez por conta AWS)

1. No console AWS: **IAM** → **Identity providers** → **Add provider**.
2. **Provider type:** OpenID Connect.
3. **Provider URL:** `https://token.actions.githubusercontent.com`
4. **Audience:** `sts.amazonaws.com` (ou o que a documentação do GitHub indicar).
5. Salvar.

### 2. Criar a IAM Role que o GitHub vai assumir

1. **IAM** → **Roles** → **Create role**.
2. **Trusted entity type:** Custom trust policy.
3. **Trust policy** (ajuste `ACCOUNT_ID`, `ORG` e `REPO`):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:ORG/REPO:*"
        }
      }
    }
  ]
}
```

- Para **orquestrador:** use o repo `ORG/Fase3-InfraOrchestrador`. A role precisa de permissões para Terraform (S3 do state, DynamoDB, ec2, lambda, ecr, api gateway, etc.).
- Para **cada serviço:** use o repo do serviço (ex.: `ORG/Fase3-UsersAPI`). A role precisa de permissão para `ecr:GetAuthorizationToken` e para o ECR (PutImage, BatchCheckLayerAvailability, etc.).

4. Anexar as **policies** necessárias (ex.: política que permite acesso ao bucket do state, DynamoDB, e recursos que o Terraform cria; ou política ECR para os serviços).

5. Copiar o **ARN da role** e colocar no secret correspondente no GitHub:
   - Orquestrador: **AWS_ROLE_ARN_TERRAFORM**
   - Serviço: **AWS_ROLE_ARN_ECR**

### 3. No repositório no GitHub

- **Secrets:** criar **AWS_ROLE_ARN_TERRAFORM** (orquestrador) ou **AWS_ROLE_ARN_ECR** (serviço) com o ARN da role (ex.: `arn:aws:iam::123456789012:role/github-fcg-terraform`).
- Os workflows já usam `aws-actions/configure-aws-credentials@v4` com `role-to-assume`. Não é necessário configurar `AWS_ACCESS_KEY_ID` nem `AWS_SECRET_ACCESS_KEY` quando se usa OIDC.

---

## Erros comuns e o que verificar

| Situação | O que pode ser | O que fazer |
|----------|----------------|-------------|
| **Terraform plan/apply falha com “failed to get existing workspace”** | Backend S3 não configurado ou inacessível. | Preencher `environments/<env>/backend.hcl`; rodar o bootstrap se necessário. Garantir que a role OIDC tem permissão no bucket e na tabela DynamoDB. Ver [BOOTSTRAP.md](BOOTSTRAP.md). |
| **“Error acquiring the state lock”** | Outra run (ou alguém local) está com o state travado. | Esperar a outra execução terminar ou, se for seguro, remover o lock na tabela DynamoDB (cuidado em time). |
| **Push para ECR falha com “no basic auth credentials”** | Login no ECR falhou (role sem permissão ou região errada). | Verificar `AWS_ROLE_ARN_ECR`, região e permissões da role (ecr:GetAuthorizationToken e ecr:PutImage, etc.). |
| **“Repository not found” ou 404 no ECR** | Nome do repositório diferente do que existe na AWS. | Conferir variable `ECR_REPOSITORY_NAME` no repo do serviço; deve ser igual ao nome do repositório criado pelo Terraform (ex.: output `ecr_repository_urls`). |
| **Orquestrador não dispara / “repository_dispatch” não roda** | Token ou repo errado; ou workflow não existe. | No **serviço:** conferir secret `ORCHESTRATOR_REPO_TOKEN` (PAT com permissão repo) e variable `ORCHESTRATOR_REPO` (owner/repo). No **orquestrador:** workflow deve ter `on.repository_dispatch.types: [deploy-request]`. |
| **Destroy não executa; aparece “Destroy não confirmado”** | Campo de confirmação diferente de `DESTROY`. | Digitar exatamente `DESTROY` em maiúsculo no campo **confirm_destroy**. |
| **Terraform apply falha com “password” ou “postgres”** | Senha do RDS não passada ou secret errado. | Definir secret `TF_VAR_POSTGRES_MASTER_PASSWORD` no orquestrador (e não commitar a senha em tfvars). |
| **Role OIDC: “Not authorized to perform sts:AssumeRoleWithWebIdentity”** | Trust policy não permite o repo ou o audience está errado. | Ajustar a condition `token.actions.githubusercontent.com:sub` para o repo correto (`repo:ORG/REPO:*`) e o audience para `sts.amazonaws.com`. |

---

## Checklist — Setup inicial

Use esta lista antes de fazer o primeiro deploy.

- [ ] **AWS:** Conta AWS ativa; região definida (ex.: us-east-1).
- [ ] **Terraform state:** Bucket S3 e tabela DynamoDB criados via `bootstrap/`; `environments/<env>/backend.hcl` preenchido para cada ambiente (ver [BOOTSTRAP.md](BOOTSTRAP.md)).
- [ ] **OIDC na AWS:** Identity provider configurado (`token.actions.githubusercontent.com`); IAM Role criada com trust policy para o repositório do orquestrador; permissões da role suficientes para Terraform (S3, DynamoDB, EC2, Lambda, ECR, API Gateway, etc.).
- [ ] **GitHub — orquestrador:** Secret `AWS_ROLE_ARN_TERRAFORM` com o ARN da role; variable `AWS_REGION` (opcional); se usar RDS, secret `TF_VAR_POSTGRES_MASTER_PASSWORD`.
- [ ] **GitHub — cada serviço:** Secret `AWS_ROLE_ARN_ECR` (role com permissão ECR); secret `ORCHESTRATOR_REPO_TOKEN` (PAT para repository_dispatch); variables `ECR_REPOSITORY_NAME`, `ORCHESTRATOR_REPO`; opcionalmente `SERVICE_NAME`, `ENVIRONMENT`, `AWS_REGION`.
- [ ] **Orquestrador:** Arquivo `image_tags.auto.tfvars` existe ou existe `image_tags.auto.tfvars.example` (o workflow pode criar a partir do exemplo).
- [ ] **Terraform:** Pelo menos uma vez, rodar `terraform init -backend-config=environments/<env>/backend.hcl` (local ou via workflow) para o backend e providers ficarem configurados.

---

## Checklist — Primeiro deploy

Use esta lista para o primeiro deploy completo da infra e das imagens.

- [ ] **Orquestrador:** Rodar **Terraform Plan** manual (Actions) para o ambiente desejado; revisar o plano (criação de VPC, ECR, SQS, Lambda, etc.).
- [ ] **Orquestrador:** Rodar **Terraform Apply** manual; escolher o environment; deixar imagens vazias ou com `latest` se já houver tfvars. Confirmar que o apply terminou com sucesso.
- [ ] **Outputs:** Anotar ou salvar os outputs importantes (ex.: `ecr_repository_urls`, `api_gateway_endpoint`). Configurar nos repositórios dos serviços a variable `ECR_REPOSITORY_NAME` com o nome correto do repositório (ex.: `fcg-prod-users-api`).
- [ ] **Serviços:** Em cada repositório de serviço, garantir que o workflow **Publish image** está habilitado e que OIDC + `ORCHESTRATOR_REPO_TOKEN` e `ORCHESTRATOR_REPO` estão configurados.
- [ ] **Primeira imagem:** Fazer um push na branch `main` de um dos serviços (ou rodar manualmente o workflow Publish image). Verificar no ECR se a imagem apareceu e no orquestrador se a run **Deploy from service update** rodou e aplicou a nova tag.
- [ ] **Validação:** Conferir no console AWS (ou via API) que o recurso (ex.: Lambda) está usando a imagem esperada; testar endpoint/health se aplicável.

---

## Checklist — Destruição do ambiente

Use esta lista quando for **descomissionar** o ambiente (destruir recursos).

- [ ] **Comunicar** a equipe; garantir que ninguém depende do ambiente.
- [ ] **Backup:** Se precisar de dados (ex.: RDS), fazer backup antes.
- [ ] **S3:** Se o bucket do frontend (ou outro) tiver objetos, esvaziar antes do destroy (ou o Terraform pode falhar ou deixar bucket não vazio). Ex.: `aws s3 rm s3://NOME_DO_BUCKET --recursive`.
- [ ] **Orquestrador:** Actions → **Terraform Destroy** → Run workflow.
- [ ] **Environment:** Escolher o ambiente a ser destruído (prod, staging, demo).
- [ ] **Confirmação:** Digitar exatamente **DESTROY** (maiúsculo) no campo **confirm_destroy**.
- [ ] **Executar:** Clicar em Run workflow e acompanhar a run; o job de destroy roda `terraform destroy -auto-approve`.
- [ ] **Verificar:** Após a conclusão, conferir no console AWS que os recursos foram removidos (ou que não restou nada crítico). State do Terraform deixa de existir para esse workspace/state file após o destroy.

---

Para decisões de arquitetura, detalhes dos workflows e da API de eventos, veja os outros documentos em **docs/** (DECISIONS.md, WORKFLOWS-OPERATION.md, DEPLOY-FROM-SERVICE-UPDATE.md, IMAGES-AND-ROLLBACK.md).
