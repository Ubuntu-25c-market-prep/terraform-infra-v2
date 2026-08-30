# Standalone customer-managed policies - attached by ARN from roles in
# this stack (policy_arns) or elsewhere (eks/iam.yaml attached_policies).
resource "aws_iam_policy" "this" {
  for_each = { for p in var.policies : p.name => p }

  name        = var.name == null ? each.key : "${var.name}-${each.key}"
  description = each.value.description

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      for statement in each.value.statements : {
        Effect   = statement.effect
        Action   = statement.actions
        Resource = statement.resources
      }
    ]
  })

  tags = merge(var.tags, {
    Name = var.name == null ? each.key : "${var.name}-${each.key}"
  })
}
