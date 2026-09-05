locals {
  public_subnets  = { for subnet in var.public_subnets : subnet.name => subnet }
  private_subnets = { for subnet in var.private_subnets : subnet.name => subnet }

  # AZs that host at least one private subnet - NAT placement for per_az.
  private_azs = distinct([for subnet in var.private_subnets : subnet.availability_zone])

  # NAT gateways to create: map key => name of the PUBLIC subnet hosting it.
  # single: one NAT in the first public subnet. per_az: one per private-subnet
  # AZ, in a public subnet of the SAME AZ (null if that AZ has no public
  # subnet - caught by a precondition with a readable error).
  nat_gateways = (
    var.nat_gateway == "single" && length(var.private_subnets) > 0
    ? { single = var.public_subnets[0].name }
    : var.nat_gateway == "per_az"
    ? { for az in local.private_azs : az => one([for s in var.public_subnets : s.name if s.availability_zone == az]) }
    : {}
  )
}

locals {
  # Stated tables, or one per private subnet.
  private_route_tables = (
    length(var.private_route_tables) > 0
    ? var.private_route_tables
    : { for subnet in var.private_subnets : "${var.name}-${subnet.name}" => [subnet.name] }
  )

  private_subnet_route_table = merge([
    for rt_name, subnet_names in local.private_route_tables :
    { for subnet_name in subnet_names : subnet_name => rt_name }
  ]...)

  # AZ of a table's subnets (per_az NAT); null when they span AZs.
  private_route_table_az = {
    for rt_name, subnet_names in local.private_route_tables :
    rt_name => (
      length(distinct([for s in subnet_names : try(local.private_subnets[s].availability_zone, null)])) == 1
      ? distinct([for s in subnet_names : try(local.private_subnets[s].availability_zone, null)])[0]
      : null
    )
  }

  private_route_table_subnets = flatten(values(local.private_route_tables))
}
