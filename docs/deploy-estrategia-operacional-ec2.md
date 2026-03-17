# Estratégia operacional de deploy remoto — FCG Fenix (EC2)

Este documento descreve a estrutura esperada em cada EC2, os arquivos de configuração, o script de deploy, os comandos usados pelo SSM Run Command, rollback, limpeza de imagens e persistência do Postgres. O **usersapi** é o exemplo principal; gamesapi e paymentsapi seguem o mesmo padrão com pequenas variações.

---

## 1. Estrutura esperada em cada EC2

Cada instância EC2 dedicada a um serviço deve ter o diretório de aplicação em um path fixo, com os arquivos necessários para o Docker Compose e variáveis de ambiente.

### 1.1 Path padrão

| Serviço    | APP_DIR (diretório da aplicação) |
|-----------|-----------------------------------|
| usersapi  | `/opt/fcg-fenix/usersapi`         |
| gamesapi  | `/opt/fcg-fenix/gamesapi`         |
| paymentsapi | `/opt/fcg-fenix/paymentsapi`   |

### 1.2 Arquivos obrigatórios em `APP_DIR`

```
/opt/fcg-fenix/usersapi/
├── docker-compose.yml   # Define o serviço (imagem ECR + volume Postgres)
├── .env                 # ECR_REGISTRY, IMAGE_TAG, senhas, etc. (não versionado)
└── deploy.sh            # (opcional) Script local para deploy/rollback manual
```

- **docker-compose.yml**: usa variáveis do `.env` (ex.: `ECR_REGISTRY`, `IMAGE_TAG`) para definir a imagem a ser puxada e a porta.
- **.env**: contém o registro ECR, a tag da imagem e segredos (ex.: senha do Postgres). O GitHub Actions (SSM) pode atualizar `IMAGE_TAG` (e opcionalmente `ECR_REGISTRY`) antes de rodar `docker compose pull && docker compose up -d`.
- **deploy.sh**: conveniência para deploy ou rollback manual na EC2 (chamado opcionalmente; o deploy automático usa o script inline do SSM).

### 1.3 Permissões sugeridas

- O usuário que roda o SSM (ex.: `ec2-user` ou `ubuntu`) deve ter permissão para:
  - `docker login` no ECR (via IAM da instância ou credenciais configuradas).
  - Executar `docker compose` em `APP_DIR` (geralmente com `sudo`).
- O diretório `APP_DIR` pode ser ownership `root:root` ou do usuário do SSM; o script do SSM usa `sudo` para docker.

---

## 2. Exemplo de docker-compose.yml por serviço

A imagem publicada no ECR é a buildada com **Dockerfile.postgres**: um único container que sobe Postgres + API (.NET). Por isso o compose na EC2 tem **um único serviço** e um volume para persistir os dados do Postgres.

### 2.1 usersapi

```yaml
# /opt/fcg-fenix/usersapi/docker-compose.yml
# Imagem ECR = build Dockerfile.postgres (Postgres + API no mesmo container).
# Variáveis ECR_REGISTRY e IMAGE_TAG vêm do .env (atualizadas pelo SSM no deploy).

services:
  app:
    image: ${ECR_REGISTRY}:${IMAGE_TAG}
    container_name: fcg-fenix-usersapi
    environment:
      ASPNETCORE_ENVIRONMENT: Production
      ASPNETCORE_URLS: http://+:8080
      POSTGRES_USER: ${POSTGRES_USER:-postgres}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB:-fcg_users}
    volumes:
      - users_pgdata:/var/lib/postgresql/data
    ports:
      - "8080:8080"
    restart: unless-stopped

volumes:
  users_pgdata:
```

### 2.2 gamesapi

Trocar apenas: `container_name`, nome do volume, `POSTGRES_DB` e porta (se quiser manter 8080 por serviço, pode usar a mesma; o ALB faz o roteamento).

