# API Gateway HTTP API — Observações críticas sobre path forwarding

Observações sobre encaminhamento de path, stage e parameter mapping quando se usa integração privada (VPC Link) para um ALB interno.

---

## 1. Fluxo do request

```
Cliente → API Gateway (rota ANY /users/{proxy+})
        → VPC Link → NLB → ALB (listener :80)
        → listener rule /users/* → target group usersapi → EC2
```

O path que o ALB recebe deve ser **o mesmo** que a aplicação espera (ex.: `/users/123`), para que o ALB faça o roteamento por path e o backend não precise tratar prefixos extras.

---

## 2. Stage e path

### Stage `$default`

- **Nome do stage:** `$default`.
- **URL de invocação:** `https://{api-id}.execute-api.{region}.amazonaws.com` (sem segmento de path do stage).
- **Request:** `GET https://.../users/123` → o path enviado ao backend (NLB/ALB) é **`/users/123`**.
- Nenhum prefixo de stage é acrescentado ao path; não é necessário parameter mapping para “cortar” stage.

**Recomendação:** usar **sempre** o stage `$default` quando o backend (ALB + apps) já trabalha com paths como `/users/*`, `/games/*`, `/payments/*`, para evitar reescrita de path.

### Stage nomeado (ex.: `v1`)

- **URL de invocação:** `https://{api-id}.execute-api.{region}.amazonaws.com/v1`.
- **Request:** `GET https://.../v1/users/123` → o path que a API Gateway envia ao backend pode ser **`/v1/users/123`** (dependendo da configuração).
- Se o ALB e as apps esperam apenas `/users/123`, o path `/v1/users/123` quebra o roteamento ou exige que o backend trate o prefixo `/v1`.

**Solução (se precisar de stage nomeado):** usar **parameter mapping** na integração para reescrever o path e remover o prefixo do stage (ver seção 4).

---

## 3. Rotas na API Gateway vs. rotas no ALB

- **API Gateway:** rotas como `ANY /users/{proxy+}` e `ANY /users` apenas selecionam a **integração** (VPC Link → NLB → ALB). Elas **não** alteram o path ao encaminhar.
- **ALB:** listener rules por path (ex.: `/users/*`) decidem qual target group (e qual backend) recebe o request.
- O path que chega no ALB é o **mesmo** que o cliente enviou à API Gateway (ex.: `/users/123`), desde que não haja stage no path ou que se use parameter mapping para ajustar.

Garanta que:

- Os prefixos de path na API Gateway (`/users`, `/games`, `/payments`) coincidam com as **condições de path** do listener do ALB (`/users/*`, `/games/*`, `/payments/*`).
- As aplicações nas EC2 esperem exatamente esse path (sem prefixo de stage).

---

## 4. Parameter mapping (quando necessário)

Se você usar um **stage nomeado** e a URL for `.../v1/users/123`, o backend pode receber `/v1/users/123`. Para manter o ALB e as apps com path sem stage:

- Use **request parameter mapping** na integração (API Gateway HTTP API).
- Exemplo (conceitual): reescrever o path removendo o primeiro segmento (o stage), por exemplo:
  - Entrada: `/v1/users/123`
  - Saída desejada para o backend: `/users/123`

Na integração Terraform, isso pode ser feito com `request_parameters` (ou equivalente no provider) que definam o header ou o path que será enviado ao backend. O formato exato depende do provider e da versão; a ideia é mapear algo como `overwrite:path` para um valor derivado de `$request.path` (ex.: expressão que remove o primeiro segmento).

**Recomendação:** evitar stage nomeado na URL pública e usar **$default** com auto deploy, para não depender de parameter mapping para path.

---

## 5. Resumo

| Tema | Recomendação |
|------|----------------|
| **Stage** | Usar **$default**; URL sem segmento de stage; path chega ao ALB igual ao da request. |
| **Path no ALB** | Manter regras `/users/*`, `/games/*`, `/payments/*` alinhadas aos prefixos das rotas da API Gateway. |
| **Stage nomeado** | Só usar se for necessário; aí configurar parameter mapping para reescrever o path e remover o prefixo do stage antes de enviar ao ALB. |
| **Backend** | Apps devem tratar path **sem** prefixo de stage (ex.: `/users/123`), pois com `$default` é isso que o ALB recebe. |

---

*Documento: observações de path forwarding — API Gateway HTTP API + VPC Link + ALB. FCG Fenix.*
