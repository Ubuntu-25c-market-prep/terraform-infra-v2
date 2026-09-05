locals {
  public_subnets  = { for subnet in var.public_subnets : subnet.name => subnet }
  private_subnets = { for subnet in var.private_subnets : subnet.name => subnet }
  private_azs     = distinct([for subnet in var.private_subnets : subnet.availability_zone])

  # NAT gateway key => hosting public subnet (per_az: same AZ, null if none there)
  nat_gateways = (
    var.nat_gateway == "single" && length(var.private_subnets) > 0
    ? { single = var.public_subnets[0].name }
    : var.nat_gateway == "per_az"
    ? { for az in local.private_azs : az => one([for s in var.public_subnets : s.name if s.availability_zone == az]) }
    : {}
  )

  # Stated tables, or one per private subnet
  private_route_tables = (
    length(var.private_route_tables) > 0
    ? var.private_route_tables
    : { for subnet in var.private_subnets : "${var.name}-${subnet.name}" => [subnet.name] }
  )

  private_subnet_route_table = merge([
    for rt_name, subnet_names in local.private_route_tables :
    { for subnet_name in subnet_names : subnet_name => rt_name }
  ]...)

  # null when a table's subnets span AZs (per_az NAT rejects that)
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
