# Rules built with filtered for-expressions: `cond ? [] : [{...}]` pairs make
# Terraform unify the branch types and countNumber renders as a string,
# which ECR rejects.
resource "aws_ecr_lifecycle_policy" "this" {
  for_each = {
    for name, repo in local.repositories : name => repo
    if repo.untagged_expiry_days != null || repo.max_image_count != null
  }

  repository = aws_ecr_repository.this[each.key].name

  policy = jsonencode({
    rules = concat(
      [for days in [each.value.untagged_expiry_days] : {
        rulePriority = 1
        description  = "Expire untagged images after ${days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = days
        }
        action = { type = "expire" }
      } if days != null],
      [for count in [each.value.max_image_count] : {
        rulePriority = 2
        description  = "Keep at most ${count} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = count
        }
        action = { type = "expire" }
      } if count != null],
    )
  })
}
