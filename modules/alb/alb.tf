resource "aws_lb" "this" {
  name               = var.name
  load_balancer_type = "application"
  internal           = var.internal
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.subnet_ids

  ip_address_type            = var.ip_address_type
  idle_timeout               = var.idle_timeout
  enable_deletion_protection = var.deletion_protection
  drop_invalid_header_fields = var.drop_invalid_header_fields

  tags = merge(var.tags, {
    Name = var.name
  })

  # Id format checks run at plan so REPLACE-ME placeholders fail there, not at apply.
  lifecycle {
    precondition {
      condition     = alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]{8}([0-9a-f]{9})?$", id))])
      error_message = "subnet_ids must be subnet ids (subnet-<hex>) - replace the placeholders with the network stack outputs."
    }
  }
}