```yaml
services:
  app:
    image: ${ECR_REGISTRY}:${IMAGE_TAG}
    container_name: fcg-fenix-gamesapi
    environment:
      ASPNETCORE_ENVIRONMENT: Production
      ASPNETCORE_URLS: http://+:8080
      POSTGRES_USER: ${POSTGRES_USER:-postgres}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB:-fcg_games}
    volumes:
      - games_pgdata:/var/lib/postgresql/data
    ports:
      - "8080:8080"
    restart: unless-stopped

volumes:
  games_pgdata:
```

### 2.3 paymentsapi

```yaml
services:
  app:
    image: ${ECR_REGISTRY}:${IMAGE_TAG}
    container_name: fcg-fenix-paymentsapi
    environment:
      ASPNETCORE_ENVIRONMENT: Production
      ASPNETCORE_URLS: http://+:8080
      POSTGRES_USER: ${POSTGRES_USER:-postgres}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB:-fcg_payments}
    volumes:
      - payments_pgdata:/var/lib/postgresql/data
    ports:
      - "8080:8080"
    restart: unless-stopped

volumes:
  payments_pgdata:
```

Em produção, o ALB aponta para a porta exposta na EC2 (ex.: 8080); cada EC2 pode usar a mesma porta interna.

---

## 3. Exemplo de .env

O `.env` não deve ser versionado. Na EC2 ele é criado/atualizado na primeira configuração e pelo pipeline (SSM) a cada deploy (pelo menos `IMAGE_TAG`).

### 3.1 usersapi

```bash
# /opt/fcg-fenix/usersapi/.env
# ECR (atualizado pelo SSM no deploy; exemplo com valor inicial)
ECR_REGISTRY=123456789012.dkr.ecr.us-east-1.amazonaws.com/fcg-fenix-usersapi-ecr
IMAGE_TAG=latest

# Postgres (dentro do mesmo container)
POSTGRES_USER=postgres
POSTGRES_PASSWORD=SenhaSeguraAqui
POSTGRES_DB=fcg_users
```

Substituir `123456789012` e `us-east-1` pelo ID da conta e região reais. O SSM deve escrever `ECR_REGISTRY` e `IMAGE_TAG` (ex.: `IMAGE_TAG=github.sha`) antes de rodar `docker compose pull` e `up -d`, para que o compose use a imagem recém-publicada.

### 3.2 gamesapi / paymentsapi

Mesmo formato; mudar apenas:

- **gamesapi**: `ECR_REGISTRY=.../fcg-fenix-gamesapi-ecr`, `POSTGRES_DB=fcg_games`
- **paymentsapi**: `ECR_REGISTRY=.../fcg-fenix-paymentsapi-ecr`, `POSTGRES_DB=fcg_payments`

---

## 4. Exemplo de deploy.sh

Script opcional na EC2 para deploy ou rollback manual (sem depender do SSM). O deploy automático via GitHub Actions usa o script inline do SSM; o `deploy.sh` é útil para correções rápidas ou quando o SSM não está disponível.

```bash
#!/usr/bin/env bash
# /opt/fcg-fenix/usersapi/deploy.sh
# Uso: ./deploy.sh [IMAGE_TAG]
# Sem argumento: faz pull da tag atual em .env e sobe.
# Com argumento: atualiza .env com a nova tag, pull e sobe (deploy ou rollback).

set -e
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$APP_DIR"

if [ -n "$1" ]; then
  TAG="$1"
  if grep -q '^IMAGE_TAG=' .env 2>/dev/null; then
    sed -i "s/^IMAGE_TAG=.*/IMAGE_TAG=$TAG/" .env
  else
    echo "IMAGE_TAG=$TAG" >> .env
  fi
  echo "Using image tag: $TAG"
fi

# Login ECR (assumindo que a instância tem role IAM com permissão ECR)
AWS_REGION="${AWS_REGION:-us-east-1}"
ECR_REGISTRY=$(grep '^ECR_REGISTRY=' .env | cut -d= -f2-)
aws ecr get-login-password --region "$AWS_REGION" | sudo docker login --username AWS --password-stdin "${ECR_REGISTRY%/*}"

sudo docker compose pull
sudo docker compose up -d

echo "Deploy finished. Current tag: $(grep '^IMAGE_TAG=' .env 2>/dev/null | cut -d= -f2-)"
```

