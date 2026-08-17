resource "aws_ecr_lifecycle_policy" "this" {
  for_each = {
    for name, repo in local.repositories : name => repo
    if repo.untagged_expiry_days != null || repo.max_image_count != null
  }

  repository = aws_ecr_repository.this[each.key].name

  policy = jsonencode({
    rules = concat(
      each.value.untagged_expiry_days == null ? [] : [{
        rulePriority = 1
        description  = "Expire untagged images after ${each.value.untagged_expiry_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = each.value.untagged_expiry_days
        }
        action = {
          type = "expire"
        }
      }],
      each.value.max_image_count == null ? [] : [{
        rulePriority = 2
        description  = "Keep at most ${each.value.max_image_count} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = each.value.max_image_count
        }
        action = {
          type = "expire"
        }
      }]
    )
  })
}
