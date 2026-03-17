# FCG Fenix — Documento de Requisitos do Produto (PRD)

Documento de requisitos do produto para a infraestrutura e o fluxo de CI/CD do projeto FCG Fenix. Linguagem orientada à execução e alinhada ao SPEC técnico.

---

## 1. Contexto

O **FCG Fenix** é um conjunto de APIs responsáveis por domínios distintos do produto:

- **usersapi** – gestão de usuários, autenticação e perfil.
- **gamesapi** – catálogo, metadata e operações relacionadas a jogos.
- **paymentsapi** – pagamentos, cobranças e integrações financeiras.

A solução será operada **100% em produção** sobre **AWS**, com:

- **Infraestrutura centralizada** em um repositório dedicado.
- **Repositórios de APIs desacoplados**, cada um com seu próprio ciclo de desenvolvimento.
- **Terraform** para provisionamento da infraestrutura.
- **GitHub Actions** para CI/CD.
- **Reusable workflows** no repositório de infraestrutura para padronizar deploys.
- **ECR** para imagens Docker de cada serviço.
- **EC2 privada por API**, com **PostgreSQL em Docker** rodando junto à API.
- Exposição via **API Gateway HTTP API → VPC Link → ALB interno → Target Groups → EC2**.
- **Deploy** realizado via **SSM Run Command**, chamado a partir dos workflows.

---

## 2. Problema

Sem este projeto:

- Não há um **padrão unificado** de infraestrutura para as APIs.
- Cada serviço tende a resolver infraestrutura “do seu jeito”, gerando duplicação, risco de configurações inseguras ou inconsistentes e dificuldade de operação.
- Deploys podem ser manuais ou pouco padronizados, aumentando risco de erro humano e tempo de entrega.
- Falta uma **visão clara e centralizada** de como as APIs chegam até produção, desde o código até a infraestrutura.

---

## 3. Objetivos do produto

- **Centralizar e padronizar** a infraestrutura de produção para `usersapi`, `gamesapi` e `paymentsapi`.
- **Desacoplar código de negócio da infraestrutura**, mantendo infra em um repo dedicado e cada API com seu repo e pipeline próprios.
- **Automatizar o caminho até produção** com provisionamento via Terraform e CI/CD via GitHub Actions + reusable workflows.
- **Garantir segurança e isolamento**: EC2 privadas por serviço, API Gateway + VPC Link + ALB interno, sem chaves estáticas (OIDC).
- **Reduzir tempo de onboarding** de novos desenvolvedores e serviços, com padrões claros e repetíveis.

---

## 4. Usuários-alvo

- **DevOps / SRE / Engenheiros de Infra:** querem um modelo previsível para provisionar e operar produção.
- **Desenvolvedores das APIs:** querem uma forma simples de “plugar” o código num pipeline de deploy confiável, sem precisar conhecer detalhes profundos de AWS.
- **Líderes técnicos / Arquitetos:** precisam de governança, segurança e rastreabilidade.
- **Stakeholders de produto / negócio:** querem agilidade e previsibilidade na entrega de novas features em produção, com menos incidentes.

---

## 5. Metas

- **Operacionais**
  - Provisionar toda a infraestrutura de produção via **Terraform**, com um único comando/pipeline.
  - Padronizar o deploy das 3 APIs via **reusable workflow** único no repositório de infra.
  - Permitir que **uma mudança de código em qualquer API** chegue em produção com build, teste, push de imagem para ECR e deploy automatizado via SSM.

- **De qualidade**
  - Reduzir o número de deploys manuais a **zero**.
  - Garantir que **100% dos recursos** provisionados tenham tags padronizadas (Project, ManagedBy, Environment, Application, Service).
  - Garantir que **nenhuma EC2 de produção** esteja diretamente exposta à internet.

- **De segurança**
  - Eliminar uso de chaves de acesso estáticas para CI/CD, adotando apenas **OIDC**.
  - Conter acesso à AWS exclusivamente via perfis e roles claramente definidos.

---

## 6. Não metas

- Não é objetivo:
  - Criar múltiplos ambientes (dev, stage, etc.) – foco exclusivo em **produção** neste projeto.
  - Implementar auto scaling, blue/green, canary ou estratégias avançadas de deploy.
  - Redesenhar ou reescrever o **código de negócio** das APIs.
  - Construir um sistema completo de observabilidade (dashboards, alertas complexos). Apenas o mínimo necessário será mencionado.

