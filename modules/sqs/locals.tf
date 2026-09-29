locals {
  queues = { for queue in var.queues : queue.name => queue }
}
