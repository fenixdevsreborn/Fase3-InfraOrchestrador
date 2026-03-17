variable "project_name" { type = string }
variable "environment" { type = string }
variable "github_oidc_org" { type = string }
variable "github_oidc_repos" { type = list(string) }
variable "tags_base" { type = any }
