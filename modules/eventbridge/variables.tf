variable "rules" {
  description = "Rules on the default event bus; name is the full rule name (at most 64 characters)"
  type = list(object({
    name                = string
    description         = optional(string)
    enabled             = optional(bool, true)
    event_pattern       = optional(string) # JSON; one of event_pattern / schedule_expression
    schedule_expression = optional(string) # rate(...) or cron(...)
    targets = optional(list(object({
      id  = string
      arn = string
    })), [])
  }))
  default  = []
  nullable = false
}

variable "tags" {
  description = "Tags applied to all resources in the module"
  type        = map(string)
  default     = {}
}
