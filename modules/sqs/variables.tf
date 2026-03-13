variable "name_prefix" {
  type = string
}

variable "notification_queue_name" {
  type = string
}

variable "message_retention_seconds" {
  type    = number
  default = 86400
}

variable "tags" {
  type    = map(string)
  default = {}
}
