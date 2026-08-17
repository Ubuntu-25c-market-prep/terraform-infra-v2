# Latest Amazon Linux 2023 resolved at plan time - AMI ids are region- and
# time-specific and never belong in config (public repo, multi-env).
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "this" {
  for_each = local.instances

  ami           = each.value.ami_id != null ? each.value.ami_id : nonsensitive(data.aws_ssm_parameter.al2023.value)
  instance_type = each.value.instance_type
  subnet_id     = each.value.subnet_id

  vpc_security_group_ids = concat(
    each.value.security_group_ids,
    var.create_security_group ? [aws_security_group.this[0].id] : [],
  )
  user_data = each.value.user_data

  # SSH access: either a module-created key pair (ssh_public_key) or an
  # existing one (key_name).
  key_name = var.ssh_public_key != null ? aws_key_pair.this[0].key_name : var.key_name

  metadata_options {
    http_tokens   = "required" # IMDSv2 only
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_size = each.value.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(var.tags, {
    Name = "${var.name}-${each.value.name}"
  })
}
