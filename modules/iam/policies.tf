resource "aws_iam_role_policy_attachment" "this" {
  for_each = local.policy_attachments

  role       = aws_iam_role.this[each.value.role].name
  policy_arn = each.value.arn
}

resource "aws_iam_role_policy" "inline" {
  for_each = { for name, role in local.roles : name => role if length(role.policy) > 0 }

  name = "${var.name}-${each.key}"
  role = aws_iam_role.this[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      for statement in each.value.policy : {
        Effect   = statement.effect
        Action   = statement.actions
        Resource = statement.resources
      }
    ]
  })
}
