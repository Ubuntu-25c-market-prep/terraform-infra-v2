locals {
  global_values = yamldecode(file("${path.module}/../../../global-values.yaml"))
  region_values = yamldecode(file("${path.module}/../../regional-values.yaml"))
  env_values    = yamldecode(file("${path.module}/../dev-values.yaml"))

  stack_config = yamldecode(file("${path.module}/config.yaml"))

  config = merge(
    local.global_values,
    local.region_values,
    local.env_values,
    # config.yaml follows the org eks template: flat cluster_*/infra keys
    # plus the eks: map - none of them collide with the layered values.
    local.stack_config,
    # tags exist in every layer; a plain merge keeps only the last map, so
    # combine them explicitly (later layers win on the same key)
    { tags = merge(local.global_values.tags, local.region_values.tags, local.env_values.tags, try(local.stack_config.tags, {})) },
  )

  name_prefix = "${local.config.org}-${local.config.env}"

  # Node groups and extra security groups: one SELF-CONTAINED file each
  # under ng/ resp. sg/, in the org format (no defaults layer). Both are
  # translated into the modules' shapes below, after the network remote
  # state they depend on.
  node_group_files     = [for f in fileset("${path.module}/ng", "*.yaml") : yamldecode(file("${path.module}/ng/${f}"))]
  security_group_files = [for f in fileset("${path.module}/sg", "*.yaml") : yamldecode(file("${path.module}/sg/${f}"))]

  # Kubernetes-style effects (as written in k8s_taints) -> EKS API values
  taint_effects = {
    NoSchedule       = "NO_SCHEDULE"
    PreferNoSchedule = "PREFER_NO_SCHEDULE"
    NoExecute        = "NO_EXECUTE"
  }

  # Cluster identity - iam.yaml (org format): access_entries keyed by
  # principal, service_accounts (IRSA) keyed by role name, iam_role_tags.
  iam_file = yamldecode(file("${path.module}/iam.yaml"))

  # An arn: key IS the principal (org-template style; never committed
  # here - public repo); any other key is an entry name whose principal
  # resolves at plan time from the entry's role_name / role_name_pattern.
  # policy_arn keeps the full cluster-access-policy ARN (no account id in
  # it) - the module wants the bare policy name.
  iam_access_entries = [
    for principal, entry in local.iam_file.access_entries : {
      name              = element(split("/", principal), length(split("/", principal)) - 1)
      type              = entry.access_entry_type
      principal_arn     = startswith(principal, "arn:") ? principal : null
      role_name         = try(entry.role_name, null)
      role_name_pattern = try(entry.role_name_pattern, null)
      policy            = try(replace(entry.policy_arn, "arn:aws:eks::aws:cluster-access-policy/", ""), null)
      kubernetes_groups = try(entry.kubernetes_groups, [])
      scope             = try(entry.scope, "cluster")
      namespaces        = try(entry.namespaces, [])
    }
  ]

  # Node-pool roles created OUTSIDE this stack (config.yaml:
  # eks.additional_node_pools_iam_roles) join as EC2_LINUX access
  # entries, alongside whatever iam.yaml lists.
  access_entries = concat(
    local.iam_access_entries,
    [
      for role in local.config.eks.additional_node_pools_iam_roles : {
        name      = role
        type      = "EC2_LINUX"
        role_name = role
      }
    ],
  )

  # service_accounts (org format) -> the iam module's irsa role shape;
  # namespace_service_account is "<namespace>/<service_account>".
  irsa_roles = [
    for role_name, sa in local.iam_file.service_accounts : {
      name            = role_name
      type            = "irsa"
      namespace       = split("/", sa.namespace_service_account)[0]
      service_account = split("/", sa.namespace_service_account)[1]
      description     = try(sa.description, null)
      policy_arns     = try(sa.attached_policies, [])
      policy          = try(sa.policy, [])
    }
  ]

  # Org/Env/Component/Repo are added by the provider's default_tags
  tags = local.config.tags
}

data "terraform_remote_state" "network" {
  backend = "local"

  config = {
    path = "${path.module}/../network/terraform.tfstate"
  }
}

