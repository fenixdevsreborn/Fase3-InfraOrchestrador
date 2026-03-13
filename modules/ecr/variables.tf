variable "name_prefix" {
  type = string
}

variable "repository_names" {
  type        = list(string)
  description = "List of repository names (without prefix)"
}

variable "tags" {
  type    = map(string)
  default = {}
}
