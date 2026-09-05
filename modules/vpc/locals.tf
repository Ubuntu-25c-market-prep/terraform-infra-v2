locals {
  public_subnets  = { for subnet in var.public_subnets : subnet.name => subnet }
  private_subnets = { for subnet in var.private_subnets : subnet.name => subnet }

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

  private_route_table_subnets = flatten(values(local.private_route_tables))
}
