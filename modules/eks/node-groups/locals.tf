locals {
  node_groups = { for group in var.node_groups : group.name => group }
  addons      = { for addon in var.addons : addon.name => addon }
}
