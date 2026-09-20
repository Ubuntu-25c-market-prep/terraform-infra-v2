# Extra ingress on the EKS-managed cluster security group - the SG EKS
# creates with the cluster and attaches to every managed node (and to the
# control plane ENIs). Rules here open the NODES to extra sources; extra
# groups for the control plane come from the security-groups module.
#
# aws_vpc_security_group_ingress_rule takes exactly ONE source, so each
# config rule fans out: one AWS rule per CIDR plus one per referenced SG.
locals {
  node_ingress_cidr_rules = merge([
    for rule_name, rule in var.node_ingress_rules : {
      for cidr in rule.cidr_blocks :
      "${rule_name}/${cidr}" => merge(rule, { rule = rule_name, source = cidr })
    }
  ]...)

  node_ingress_sg_rules = merge([
    for rule_name, rule in var.node_ingress_rules : {
      for sg in rule.referenced_security_group_ids :
      "${rule_name}/${sg}" => merge(rule, { rule = rule_name, source = sg })
    }
  ]...)
}

resource "aws_vpc_security_group_ingress_rule" "node_cidr" {
  for_each = local.node_ingress_cidr_rules

  security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id

  description = each.value.description
  cidr_ipv4   = each.value.source
  ip_protocol = each.value.ip_protocol
  from_port   = each.value.from_port
  to_port     = each.value.to_port

  tags = merge(var.tags, {
    Name = "${var.name}-${each.value.rule}"
  })
}

resource "aws_vpc_security_group_ingress_rule" "node_sg" {
  for_each = local.node_ingress_sg_rules

  security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id

  description                  = each.value.description
  referenced_security_group_id = each.value.source
  ip_protocol                  = each.value.ip_protocol
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port

  tags = merge(var.tags, {
    Name = "${var.name}-${each.value.rule}"
  })
}
