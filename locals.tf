# ------------------------------------------------------------------------------
# Locals — agregação de variáveis para imagens e uso em outputs
# As tags por serviço vêm de variáveis separadas (facilita -var e rollback).
# ------------------------------------------------------------------------------

locals {
  # Mapa serviço -> tag da imagem em uso. Usado em outputs (rollback) e opcionalmente em módulos.
  # Chaves devem coincidir com ecr_repository_names (users-api, games-api, payments-api, notification-lambda).
  service_image_tags = {
    "users-api"           = var.ecr_image_tag_users_api
    "games-api"           = var.ecr_image_tag_games_api
    "payments-api"        = var.ecr_image_tag_payments_api
    "notification-lambda" = var.ecr_image_tag_notification_lambda
  }
}
