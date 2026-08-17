resource "aws_ecr_repository" "this" {
  for_each = local.repositories

  name                 = "${var.name}-${each.value.name}"
  image_tag_mutability = each.value.image_tag_mutability
  force_delete         = each.value.force_delete

  image_scanning_configuration {
    scan_on_push = each.value.scan_on_push
  }

  tags = merge(var.tags, {
    Name = "${var.name}-${each.value.name}"
  })
}
