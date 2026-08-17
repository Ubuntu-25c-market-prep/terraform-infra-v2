locals {
  repositories = { for repo in var.repositories : repo.name => repo }
}
