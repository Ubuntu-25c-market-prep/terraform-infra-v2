# NAT gateways live in PUBLIC subnets and carry the private subnets'
# egress. Each one costs ~$0.045/h (~$33/month) plus per-GiB processing -
# nat_gateway = "none" is the deliberate default.

resource "aws_eip" "nat" {
  for_each = local.nat_gateways

  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.name}-nat-${each.key}"
  })
}

resource "aws_nat_gateway" "this" {
  for_each = local.nat_gateways

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.value].id

  tags = merge(var.tags, {
    Name = "${var.name}-nat-${each.key}"
  })

  # The IGW must exist before a NAT in a public subnet is functional.
  depends_on = [aws_internet_gateway.this]

  lifecycle {
    precondition {
      condition     = each.value != null
      error_message = "nat_gateway = per_az: AZ '${each.key}' has private subnets but no public subnet to host its NAT gateway."
    }
  }
}
