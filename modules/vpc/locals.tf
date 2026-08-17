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