Para **gamesapi** e **paymentsapi**, usar o mesmo script; apenas o `APP_DIR` será o do serviço correspondente (o script usa o diretório onde está).

---

## 5. Comandos usados no SSM Run Command

O reusable workflow `deploy-ec2.yml` envia um único comando SSM que executa um script em base64 na EC2. Resumo do que esse script faz:

### 5.1 Variáveis de ambiente no script

- `AWS_DEFAULT_REGION` — região AWS (ex.: `us-east-1`)
- `ECR_REGISTRY` — URI do repositório ECR (ex.: `123456789012.dkr.ecr.us-east-1.amazonaws.com/fcg-fenix-usersapi-ecr`)
- `IMAGE_TAG` — tag da imagem (ex.: `github.sha`)
- `SERVICE` — nome do serviço: `usersapi`, `gamesapi` ou `paymentsapi`
- `APP_DIR` — `/opt/fcg-fenix/${SERVICE}`

### 5.2 Passos do script (inline no workflow)

1. **Login no ECR**
   ```bash
   aws ecr get-login-password --region $AWS_DEFAULT_REGION | sudo docker login --username AWS --password-stdin $ECR_REGISTRY
   ```
   (O login é feito no “registry” sem o path do repo; na prática usa-se o mesmo valor ou o host do ECR.)

2. **Se existir `docker-compose.yml` em `APP_DIR`**
   - **Recomendado**: antes de `pull`, escrever no `.env` o `ECR_REGISTRY` e `IMAGE_TAG` atuais (para o compose usar a tag do pipeline). Exemplo no workflow:
     - `echo "ECR_REGISTRY=$ECR_REGISTRY" > ${APP_DIR}/.env`
     - `echo "IMAGE_TAG=$IMAGE_TAG" >> ${APP_DIR}/.env`
     - (e acrescentar as demais variáveis já existentes em `.env` se não quiser sobrescrever o arquivo inteiro.)
   - Em seguida:
     ```bash
     (cd ${APP_DIR} && sudo docker compose pull && sudo docker compose up -d)
     ```

3. **Se não existir `docker-compose.yml`** (fallback)
   - `sudo docker pull ${ECR_REGISTRY}:${IMAGE_TAG}`
   - `sudo docker stop ${SERVICE}-app 2>/dev/null || true`
   - `sudo docker rm ${SERVICE}-app 2>/dev/null || true`
   - `sudo docker run -d --name ${SERVICE}-app -p 80:80 --restart unless-stopped ${ECR_REGISTRY}:${IMAGE_TAG}`

### 5.3 Documento SSM e parâmetros

- **Document**: `AWS-RunShellScript`
- **Comando**: o script acima é codificado em base64 e executado com:
  `echo <base64> | base64 -d | sudo bash`

Assim o SSM Run Command executa um único shell script que faz login, atualiza (ou cria) `.env` e roda o compose (ou o fallback com `docker run`).

---

## 6. Observações sobre rollback simples

- **Rollback = voltar para uma tag de imagem anterior.** A tag é o `github.sha` do commit anterior (ou outra tag conhecida).

1. **Via deploy.sh (na EC2)**  
   - SSH ou sessão SSM na instância:
     ```bash
     cd /opt/fcg-fenix/usersapi
     ./deploy.sh <commit-sha-anterior>
     ```
   - O script atualiza `IMAGE_TAG` no `.env`, faz `docker compose pull` e `up -d`.

2. **Via SSM manual**  
   - Executar o mesmo script usado pelo pipeline, mas com `IMAGE_TAG=<sha-anterior>` (e opcionalmente escrevendo no `.env` e rodando `docker compose up -d`).

3. **Via novo push no GitHub**  
   - Reverter o código e dar push na branch de deploy; o pipeline fará build e deploy da nova imagem (tag = novo `github.sha`).

4. **Boa prática**  
   - Manter um registro (ex.: em releases ou em um artefato) das últimas tags implantadas, para escolher rapidamente a tag de rollback.

