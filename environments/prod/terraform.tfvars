# ------------------------------------------------------------------------------
# Variáveis do ambiente prod (uso com -var-file=environments/prod/terraform.tfvars)
# Não inclua segredos; use TF_VAR_postgres_master_password ou secrets no CI.
# ------------------------------------------------------------------------------

environment  = "prod"
project_name = "fcg"
aws_region   = "us-east-1"
