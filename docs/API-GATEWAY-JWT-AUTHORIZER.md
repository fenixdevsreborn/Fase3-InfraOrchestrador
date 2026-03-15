# API Gateway HTTP API — JWT Authorizer nativo (Users API como emissor)

Este documento descreve a configuração do **JWT authorizer nativo** do API Gateway HTTP API (v2) usando a **Users API** como emissor de tokens (RS256, OIDC discovery, JWKS). Sem Lambda Authorizer e sem Cognito.

---

## 1. Visão geral

- **Emissor:** Users API expõe `/.well-known/openid-configuration` e `/.well-known/jwks.json`.
- **API Gateway:** valida o JWT no edge (issuer, audience, assinatura via JWKS), opcionalmente escopos por rota.
- **Fluxo:** cliente obtém token em `POST /auth/login` (Users API) → envia `Authorization: Bearer <token>` nas requisições → API Gateway valida e encaminha para a integração (Lambda/HTTP backend).

O API Gateway **busca a chave pública** usando o documento OIDC do issuer: acessa `{issuer}/.well-known/openid-configuration`, lê o `jwks_uri` e faz o download do JWKS. Suporta apenas **RSA**; cache das chaves por **até 2 horas**.

---

## 2. Valores para preencher no API Gateway

### 2.1 Console (Authorizers → Create → JWT)

| Campo | Valor | Observação |
|-------|--------|------------|
| **Name** | `fcg-jwt-users` | Nome identificador do authorizer. |
| **Identity source** | `$request.header.Authorization` | Cabeçalho onde está o Bearer token. |
| **Issuer** | URL base da Users API (ex.: `https://users-api.seudominio.com`) | **Sem** barra final. Deve ser exatamente o valor do claim `iss` do token. |
| **Audience** | `fcg-cloud-platform` | Um ou mais valores; o token deve ter `aud` igual a um deles. |

**Importante:** o **Issuer** deve ser a **URL real** da Users API em produção (ex.: `https://users-api.seudominio.com`). Em desenvolvimento, use a URL onde a Users API está exposta (ex.: `https://localhost:5001` se o gateway conseguir acessá-la). O API Gateway usa esse issuer para resolver o OIDC discovery e, em seguida, o `jwks_uri`.

### 2.2 AWS CLI (create-authorizer)

```bash
aws apigatewayv2 create-authorizer \
  --api-id <API_ID> \
  --name fcg-jwt-users \
  --authorizer-type JWT \
  --identity-source '$request.header.Authorization' \
  --jwt-configuration "Audience=fcg-cloud-platform,Issuer=https://users-api.seudominio.com"
```

- **Issuer:** substituir `https://users-api.seudominio.com` pela URL base real da Users API.
- **Audience:** deve ser o mesmo configurado na Users API ao emitir o token (ex.: `fcg-cloud-platform`).

### 2.3 Identity source

- **Recomendado:** `$request.header.Authorization`.
- O token pode ser enviado **com** ou **sem** o prefixo `Bearer `; o API Gateway aceita os dois formatos quando o identity source é o header `Authorization`.
- Não usar query string para token em produção (risco de vazamento em logs).

---

## 3. Matriz de rotas: públicas vs protegidas

Assume-se que o API Gateway expõe as rotas dos backends (Users, Games, Payments) com o mesmo path que as APIs (ex.: rota `/auth/login` no gateway encaminha para a Users API).

### 3.1 Rotas **públicas** (sem JWT authorizer)

| Método | Rota | Motivo |
|--------|------|--------|
| POST | `/auth/login` | Obtenção do token. |
| GET | `/.well-known/openid-configuration` | Discovery OIDC (consumido por clientes e pelo próprio gateway). |
| GET | `/.well-known/jwks.json` | JWKS (chaves públicas). |
| GET | `/api/discovery` | Discovery da API (Users); opcional. |
| POST | `/payments/webhooks/provider` | Callback do provedor de pagamento; validação por outro meio (ex.: assinatura). |
| POST | `/internal/library/add-from-payment` | Chamada interna (ex.: serviço a serviço com API key ou rede privada). |

**Ação:** essas rotas **não** devem ter authorizer JWT associado; usar "NONE" ou não anexar authorizer.

### 3.2 Rotas **protegidas** (com JWT authorizer)

Todas as demais rotas devem exigir o JWT authorizer `fcg-jwt-users`.

