variable "queues" {
  description = "Standard queues to create; name is the full queue name"
  type = list(object({
    name                       = string
    message_retention_seconds  = optional(number, 345600)
    visibility_timeout_seconds = optional(number, 30)
    receive_wait_time_seconds  = optional(number, 0)
    kms_key_id                 = optional(string)           # null = SQS-managed encryption
    send_services              = optional(list(string), []) # AWS service principals allowed to send
  }))
  default  = []
  nullable = false
}

variable "tags" {
  description = "Tags applied to all resources in the module"
  type        = map(string)
  default     = {}
}
