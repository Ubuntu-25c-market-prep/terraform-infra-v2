locals {
  global_values = yamldecode(file("${path.module}/../../../global-values.yaml"))
  region_values = yamldecode(file("${path.module}/../../regional-values.yaml"))
  env_values    = yamldecode(file("${path.module}/../prod-values.yaml"))

  config = merge(
    local.global_values,
    local.region_values,
    local.env_values,
    # config.yaml follows the vpc template: flat keys, one subnets
    # map, named route_tables (see the comments in config.yaml).
    yamldecode(file("${path.module}/config.yaml")),
    # tags exist in every layer; a plain merge keeps only the last map, so
    # combine them explicitly (later layers win on the same key)
    { tags = merge(local.global_values.tags, local.region_values.tags, local.env_values.tags) },
  )

  name_prefix = "${local.config.org}-${local.config.env}"

  # Org/Env/Component/Repo are added by the provider's default_tags
  tags = local.config.tags

  # CIDRs compose as <cidr_prefix>.<cidr_suffix> - VPC and subnets alike.
  vpc_cidr = "${local.config.cidr_prefix}.${local.config.cidr_suffix}"

  # Each subnet's route table NAME: the template format attaches tables to
  # subnets via attach_to_subnets, and EXACTLY ONE table must list each
  # subnet - one() fails the plan on zero or several matches.
  subnet_route_table_name = {
    for subnet_name, subnet in local.config.subnets :
    subnet_name => one([
      for rt_name, rt in local.config.route_tables : rt_name
      if contains(rt.attach_to_subnets, subnet_name)
    ])
  }

  subnet_route_table = {
    for subnet_name, rt_name in local.subnet_route_table_name :
    subnet_name => local.config.route_tables[rt_name]
  }

  # A subnet is PUBLIC when its route table has enable_igw: true.
  public_subnets = [
    for subnet_name, subnet in local.config.subnets : {
      name              = subnet_name
      cidr_block        = "${local.config.cidr_prefix}.${subnet.cidr_suffix}"
      availability_zone = subnet.availability_zone
    } if try(local.subnet_route_table[subnet_name].enable_igw, false)
  ]

  private_subnets = [
    for subnet_name, subnet in local.config.subnets : {
      name              = subnet_name
      cidr_block        = "${local.config.cidr_prefix}.${subnet.cidr_suffix}"
      availability_zone = subnet.availability_zone
    } if !try(local.subnet_route_table[subnet_name].enable_igw, false)
  ]

  # Route table Name tags are the config keys; one public table (one()
  # enforces), private tables list the subnets they route.
  public_route_table_name = one(distinct([
    for subnet in local.public_subnets : local.subnet_route_table_name[subnet.name]
  ]))
  private_route_tables = {
    for rt_name, rt in local.config.route_tables :
    rt_name => rt.attach_to_subnets if !try(rt.enable_igw, false)
  }

  # Any enable_endpoint_route: true wires the gateway endpoints to every table.
  gateway_endpoints_enabled = anytrue([
    for rt in values(local.config.route_tables) : try(rt.enable_endpoint_route, false)
  ])
}

module "vpc" {
  source = "../../../../modules/vpc"

  name       = local.config.name
  cidr_block = local.vpc_cidr

  # Strict lookups on purpose: every value must be stated in config.yaml,
  # so a missing or misspelled key fails the plan instead of silently
  # falling back to a module default.
  enable_dns_support                   = local.config.enable_dns_support
  enable_dns_hostnames                 = local.config.enable_dns_hostnames
  enable_network_address_usage_metrics = local.config.enable_network_address_usage_metrics
  map_public_ip_on_launch              = local.config.map_public_ip_on_launch
  instance_tenancy                     = local.config.instance_tenancy
  region                               = local.config.region
  enable_s3_gateway_endpoint           = local.gateway_endpoints_enabled && contains(local.config.gateway_endpoints, "s3")
  enable_dynamodb_gateway_endpoint     = local.gateway_endpoints_enabled && contains(local.config.gateway_endpoints, "dynamodb")

  public_subnets  = local.public_subnets
  private_subnets = local.private_subnets

  # The deployed tables are literally named like the config keys
  # (prod-route-us-east-1-public, ...), so config and AWS console match.
  public_route_table_name = local.public_route_table_name
  private_route_tables    = local.private_route_tables

  public_subnet_tags  = local.config.public_subnet_tags
  private_subnet_tags = local.config.private_subnet_tags

  tags = local.tags
}
