locals {
  instances = { for instance in var.instances : instance.name => instance }
}
