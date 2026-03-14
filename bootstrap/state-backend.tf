# ------------------------------------------------------------------------------
# Bootstrap usa backend local: state fica em bootstrap/terraform.tfstate
# Execute este módulo uma vez por conta/região; depois use os outputs em
# environments/<env>/backend.hcl
# ------------------------------------------------------------------------------

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
