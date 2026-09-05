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

resource "aws_route_table" "private" {
  for_each = local.private_route_tables

  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = each.key
  })

  lifecycle {
    precondition {
      condition     = alltrue([for s in each.value : contains(keys(local.private_subnets), s)])
      error_message = "Route table '${each.key}' lists a subnet that is not a private subnet of this VPC (${join(", ", each.value)})."
    }
    precondition {
      condition     = length(local.private_route_table_subnets) == length(distinct(local.private_route_table_subnets))
      error_message = "A private subnet is listed in more than one private route table - each subnet attaches to exactly one."
    }
  }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = try(aws_route_table.private[local.private_subnet_route_table[each.key]].id, null)

  lifecycle {
    precondition {
      condition     = contains(keys(local.private_subnet_route_table), each.key)
      error_message = "Private subnet '${each.key}' is listed in no private route table - every private subnet needs exactly one."
    }
  }
}
