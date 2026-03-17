# FCG Fenix — Naming e locals para Terraform

Proposta de **locals centrais** para padronizar nomes e tags de todos os recursos, seguindo a convenção `fcg-fenix-{aplicacao-ws}-{identificador}`.

---

## 1. Proposta do arquivo `locals.tf`

O arquivo `locals.tf` concentra:

- **Prefixo** do projeto.
- **Funções de nome** para recursos compartilhados (`main`) e por serviço.
- **Tags base** (Project, ManagedBy, Environment).
- **Tags por recurso** (com Application e Service).

Coloque `locals.tf` no **ambiente** (`environments/production/`) e, se os módulos precisarem de nomes/tags, **passe via variáveis** (recomendado) ou repita um bloco equivalente dentro de cada módulo usando variáveis recebidas.

### Conteúdo proposto

```hcl
# locals.tf — FCG Fenix: naming e tags centralizados
# Convenção: fcg-fenix-{aplicacao-ws}-{identificador}

locals {
  # --- Projeto e ambiente ---
  project_name = "fcg-fenix"
  environment  = "production"

  # Lista de serviços (evitar repetição em módulos)
  services = ["usersapi", "gamesapi", "paymentsapi"]

  # --- Naming ---
  name_prefix = local.project_name

  # Nome para recurso compartilhado (aplicacao = "main")
  # Uso: local.main_name("vpc") -> "fcg-fenix-main-vpc"
  main_name = {
    "vpc"      = "${local.name_prefix}-main-vpc"
    "igw"      = "${local.name_prefix}-main-igw"
    "alb"      = "${local.name_prefix}-main-alb"
    "listener" = "${local.name_prefix}-main-listener"
    "apigw"    = "${local.name_prefix}-main-apigw"
    "vpclink"  = "${local.name_prefix}-main-vpclink"
    "public-rt"  = "${local.name_prefix}-public-rt"
    "private-rt" = "${local.name_prefix}-private-rt"
  }

  # Nome por serviço: fcg-fenix-{service}-{identifier}
  # Uso nos módulos: passar service + identifier; no root pode usar o mapa abaixo.
  service_names = {
    for svc in local.services : svc => {
      "ecr"     = "${local.name_prefix}-${svc}-ecr"
      "ec2"     = "${local.name_prefix}-${svc}-ec2"
      "sg"      = "${local.name_prefix}-${svc}-sg"
      "tg"      = "${local.name_prefix}-${svc}-tg"
      "role"    = "${local.name_prefix}-${svc}-role"
      "profile" = "${local.name_prefix}-${svc}-profile"
    }
  }

  # Recursos com aplicação específica (não "main" nem serviço)
  special_names = {
    "alb-sg"            = "${local.name_prefix}-alb-sg"
    "githubactions-role" = "${local.name_prefix}-githubactions-role"
  }

  # Subnets: identificador inclui tipo e AZ
  subnet_names = {
    "public-a"  = "${local.name_prefix}-public-a-subnet"
    "public-b"  = "${local.name_prefix}-public-b-subnet"
    "private-a" = "${local.name_prefix}-private-a-subnet"
    "private-b" = "${local.name_prefix}-private-b-subnet"
  }

  # --- Tags obrigatórias ---
  tags_base = {
    Project     = local.project_name
    ManagedBy   = "terraform"
    Environment = local.environment
  }

  # Tags para recurso compartilhado (Application/Service = "shared")
  tags_shared = merge(local.tags_base, {
    Application = "shared"
    Service     = "shared"
  })

  # Tags por serviço — uso: local.tags_for_service("usersapi")
  tags_for_service = {
    for svc in local.services : svc => merge(local.tags_base, {
      Application = svc
      Service     = svc
    })
  }

  # Tags para recurso “especial” (ex.: GitHub Actions)
  tags_github_actions = merge(local.tags_base, {
    Application = "githubactions"
    Service     = "githubactions"
  })
}
```

### Função genérica reutilizável (opcional)

Se preferir **uma única função** em vez de mapas pré-definidos, use:

```hcl
# Retorna nome no padrão fcg-fenix-{aplicacao-ws}-{identificador}
locals {
  name = join("-", [local.name_prefix, var.application, var.identifier])
}
```

Nos módulos, isso vira: passar `application` (ex.: `"main"` ou `"usersapi"`) e `identifier` (ex.: `"vpc"`, `"ec2"`). No ambiente, os mapas acima são mais legíveis e evitam typo nos identificadores.

---

## 2. Mapa de naming reutilizável

Resumo dos nomes em um único mapa, para consulta e para passar a módulos via variável.

| Contexto   | Chave / Uso                         | Exemplo de nome                |
|-----------|--------------------------------------|---------------------------------|
| Shared    | `main_name["vpc"]`                   | `fcg-fenix-main-vpc`            |
| Shared    | `main_name["alb"]`                   | `fcg-fenix-main-alb`            |
| Shared    | `main_name["apigw"]`                 | `fcg-fenix-main-apigw`          |
| Serviço   | `service_names["usersapi"]["ec2"]`   | `fcg-fenix-usersapi-ec2`        |
| Serviço   | `service_names["gamesapi"]["ecr"]`  | `fcg-fenix-gamesapi-ecr`        |
| Especial  | `special_names["alb-sg"]`            | `fcg-fenix-alb-sg`              |
| Subnet    | `subnet_names["private-a"]`          | `fcg-fenix-private-a-subnet`    |

### Mapa completo para passar aos módulos

No `main.tf` do ambiente você pode expor um único objeto de naming para os módulos:

