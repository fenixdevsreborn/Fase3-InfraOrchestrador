# locals.tf — FCG Fenix: naming e tags centralizados
# Convenção: fcg-fenix-{aplicacao-ws}-{identificador}
# Não usar "prod" no nome dos recursos; Environment = production só nas tags.

locals {
  # --- Projeto e ambiente ---
  project_name = "fcg-fenix"
  environment  = "production"

  services = ["usersapi", "gamesapi", "paymentsapi"]

  # --- Naming ---
  name_prefix = local.project_name

  # Recursos compartilhados (aplicacao = "main")
  main_name = {
    "vpc"       = "${local.name_prefix}-main-vpc"
    "igw"       = "${local.name_prefix}-main-igw"
    "alb"       = "${local.name_prefix}-main-alb"
    "listener"  = "${local.name_prefix}-main-listener"
    "apigw"     = "${local.name_prefix}-main-apigw"
    "vpclink"   = "${local.name_prefix}-main-vpclink"
    "public-rt" = "${local.name_prefix}-public-rt"
    "private-rt" = "${local.name_prefix}-private-rt"
  }

  # Por serviço: fcg-fenix-{service}-{identifier}
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
    "alb-sg"             = "${local.name_prefix}-alb-sg"
    "githubactions-role" = "${local.name_prefix}-githubactions-role"
  }

  # Subnets: tipo + AZ
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

  tags_shared = merge(local.tags_base, {
    Application = "shared"
    Service     = "shared"
  })

  tags_for_service = {
    for svc in local.services : svc => merge(local.tags_base, {
      Application = svc
      Service     = svc
    })
  }

  tags_github_actions = merge(local.tags_base, {
    Application = "githubactions"
    Service     = "githubactions"
  })

  # Objetos consolidados para passar aos módulos (opcional)
  naming = {
    prefix   = local.name_prefix
    main     = local.main_name
    service  = local.service_names
    special  = local.special_names
    subnets  = local.subnet_names
  }

  tags = {
    base           = local.tags_base
    shared         = local.tags_shared
    for_service    = local.tags_for_service
    github_actions  = local.tags_github_actions
  }

  # ALB: path prefix -> serviço para listener rules (/users/* -> usersapi, etc.)
  alb_path_prefix_to_service = {
    "/users"    = "usersapi"
    "/games"    = "gamesapi"
    "/payments" = "paymentsapi"
  }
}
