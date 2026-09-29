resource "aws_cloudwatch_event_rule" "this" {
  for_each = local.rules

  name        = each.value.name
  description = each.value.description
  state       = each.value.enabled ? "ENABLED" : "DISABLED"

  event_pattern       = each.value.event_pattern
  schedule_expression = each.value.schedule_expression

  tags = merge(var.tags, {
    Name = each.value.name
  })
}

# The target's own resource policy must allow events.amazonaws.com.
resource "aws_cloudwatch_event_target" "this" {
  for_each = local.targets

  rule      = aws_cloudwatch_event_rule.this[each.value.rule].name
  target_id = each.value.id
  arn       = each.value.arn
}
