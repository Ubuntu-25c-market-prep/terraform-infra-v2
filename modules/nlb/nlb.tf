resource "aws_lb" "this" {
  name               = var.name
  load_balancer_type = "network"
  internal           = var.internal
  # Security groups on an NLB can only be set at creation time - AWS
  # refuses to add one to an existing NLB. Changing the set later replaces
  # the load balancer (and its DNS name).
  security_groups = [aws_security_group.nlb.id]
  subnets         = var.subnet_ids

  ip_address_type                  = var.ip_address_type
  enable_cross_zone_load_balancing = var.cross_zone_load_balancing
  enable_deletion_protection       = var.deletion_protection

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
