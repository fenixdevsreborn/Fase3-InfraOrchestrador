# Exemplos para deploy nas EC2 — FCG Fenix

Estes arquivos são **modelos** para copiar em cada EC2 no path `/opt/fcg-fenix/<service>/`.

- **usersapi** — exemplo completo: `docker-compose.yml`, `.env.example`, `deploy.sh`
- **gamesapi** — `docker-compose.yml`, `.env.example` (usar o mesmo `deploy.sh` do usersapi)
- **paymentsapi** — `docker-compose.yml`, `.env.example` (usar o mesmo `deploy.sh` do usersapi)

## Uso

1. Documento principal: [deploy-estrategia-operacional-ec2.md](../deploy-estrategia-operacional-ec2.md)
2. Em cada EC2, criar o diretório e copiar os arquivos:
   - `docker-compose.yml` → copiar do serviço correspondente
   - `.env` → copiar de `.env.example`, renomear para `.env` e preencher (principalmente senhas e ECR_REGISTRY)
   - `deploy.sh` → copiar de `usersapi/deploy.sh`, `chmod +x deploy.sh`
3. O pipeline (SSM) atualiza `ECR_REGISTRY` e `IMAGE_TAG` no `.env` a cada deploy.

## Porta 80 no host (evita 502 no API Gateway)

O ALB envia tráfego para a **porta 80** da EC2. O `docker-compose` deve publicar **`80:8080`** (não `8080:8080`). Sem isso, os targets ficam unhealthy ou o gateway retorna **502 Bad Gateway**.