| API | Método | Rota (exemplo) | Observação |
|-----|--------|----------------|-------------|
| Users | GET | `/users` | Admin. |
| Users | GET | `/users/{id}` | Admin. |
| Users | POST/PUT/DELETE | `/users/*` | Admin. |
| Users | GET/PUT/DELETE | `/users/me` | Usuário autenticado. |
| Games | GET | `/games`, `/games/{id}`, `/games/search`, `/games/recommendations` | Autenticado. |
| Games | POST | `/games/{id}/purchase` | Autenticado. |
| Games | POST/PUT/PATCH/DELETE | `/games/*` | Admin. |
| Games | GET/POST/PUT/DELETE | `/me/library/*` | Autenticado. |
| Payments | POST | `/payments` | Autenticado. |
| Payments | GET | `/payments/me`, `/payments/{id}` | Autenticado. |
| Payments | POST | `/payments/{id}/confirm`, `/payments/{id}/fail` | Autenticado. |
| Payments | GET | `/payments/{id}/audit` | Autenticado. |

**Ação:** em cada rota protegida, anexar o authorizer `fcg-jwt-users` e, quando fizer sentido, configurar **Authorization scopes** (ver seção 4).

---

## 4. Scopes por rota (exemplo)

O API Gateway permite definir **Authorization scopes** por rota. O token deve conter no claim `scope` (ou `scp`) **pelo menos um** dos scopes da rota.

Scopes usados na plataforma FCG (ex.: `users:read`, `users:write`, `games:read`, `games:write`, `payments:read`, `payments:write`, `admin`).

### 4.1 Exemplo de mapeamento rota → scopes

| Rota (método + path) | Scopes na rota (pelo menos um) |
|----------------------|---------------------------------|
| GET `/users`, GET `/users/{id}` | `users:read` ou `admin` |
| POST/PUT/DELETE `/users/*` | `users:write` ou `admin` |
| GET `/users/me` | `users:read` ou `admin` |
| PUT/DELETE `/users/me` | `users:write:me` ou `admin` |
| GET `/games`, `/games/{id}`, `/games/search`, `/games/recommendations` | `games:read` |
| POST `/games/{id}/purchase` | `games:read`, `payments:write` (ou só `games:read`) |
| POST/PUT/PATCH/DELETE `/games/*` | `games:write` ou `admin` |
| GET/POST/PUT/DELETE `/me/library/*` | `games:read` (e `games:write` para alterações) |
| POST `/payments` | `payments:write` |
| GET `/payments/me`, GET `/payments/{id}` | `payments:read` |
| POST `/payments/{id}/confirm`, `/payments/{id}/fail` | `payments:write` |
| GET `/payments/{id}/audit` | `payments:read` ou `admin` |

**Configuração no console:** em cada rota → Attach authorizer → selecionar `fcg-jwt-users` → em "Authorization scopes" informar os scopes (ex.: `games:read`).

**CLI (exemplo):**

```bash
aws apigatewayv2 update-route \
  --api-id <API_ID> \
  --route-id <ROUTE_ID> \
  --authorization-type JWT \
  --authorizer-id <AUTHORIZER_ID> \
  --authorization-scopes "games:read"
```

Se não quiser restringir por scope no gateway, deixe **Authorization scopes** vazio; nesse caso o gateway só valida issuer, audience e assinatura (a autorização por role/scope fica nas APIs).

---

## 5. Checklist de testes manuais

- [ ] **Discovery e JWKS acessíveis**  
  `GET https://<users-api-url>/.well-known/openid-configuration` e `GET https://<users-api-url>/.well-known/jwks.json` retornam 200 e JSON válido; o `issuer` do discovery é a URL configurada no authorizer.

- [ ] **Login e token**  
  `POST /auth/login` (body com credenciais) retorna 200 e um `accessToken` (ou campo equivalente); decodificar o JWT e conferir `iss`, `aud`, `alg: RS256`, `kid` no header.

- [ ] **Rota pública sem token**  
  `GET /.well-known/openid-configuration` e `POST /auth/login` sem header `Authorization` retornam 200 (ou 4xx por credenciais inválidas), nunca 403 do authorizer.

- [ ] **Rota protegida sem token**  
  `GET /users/me` (ou outra rota protegida) **sem** `Authorization` retorna **403** (Forbidden) do API Gateway.

- [ ] **Rota protegida com token inválido**  
  `GET /users/me` com `Authorization: Bearer token-invalido` retorna **403**.

- [ ] **Rota protegida com token válido**  
  `GET /users/me` com `Authorization: Bearer <token do login>` retorna **200** (ou 404 se o backend assim decidir); o request chega ao backend.

- [ ] **Token expirado**  
  Token com `exp` no passado → **403**.

- [ ] **Audience errada**  
  Token com `aud` diferente do configurado no authorizer → **403**.

- [ ] **Scopes (se configurados)**  
  Rota com authorization scopes ex.: `games:read`; token **sem** `games:read` no claim `scope` → **403**; token **com** `games:read` → 200 (se o backend permitir).

- [ ] **Webhook público**  
  `POST /payments/webhooks/provider` sem JWT retorna 200 ou 400 conforme o body, nunca 403 por falta de JWT.

---

## 6. Problemas comuns e como diagnosticar