---

## 7. Solução proposta

- **Infraestrutura centralizada**
  - Repositório `fcg-fenix-infra-repo` com módulos Terraform (VPC, EC2, ALB, API Gateway, VPC Link, ECR, IAM, SSM), backend S3 + lock, workflows de Terraform (plan/apply) e reusable workflows para deploy via SSM Run Command.

- **APIs desacopladas**
  - Cada API em seu próprio repo, com código, Dockerfile e workflows de CI/CD que buildam, testam, enviam imagem para ECR e chamam o reusable workflow de infra para deploy.

- **Arquitetura de execução**
  - Entrada: API Gateway HTTP API.
  - Integração: VPC Link → ALB interno → Target Groups por API.
  - Back-end: 1 EC2 privada por serviço, com container da API e PostgreSQL, gerenciados por scripts e SSM Run Command.

- **Governança**
  - Padrão de nomes `fcg-fenix-{aplicacao-ws}-{identificador}` e padrão de tags obrigatórias; reusable workflows documentados e versionados no repo de infra.

---

## 8. Fluxos principais

### 8.1 Fluxo de provisionamento de infraestrutura

1. Engenheiro de infra altera código Terraform em `fcg-fenix-infra-repo`.
2. Abre PR → pipeline `terraform-plan` roda validação e plano de mudanças.
3. PR aprovado e mergeado.
4. Pipeline `terraform-apply` roda e aplica plano no ambiente de produção.
5. Infraestrutura (VPC, ALB, API Gateway, EC2, ECR, IAM, SSM etc.) é criada/atualizada.

### 8.2 Fluxo de desenvolvimento e deploy de uma API

1. Dev commita código em um repo de API (ex.: `fcg-fenix-usersapi-repo`).
2. Pipeline `ci` roda build, testes e validações.
3. Merge na branch principal dispara pipeline `cd`: build da imagem Docker, push para o ECR correspondente, chamada do reusable workflow de infra com `service`, `image_tag`, `environment=production`.
4. Reusable workflow assume role AWS via OIDC e executa SSM Run Command na EC2 correspondente; script na EC2 faz pull da nova imagem e reinicia o container da API.
5. API passa a responder com a nova versão pela mesma rota do API Gateway.

---

## 9. Requisitos funcionais

- **RF1** – Provisionar infraestrutura de produção via Terraform, incluindo VPC, subnets, route tables, IGW, NAT, security groups, EC2 privadas (uma por API), ALB interno, listener, target groups por API, API Gateway HTTP API + VPC Link, ECR por serviço, IAM roles e instance profiles, SSM Parameter Store com paths por serviço.

- **RF2** – Permitir que cada API faça build da imagem Docker, push para o ECR correspondente e disparo de deploy para a respectiva EC2 via reusable workflow.

- **RF3** – Disponibilizar endpoints públicos via API Gateway para `usersapi`, `gamesapi` e `paymentsapi` (ex.: `/users`, `/games`, `/payments`).

- **RF4** – Registrar configurações das APIs (strings de conexão, secrets, etc.) em SSM em paths específicos por serviço.

- **RF5** – Oferecer pelo menos um reusable workflow de deploy parametrizável por serviço, tag da imagem e ambiente.

---

## 10. Requisitos não funcionais

- **RNF1 – Segurança:** Uso obrigatório de **OIDC** para autenticação GitHub → AWS em workflows; EC2 de produção somente em subnets privadas; nenhuma chave de acesso estática de AWS nos repositórios.

- **RNF2 – Confiabilidade:** Deploys reexecutáveis (idempotentes) via SSM; scripts de deploy capazes de rodar múltiplas vezes sem corromper o ambiente.

- **RNF3 – Manutenibilidade:** Estrutura de módulos Terraform clara e documentada; padrão de nomes e tags aplicado de forma consistente em todos os recursos.

- **RNF4 – Escalabilidade futura:** Projeto preparado para evoluir para ASG, múltiplas instâncias por API e novos serviços em fases posteriores.

- **RNF5 – Observabilidade mínima:** Logs básicos de API Gateway, ALB e EC2 acessíveis; facilitação para inclusão de métricas e alarmes em próxima fase.

