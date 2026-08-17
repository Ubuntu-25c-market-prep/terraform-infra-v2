# Key pair created FROM committed public key material - a public key is
# safe in a public repo (only the private half must stay out of git).
resource "aws_key_pair" "this" {
  count = var.ssh_public_key != null ? 1 : 0

  key_name   = "${var.name}-bastion"
  public_key = var.ssh_public_key

  tags = var.tags

  lifecycle {
    precondition {
      condition     = var.key_name == null
      error_message = "Set ssh_public_key (module creates the key pair) OR key_name (existing pair), not both."
    }
  }
}