| Sintoma | Possível causa | O que verificar |
|--------|----------------|------------------|
| 403 em toda rota protegida mesmo com token válido | Issuer ou audience diferente do token | Comparar `iss` e `aud` do JWT (jwt.io) com Issuer e Audience do authorizer. URLs exatamente iguais (sem barra final, mesmo esquema). |
| 403 só às vezes / após troca de chave | Cache do JWKS (até 2 h) | Aguardar até 2 h ou garantir que a chave antiga siga no JWKS durante o período de graça (rotação, ver seção 8). |
| Authorizer "não encontra" o token | Identity source errado | Confirmar que o cliente envia `Authorization: Bearer <token>`. Identity source deve ser `$request.header.Authorization`. |
| 403 por scope | Token sem o scope da rota | Incluir o scope no token (Users API) ou remover/ajustar authorization scopes da rota no gateway. |
| Gateway não alcança o issuer | Rede / HTTPS | Em VPC, garantir que o API Gateway (ou o serviço que resolve o JWKS) consiga acessar a URL do issuer (NAT, security group, DNS). |
| Erro ao criar authorizer (issuer inválido) | URL inacessível ou formato errado | Issuer deve ser URL HTTPS (em prod) acessível pelo gateway; sem barra final. Testar `curl` do ambiente AWS para o discovery. |

**Diagnóstico rápido:** decodificar o token em [jwt.io](https://jwt.io) e conferir `iss`, `aud`, `exp`, `scope`; comparar com a configuração do authorizer e com os scopes da rota.

---

## 7. Rollout sem quebrar clientes

1. **Criar o authorizer** sem anexar a nenhuma rota; validar que o issuer e o audience estão corretos (teste manual com uma rota de teste protegida).
2. **Deixar rotas públicas** explicitamente sem authorizer (NONE).
3. **Proteger rotas por etapas:** primeiro um conjunto pequeno (ex.: só `/users/me`); validar com clientes reais; depois estender para `/games`, `/payments`, etc.
4. **Comunicar** que a partir de uma data será obrigatório enviar `Authorization: Bearer <token>` nas rotas protegidas; manter documentação e exemplos atualizados.
5. **Não remover** rotas públicas de login e discovery; clientes precisam delas para obter o token.
6. **Monitorar** 403 após o rollout (CloudWatch, access logs); se muitos 403, checar issuer/audience e formato do header.

---

## 8. Rotação de chaves e cache de 2 horas

- O API Gateway **cacheia as chaves públicas** obtidas do `jwks_uri` por **até 2 horas**. Após rotação, tokens assinados com a chave **nova** podem ser rejeitados até o cache expirar se o gateway ainda não tiver buscado o JWKS atualizado.
- **Prática recomendada:**
  1. **Incluir a chave nova no JWKS** antes de passar a emitir tokens com ela (ex.: adicionar novo `kid` no JSON de `/.well-known/jwks.json`).
  2. **Continuar incluindo a chave antiga** no JWKS por pelo menos **2 horas** após começar a usar a chave nova (período de graça).
  3. Só então **deixar de emitir** tokens com a chave antiga e, após mais 2 horas, remover a chave antiga do JWKS.
- Assim, o API Gateway que ainda tiver a chave antiga em cache continua validando tokens antigos, e ao buscar o JWKS de novo passará a ver também a chave nova e validar os tokens novos.

---

## 9. Resumo da configuração recomendada do authorizer

| Item | Valor |
|------|--------|
| **Authorizer type** | JWT |
| **Name** | `fcg-jwt-users` |
| **Identity source** | `$request.header.Authorization` |
| **Issuer** | URL base da Users API (ex.: `https://users-api.seudominio.com`), igual ao `iss` do token |
| **Audience** | `fcg-cloud-platform` (ou lista incluindo esse valor) |
| **Authorization scopes** | Por rota; opcional (ex.: `games:read`, `payments:write`). Vazio = só valida issuer/audience/assinatura. |

Rotas públicas (login, discovery, jwks, webhook, internal) **sem** authorizer; demais rotas com **authorizer** `fcg-jwt-users` e, quando desejado, scopes por rota.

---

## 10. Matriz de rotas (referência rápida)

| Público (sem JWT) | Protegido (JWT) |
|-------------------|-----------------|
| `POST /auth/login` | `GET/PUT/DELETE /users/me` |
| `GET /.well-known/openid-configuration` | `GET/POST/PUT/DELETE /users/*` (admin/CRUD) |
| `GET /.well-known/jwks.json` | `GET/POST/PUT/PATCH/DELETE /games/*` |
| `GET /api/discovery` | `GET/POST/PUT/DELETE /me/library/*` |
| `POST /payments/webhooks/provider` | `POST /payments`, `GET /payments/me`, `GET/POST /payments/{id}/*` |
| `POST /internal/library/add-from-payment` | Todas as demais rotas de negócio |