---

## 11. Métricas de sucesso

- **M1** – % de recursos de produção gerenciados por Terraform: meta **≥ 95%**.
- **M2** – % de deploys de APIs realizados via pipeline automatizado: meta **100%**.
- **M3** – Tempo médio de deploy (do merge ao serviço atualizado): meta **≤ 15 minutos**.
- **M4** – Número de incidentes relacionados a configuração incorreta de infraestrutura: meta de **redução perceptível** após adoção (ex.: queda de 50% em 3 meses).
- **M5** – Aderência a padrões de nome e tags: meta **100%** dos recursos novos em produção seguindo os padrões definidos.

---

## 12. Riscos

- **Risco 1 – Complexidade adicional para times que não conhecem AWS/Terraform**  
  *Mitigação:* Documentação clara, exemplos, treinamento rápido, abstração via reusable workflows.

- **Risco 2 – Single EC2 por API (ponto único de falha)**  
  *Mitigação:* Documentar limitação e plano de evolução para ASG; backups e scripts de re-provisioning rápido via Terraform.

- **Risco 3 – Configuração incorreta de OIDC**  
  *Mitigação:* Validar em ambiente controlado; revisar trust policy; aplicar princípio do menor privilégio.

- **Risco 4 – Dependência de SSM Run Command para deploy**  
  *Mitigação:* Scripts de fallback; documentar processo manual emergencial; monitorar status de SSM.

---

## 13. Roadmap por fases

- **Fase 1 – Fundamentos de Infra**  
  Criar repositório de infra; implementar VPC, subnets, route tables, IGW, NAT, security groups; configurar backend do Terraform (S3 + lock); criar módulos básicos.

- **Fase 2 – Compute + Rede de Aplicação**  
  Provisionar EC2 privadas (1 por API); criar ALB interno + Target Groups; criar API Gateway HTTP API + VPC Link; conectar rotas do API Gateway aos Target Groups.

- **Fase 3 – Imagens, Deploy e IAM**  
  Criar ECR por serviço; configurar IAM (roles para EC2, GitHub Actions via OIDC, SSM); implementar SSM Parameter Store para cada serviço; criar workflows Terraform (plan/apply).

- **Fase 4 – CI/CD das APIs**  
  Ajustar repositórios das APIs para usar Docker; criar pipelines de CI/CD em cada repo; criar e integrar reusable workflows de deploy no repo de infra; fazer primeiros deploys fim-a-fim.

- **Fase 5 – Endurecimento & Melhorias**  
  Ajustes de segurança fina (SGs, IAM); observabilidade mínima (logs e métricas básicas); documentação completa para onboarding.

---

## 14. Definição de pronto (DoD)

O projeto **FCG Fenix – Infra & Deploy** será considerado **pronto** quando:

1. **Infraestrutura** – VPC, subnets, NAT, IGW, security groups, ALB, API Gateway, VPC Link, EC2, ECR, IAM, SSM forem totalmente provisionados via Terraform em produção; todos os recursos relevantes em produção seguirem o padrão de nomes e tags definidos.

2. **CI/CD** – Repositório de infra com workflows de `plan` e `apply` funcionando; reusable workflow de deploy via SSM Run Command integrado com as 3 APIs (`usersapi`, `gamesapi`, `paymentsapi`); repositórios das APIs com pipelines de CI (build/teste) e CD (build+push+deploy) funcionando.

3. **Segurança** – Autenticação GitHub → AWS feita exclusivamente via OIDC nas pipelines; nenhuma EC2 de produção exposta diretamente à internet; credenciais sensíveis fora do código, armazenadas em SSM.

4. **Funcionalidade** – Todas as rotas principais de `usersapi`, `gamesapi` e `paymentsapi` acessíveis via API Gateway, roteando corretamente até as EC2 via ALB interno; pelo menos um ciclo completo (commit → merge → deploy) validado para cada API.

5. **Documentação** – SPEC.md e PRD.md atualizados no repositório de infra; guia mínimo de uso para desenvolvedores de API (como integrar seus repos aos reusable workflows); README do repositório de infra explicando como executar Terraform e como funcionam os pipelines.

---

*Documento: PRD.md — FCG Fenix. Alinhado a SPEC.md e 01-arquitetura-e-convencoes.md.*
