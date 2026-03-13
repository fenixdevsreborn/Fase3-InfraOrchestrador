variable "name_prefix" {
  type = string
}

variable "bucket_name" {
  type        = string
  default     = ""
  description = "Custom bucket name; empty = auto-generate"
}

variable "enable_cors" {
  type    = bool
  default = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
