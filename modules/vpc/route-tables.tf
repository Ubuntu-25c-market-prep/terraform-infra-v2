resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = coalesce(var.public_route_table_name, "${var.name}-public")
  })
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# One route table per private subnet: with per_az NAT each routes to its
# own AZ's NAT; with single NAT they all point at the same one; with
# nat_gateway = none they hold no default route (S3 gateway endpoint only).
resource "aws_route_table" "private" {
  for_each = local.private_subnets

  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = lookup(var.private_route_table_names, each.value.name, "${var.name}-${each.value.name}")
  })
}

resource "aws_route" "private_nat" {
  for_each = var.nat_gateway == "none" ? {} : local.private_subnets

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = (
    var.nat_gateway == "single"
    ? aws_nat_gateway.this["single"].id
    : aws_nat_gateway.this[each.value.availability_zone].id
  )
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}