locals {
  # ng/*.yaml (org node-group format) -> node-groups module shape.
  # Strict lookups on purpose (same rule as config.yaml): name, sizing and
  # the use_*/public_instance switches must be stated in every file; only
  # k8s_labels, k8s_taints, tags and subnet_ids may be omitted.
  node_groups = [
    for g in local.node_group_files : {
      name           = g.name
      instance_types = g.instance_type_list
      capacity_type  = g.use_on_demand_instance ? "ON_DEMAND" : "SPOT"
      ami_type       = g.use_al2023_ami ? "AL2023_x86_64_STANDARD" : "AL2_x86_64"
      min_size       = g.min_size
      desired_size   = g.desired_size
      max_size       = g.max_size
      disk_size      = g.disk_size
      labels         = try(g.k8s_labels, {})
      tags           = try(g.tags, {})

      # k8s_taints entries are "<key>: <value>:<Effect>" (k8s spelling,
      # e.g. "dedicated: elk:NoSchedule") - split and map the effect.
      taints = [
        for key, value in try(g.k8s_taints, {}) : {
          key    = key
          value  = split(":", value)[0]
          effect = local.taint_effects[split(":", value)[1]]
        }
      ]

      # Explicit subnet_ids in the file win (they never do in this public
      # repo); otherwise public_instance picks this environment's public
      # or private subnets from the network stack.
      subnet_ids = try(g.subnet_ids, null) != null ? g.subnet_ids : (
        g.public_instance
        ? values(data.terraform_remote_state.network.outputs.public_subnet_ids)
        : values(data.terraform_remote_state.network.outputs.private_subnet_ids)
      )
    }
  ]

  # sg/*.yaml (org security-group format: rules are maps keyed by rule
  # name; omitted ports/ip_protocol = all traffic) -> security-groups
  # module shape. cidrs_ipv6 is NOT wired - the module carries no IPv6
  # rules yet.
  security_groups = [
    for g in local.security_group_files : {
      name              = g.name
      description       = g.description
      attach_to_cluster = try(g.attach_to_cluster, false)

      ingress = [
        for rule_name, rule in try(g.ingress_rules, {}) : {
          description     = try(rule.description, rule_name)
          from_port       = try(rule.from_port, 0)
          to_port         = try(rule.to_port, 0)
          protocol        = try(rule.ip_protocol, "-1")
          cidr_blocks     = try(rule.cidrs, [])
          security_groups = try(rule.referenced_security_group_ids, [])
        }
      ]

      egress = [
        for rule_name, rule in try(g.egress_rules, {}) : {
          description     = try(rule.description, rule_name)
          from_port       = try(rule.from_port, 0)
          to_port         = try(rule.to_port, 0)
          protocol        = try(rule.ip_protocol, "-1")
          cidr_blocks     = try(rule.cidrs, [])
          security_groups = try(rule.referenced_security_group_ids, [])
        }
      ]
    }
  ]

  # eks.cluster_ingress_rules (config.yaml) -> one extra security group
  # attached to the control plane ENIs; {} creates no group.
  cluster_ingress_sg = length(local.config.eks.cluster_ingress_rules) == 0 ? [] : [{
    name              = "cluster-ingress"
    description       = "Extra ingress to the cluster control plane (config.yaml eks.cluster_ingress_rules)"
    attach_to_cluster = true
    egress            = []
    ingress = [
      for rule_name, rule in local.config.eks.cluster_ingress_rules : {
        description     = try(rule.description, rule_name)
        from_port       = try(rule.from_port, 0)
        to_port         = try(rule.to_port, 0)
        protocol        = try(rule.ip_protocol, "-1")
        cidr_blocks     = try(rule.cidrs, [])
        security_groups = try(rule.referenced_security_group_ids, [])
      }
    ]
  }]

  # Rule files are shared config, but CIDRs differ per environment. The
  # token "@vpc" in any cidrs entry resolves to THIS environment's
  # VPC CIDR (from the network stack) at plan time.
  security_groups_resolved = [
    for g in concat(local.security_groups, local.cluster_ingress_sg) : merge(g, {
      ingress = [for r in try(g.ingress, []) : merge(r, {
        cidr_blocks = [for c in try(r.cidr_blocks, []) : c == "@vpc" ? data.terraform_remote_state.network.outputs.vpc_cidr_block : c]
      })]
      egress = [for r in try(g.egress, []) : merge(r, {
        cidr_blocks = [for c in try(r.cidr_blocks, []) : c == "@vpc" ? data.terraform_remote_state.network.outputs.vpc_cidr_block : c]
      })]
    })
  ]

  # Same "@vpc" token for the rules on the EKS-managed shared node SG
  # (config.yaml: eks.shared_node_ingress_rules; org rule format with
  # cidrs -> the module's cidr_blocks).
  node_ingress_rules_resolved = {
    for name, rule in local.config.eks.shared_node_ingress_rules :
    name => {
      description                   = try(rule.description, "Managed by Terraform")
      cidr_blocks                   = [for c in try(rule.cidrs, []) : c == "@vpc" ? data.terraform_remote_state.network.outputs.vpc_cidr_block : c]
      referenced_security_group_ids = try(rule.referenced_security_group_ids, [])
      from_port                     = try(rule.from_port, null)
      to_port                       = try(rule.to_port, null)
      ip_protocol                   = tostring(rule.ip_protocol)
    }
  }
}

