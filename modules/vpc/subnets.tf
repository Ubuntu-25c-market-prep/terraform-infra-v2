resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr_block
  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = merge(var.tags, var.public_subnet_tags, {
    Name = "${var.name}-${each.value.name}"
  })

  lifecycle {
    # A subnet must be carved FROM the VPC range: its prefix cannot be
    # shorter than the VPC's. (Full containment is enforced by AWS at
    # apply; this catches the common /16-vs-/24 mixup at plan time.)
    precondition {
      condition     = tonumber(split("/", each.value.cidr_block)[1]) >= tonumber(split("/", var.cidr_block)[1])
      error_message = "Subnet '${each.value.name}' (${each.value.cidr_block}) has a larger range than the VPC itself (${var.cidr_block})."
    }
  }
}

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.availability_zone
  # never map_public_ip_on_launch - that is what makes it private

  tags = merge(var.tags, var.private_subnet_tags, {
    Name = "${var.name}-${each.value.name}"
  })

  lifecycle {
    precondition {
      condition     = tonumber(split("/", each.value.cidr_block)[1]) >= tonumber(split("/", var.cidr_block)[1])
      error_message = "Subnet '${each.value.name}' (${each.value.cidr_block}) has a larger range than the VPC itself (${var.cidr_block})."
    }

    # Names and CIDRs must not collide with the public subnets (validations
    # cannot see other variables on TF 1.5, so the check lives here).
    precondition {
      condition     = !contains([for s in var.public_subnets : s.cidr_block], each.value.cidr_block)
      error_message = "Private subnet '${each.value.name}' reuses CIDR ${each.value.cidr_block} of a public subnet."
    }

    precondition {
      condition     = !contains([for s in var.public_subnets : s.name], each.value.name)
      error_message = "Private subnet '${each.value.name}' reuses the name of a public subnet."
    }
  }
}
