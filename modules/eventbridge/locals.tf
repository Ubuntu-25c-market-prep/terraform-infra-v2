locals {
  rules = { for rule in var.rules : rule.name => rule }

  targets = {
    for pair in flatten([
      for rule in var.rules : [
        for target in rule.targets : {
          rule = rule.name
          id   = target.id
          arn  = target.arn
        }
      ]
    ]) : "${pair.rule}/${pair.id}" => pair
  }
}