module "security_groups" {
  source = "../../../../modules/eks/security-groups"

  name = local.name_prefix
  # An explicit vpc_id in config.yaml wins (it never does in this public
  # repo); otherwise the network stack's VPC.
  vpc_id = try(local.config.vpc_id, null) != null ? local.config.vpc_id : data.terraform_remote_state.network.outputs.vpc_id

  security_groups = local.security_groups_resolved

  tags = local.tags
}

module "cluster" {
  source = "../../../../modules/eks/cluster"

  name = local.config.cluster_name
  # Explicit cluster_subnet_ids in config.yaml win (they never do in this
  # public repo); otherwise the network stack's public subnets.
  subnet_ids = try(local.config.cluster_subnet_ids, null) != null ? local.config.cluster_subnet_ids : values(data.terraform_remote_state.network.outputs.public_subnet_ids)

  security_group_ids = module.security_groups.cluster_security_group_ids

  # Strict lookups on purpose: every value must be stated in config.yaml,
  # so a missing or misspelled key fails the plan instead of silently
  # falling back to a module default (org template shape: flat cluster/
  # infra keys + the eks: map).
  cluster_version           = local.config.cluster_version
  endpoint_public_access    = local.config.eks.endpoint_public_access
  endpoint_private_access   = local.config.eks.endpoint_private_access
  enabled_cluster_log_types = local.config.eks.enabled_log_types
  public_access_cidrs       = local.config.eks.public_access_cidrs
  service_ipv4_cidr         = local.config.eks.service_ipv4_cidr
  create_oidc               = local.config.eks.create_oidc
  # kms_key_id holds an ALIAS by org rule (this repo is public)
  secrets_kms_key_alias = local.config.kms_key_id
  node_ingress_rules    = local.node_ingress_rules_resolved

  authentication_mode                         = local.config.eks.authentication_mode
  bootstrap_cluster_creator_admin_permissions = local.config.eks.bootstrap_cluster_creator_admin_permissions
  access_entries                              = local.access_entries

  tags = local.tags
}

# NO platform-tool discovery tags on purpose (karpenter.sh/discovery,
# kubernetes.io/role/*elb, ...): another EKS cluster with Karpenter runs
# in this account, and auto-discovery tags would let its controllers (or
# ours, prematurely) land resources in this infra before it is ready.
# Re-add them as their own change when this cluster goes live.

module "irsa" {
  source = "../../../../modules/iam"

  name  = local.name_prefix
  roles = local.irsa_roles

  # Straight from the cluster - no remote-state hop, and Terraform orders
  # cluster -> IRSA roles automatically.
  oidc_provider_arn = module.cluster.oidc_provider_arn
  oidc_issuer_url   = module.cluster.oidc_issuer_url

  tags = merge(local.tags, try(local.iam_file.iam_role_tags, {}))
}

module "node_groups" {
  source = "../../../../modules/eks/node-groups"

  name         = local.name_prefix
  cluster_name = module.cluster.cluster_name
  # Fallback only - every group carries its own subnet_ids, resolved from
  # public_instance in its ng/*.yaml file (currently all private; NOTE:
  # with nat_gateway = none the private subnets have no egress - the open
  # node-egress decision).
  subnet_ids = values(data.terraform_remote_state.network.outputs.private_subnet_ids)

  node_groups = local.node_groups

  tags = local.tags
}