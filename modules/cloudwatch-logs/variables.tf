variable "name_prefix" {
  type = string
}

variable "retention_days" {
  type    = number
  default = 14
}

variable "tags" {
  type    = map(string)
  default = {}
}
