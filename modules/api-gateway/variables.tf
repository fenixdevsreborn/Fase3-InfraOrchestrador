variable "name_prefix" {
  type        = string
  description = "Prefix for resource names"
}

variable "jwt_issuer_uri" {
  type        = string
  default     = ""
  description = "JWT issuer URI (Cognito or custom). Empty = no JWT authorizer"
}

variable "jwt_audience" {
  type        = list(string)
  default     = []
  description = "Expected JWT audience"
}

variable "access_log_group_arn" {
  type        = string
  default     = null
  description = "ARN of CloudWatch log group for access logs; null = create one in this module"
}

variable "tags" {
  type        = map(string)
  default     = {}
}
