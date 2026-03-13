variable "name" {
  type        = string
  description = "Prefix for resource names"
}

variable "cidr" {
  type        = string
  description = "CIDR block for VPC"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags to apply"
}
