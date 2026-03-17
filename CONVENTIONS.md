# Convenções FCG Fenix — Referência rápida

## Nomenclatura

- **Padrão:** `fcg-fenix-{aplicacao-ws}-{identificador}`
- **Escrita:** minúsculo, sem acento, sem espaço, hífen
- **Compartilhado:** usar `main` (ex: `fcg-fenix-main-vpc`, `fcg-fenix-main-alb`)
- **Sem "prod"** nos nomes dos recursos

## Tags obrigatórias

| Tag         | Valor                          |
|------------|---------------------------------|
| Project    | fcg-fenix                       |
| ManagedBy  | terraform                       |
| Environment| production                      |
| Application| usersapi / gamesapi / paymentsapi |
| Service    | usersapi / gamesapi / paymentsapi |

## Serviços

- usersapi
- gamesapi
- paymentsapi

Detalhes em [docs/01-arquitetura-e-convencoes.md](docs/01-arquitetura-e-convencoes.md).
