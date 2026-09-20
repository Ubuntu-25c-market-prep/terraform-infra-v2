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
}