---

## 7. Observações sobre limpeza de imagens antigas

O disco da EC2 pode encher com imagens Docker antigas. Recomendações:

- **Remover imagens não utilizadas (dangling e não referenciadas por nenhum container):**
  ```bash
  sudo docker image prune -f
  ```
- **Remover apenas imagens “dangling” (sem tag):**
  ```bash
  sudo docker image prune -f
  ```
  (o mesmo comando já remove dangling.)

- **Remover imagens do repositório ECR do serviço que não sejam a tag atual** (ex.: manter só as últimas N tags):
  - Pode ser feito por um job agendado na EC2 ou no pipeline, listando imagens no ECR e removendo as antigas (via AWS CLI ou política de lifecycle no ECR).
  - Na EC2, após cada deploy, rodar `sudo docker image prune -f` já libera espaço das imagens antigas que não estão mais em uso.

- **Cron sugerido (opcional)**  
  Ex.: todo dia às 3h:
  ```bash
  0 3 * * * root docker image prune -f >> /var/log/docker-prune.log 2>&1
  ```

---

## 8. Observações sobre persistência do Postgres no host

A imagem usada em produção (Dockerfile.postgres) sobe Postgres e a API no **mesmo container**. Os dados do Postgres precisam ficar fora do container para não se perder no `docker compose down` ou em recriações do container.

- **No docker-compose** isso é feito com um **volume nomeado** (ex.: `users_pgdata`) mapeado para `/var/lib/postgresql/data`:
  ```yaml
  volumes:
    - users_pgdata:/var/lib/postgresql/data
  volumes:
    users_pgdata:
  ```
  O Docker persiste esse volume no host (em geral em `/var/lib/docker/volumes/...`).

- **Backup**  
  - Fazer backup periódico do volume (ex.: `pg_dump` dentro do container ou export do volume).
  - Exemplo de dump:
    ```bash
    sudo docker exec fcg-fenix-usersapi pg_dump -U postgres -d fcg_users > backup_$(date +%Y%m%d).sql
    ```

- **Restore**  
  - Restaurar com `psql` ou `pg_restore` dentro do mesmo container (ou em um temporário com o mesmo volume).

- **Migrações**  
  - As migrações da aplicação .NET rodam no startup da API (se configurado); como o volume persiste, ao subir uma nova imagem com migrações, os dados permanecem e as migrações são aplicadas na abertura da API.

---

## Replicar para os outros serviços (gamesapi, paymentsapi)

1. **Estrutura**: criar em cada EC2 o diretório `/opt/fcg-fenix/<service>` com `docker-compose.yml`, `.env` e (opcional) `deploy.sh`.
2. **docker-compose.yml**: usar os exemplos da seção 2, ajustando `container_name`, nome do volume e `POSTGRES_DB` (e porta se necessário).
3. **.env**: mesmo formato do usersapi; alterar `ECR_REGISTRY` para o repositório ECR do serviço e `POSTGRES_DB` para `fcg_games` ou `fcg_payments`.
4. **deploy.sh**: copiar o mesmo script; funciona em qualquer `APP_DIR`.
5. **SSM**: o workflow já usa `service` (usersapi/gamesapi/paymentsapi) e `APP_DIR=/opt/fcg-fenix/${SERVICE}`; desde que os arquivos existam nesse path, o mesmo fluxo atende os três serviços.
6. **Rollback / limpeza / Postgres**: mesmas práticas; só trocar nomes de container e volume nos exemplos de comando.

Com isso, a estratégia operacional de deploy remoto nas EC2 do FCG Fenix fica unificada entre usersapi, gamesapi e paymentsapi.

---

## Referência dos exemplos

Os arquivos de exemplo (docker-compose, .env.example, deploy.sh) estão em:

- `docs/ec2-examples/usersapi/`
- `docs/ec2-examples/gamesapi/`
- `docs/ec2-examples/paymentsapi/`

Ver `docs/ec2-examples/README.md` para como copiá-los nas EC2.
