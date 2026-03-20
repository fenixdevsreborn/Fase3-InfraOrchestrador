# Módulo API Gateway HTTP API — integração privada via VPC Link para ALB interno
# Naming: fcg-fenix-main-apigw, fcg-fenix-main-vpclink, fcg-fenix-main-nlb (ponte para o ALB)

variable "project_name" {
  type        = string
  description = "Prefixo do projeto (ex.: fcg-fenix)."
}

variable "environment" {
  type        = string
  description = "Ambiente (ex.: production). Usado em tags."
}

variable "vpc_id" {
  type        = string
  description = "ID da VPC onde o NLB (ponte para o ALB) e o VPC Link serão criados."
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "IDs das subnets privadas para o NLB e o VPC Link."
}

variable "alb_arn" {
  type        = string
  description = "ARN do ALB interno (alvo do NLB)."
}

variable "alb_listener_port" {
  type        = number
  description = "Porta do listener do ALB (deve coincidir com o listener existente)."
  default     = 80
}

variable "route_paths" {
  type        = map(string)
  description = "Mapa path_prefix -> service para as rotas (ex.: { \"/users\" = \"usersapi\", \"/games\" = \"gamesapi\", \"/payments\" = \"paymentsapi\" }). Serão criadas rotas ANY path_prefix/{proxy+} e ANY path_prefix."
}

variable "tags_base" {
  type        = map(string)
  description = "Tags base (Project, ManagedBy, Environment)."
}

variable "vpc_link_security_group_ids" {
  type        = list(string)
  description = "IDs dos security groups para o VPC Link (opcional; necessário em algumas configurações de rede)."
  default     = []
}

variable "api_description" {
  type        = string
  description = "Descrição da API HTTP."
  default     = "FCG Fenix HTTP API - private integration via VPC Link to ALB"
}

variable "api_gateway_access_log_retention_days" {
  type        = number
  description = "Retenção (dias) do log group de access logs no CloudWatch. Use 0 para nunca expirar (não recomendado em produção)."
  default     = 30
}

variable "api_gateway_detailed_metrics_enabled" {
  type        = bool
  description = "Habilita métricas de rota detalhadas no CloudWatch para o stage $default (equivalente ao toggle no console)."
  default     = true
}

variable "api_gateway_route_logging_level" {
  type        = string
  description = "Nível de log de execução na rota padrão: ERROR, INFO ou OFF (HTTP API v2)."
  default     = "INFO"

  validation {
    condition     = contains(["ERROR", "INFO", "OFF"], var.api_gateway_route_logging_level)
    error_message = "api_gateway_route_logging_level deve ser ERROR, INFO ou OFF."
  }
}

variable "api_gateway_data_trace_enabled" {
  type        = bool
  description = "Inclui corpo de request/response nos logs de execução (pode expor dados sensíveis e aumentar custo). Default false."
  default     = false
}

# --- JWT authorizer (Users API / OIDC) ---

variable "jwt_authorizer_enabled" {
  type        = bool
  description = <<-EOT
    Se true, exige JWT nas rotas de jwt_authorizer_route_prefixes.
    A AWS valida o issuer na criação: a URL {issuer}/.well-known/openid-configuration deve responder 200 com JSON OIDC válido.
    Mantenha false até a Users API estar no ar com Jwt__Issuer + PathBase alinhados ao issuer; depois true e novo apply.
  EOT
  default     = false
}

variable "users_api_jwt_issuer" {
  type        = string
  description = "Valor do claim iss / Jwt:Issuer na Users API. Se vazio, usa https://{api-id}.execute-api.{região}.amazonaws.com/users (exige ASPNETCORE_PATHBASE=/users e OIDC em /users/.well-known/*)."
  default     = ""
}

variable "users_api_jwt_audience" {
  type        = list(string)
  description = "Audiences aceitos (Jwt:Audience na Users API, ex.: fcg-cloud-platform)."
  default     = ["fcg-cloud-platform"]
}

variable "jwt_authorizer_route_prefixes" {
  type        = list(string)
  description = "Prefixos de path (chaves de route_paths) que exigem JWT no gateway. Não incluir /users (login e OIDC públicos)."
  default     = ["/games", "/payments"]
}