```hcl
locals {
  # ... (bloco anterior) ...

  # Mapa único para módulos que recebem "naming" como variável
  naming = {
    prefix   = local.name_prefix
    main     = local.main_name
    service  = local.service_names
    special  = local.special_names
    subnets  = local.subnet_names
  }

  tags = {
    base   = local.tags_base
    shared = local.tags_shared
    for_service = local.tags_for_service
    github_actions = local.tags_github_actions
  }
}
```

Assim, cada módulo recebe `naming` e `tags` (ou só as chaves que precisa) e monta o nome/tag internamente, sem repetir a lógica.

---

## 3. Exemplos de uso em recursos Terraform

### VPC (recurso compartilhado)

```hcl
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.tags_shared, {
    Name = local.main_name["vpc"]
  })
}
```

### Security Group do ALB (recurso especial)

```hcl
resource "aws_security_group" "alb" {
  name        = local.special_names["alb-sg"]
  description = "Security group for main ALB"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.tags_shared, {
    Name = local.special_names["alb-sg"]
  })
}
```

### Security Group por serviço (em módulo ou com for_each)

```hcl
resource "aws_security_group" "api" {
  for_each    = toset(local.services)
  name        = local.service_names[each.key]["sg"]
  description = "Security group for ${each.key} EC2"
  vpc_id      = var.vpc_id

  tags = merge(local.tags_for_service[each.key], {
    Name = local.service_names[each.key]["sg"]
  })
}
```

### EC2 por serviço (módulo chamado 3x)

No ambiente, passa o nome e as tags:

```hcl
module "ec2_usersapi" {
  source = "../../modules/ec2-api"

  instance_name = local.service_names["usersapi"]["ec2"]
  tags          = local.tags_for_service["usersapi"]
  # ...
}
```

Dentro do módulo:

```hcl
resource "aws_instance" "api" {
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = var.private_subnet_ids[0]

  iam_instance_profile = var.instance_profile_name

  tags = merge(var.tags, {
    Name = var.instance_name
  })
}
```

### Target Group (nome por serviço)

```hcl
resource "aws_lb_target_group" "api" {
  for_each    = toset(local.services)
  name        = local.service_names[each.key]["tg"]
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  tags = merge(local.tags_for_service[each.key], {
    Name = local.service_names[each.key]["tg"]
  })
}
```

### ALB e Listener (shared)

```hcl
resource "aws_lb" "main" {
  name               = local.main_name["alb"]
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.private_subnet_ids

  tags = merge(local.tags_shared, {
    Name = local.main_name["alb"]
  })
}

resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      status_code = "404"
    }
  }
}
```

### ECR por serviço

```hcl
resource "aws_ecr_repository" "api" {
  for_each = toset(local.services)
  name     = local.service_names[each.key]["ecr"]

  tags = merge(local.tags_for_service[each.key], {
    Name = local.service_names[each.key]["ecr"]
  })
}
```

### Tags obrigatórias sempre presentes

Em **qualquer** recurso:

- Recurso **compartilhado**: `tags = merge(local.tags_shared, { Name = "..." })`
- Recurso **por serviço**: `tags = merge(local.tags_for_service[service], { Name = "..." })`
- Recurso **GitHub Actions**: `tags = merge(local.tags_github_actions, { Name = "..." })`

Assim garantimos: **Project**, **ManagedBy**, **Environment**, **Application**, **Service** (e **Name** quando fizer sentido).

---

## 4. Boas práticas para evitar repetição

### 4.1 Um único `locals.tf` no ambiente

- Manter **um** arquivo `locals.tf` em `environments/production/` com prefixo, nomes e tags.
- Módulos **não** definem o prefixo nem a convenção; recebem **nomes e/ou tags** já montados (ou `naming` + `tags`).

### 4.2 Passar nome e tags para módulos

- Preferir passar `instance_name = local.service_names["usersapi"]["ec2"]` e `tags = local.tags_for_service["usersapi"]` para o módulo, em vez de passar `project_name`, `environment`, `service` e o módulo montar o nome. Assim a convenção fica **só no ambiente**.

### 4.3 Mapas pré-definidos em vez de string solta

- Usar `local.main_name["vpc"]` e `local.service_names[svc]["ec2"]` em vez de `"${local.name_prefix}-main-vpc"` espalhado. Reduz typo e facilita refatoração.

### 4.4 Sempre merge de tags

- Nunca sobrescrever `tags_base`; sempre `merge(local.tags_shared, { Name = ... })` ou `merge(local.tags_for_service[svc], { Name = ... })` para adicionar apenas **Name** (ou extras) e manter Project, ManagedBy, Environment, Application, Service.

### 4.5 Novos identificadores

- Ao adicionar um novo tipo de recurso (ex.: `"nlb"`), incluir em `main_name`, em `service_names` ou em `special_names` em **um único lugar** no `locals.tf`.

### 4.6 Novo serviço

- Incluir o novo serviço em `local.services`; os mapas `service_names` e `tags_for_service` passam a incluí-lo automaticamente (for_each / chamadas de módulo já parametrizadas por `local.services`).

### 4.7 Nomes longos ou com restrições

- Alguns recursos AWS têm limite de caracteres (ex.: 32 para target group). Manter identificadores curtos (`tg`, `sg`, `ec2`, `ecr`, `role`, `profile`) para caber no padrão sem truncar.

---

*Documento: naming e locals Terraform — FCG Fenix. Alinhado a CONVENTIONS.md e SPEC.md.*
