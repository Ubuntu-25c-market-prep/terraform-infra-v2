# Key pair created FROM committed public key material - a public key is
# safe to commit; only the private half must stay out of git.
resource "aws_key_pair" "this" {
  count = var.ssh_public_key != null ? 1 : 0

  key_name   = var.name
  public_key = var.ssh_public_key

  tags = var.tags
}
