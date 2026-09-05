# Latest Amazon Linux 2023 resolved at plan time - AMI ids are region- and
# time-specific and never belong in config (multi-env).
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

  iam_instance_profile = var.enable_ssm ? aws_iam_instance_profile.this[0].name : null

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
    Name = each.value.name # full name from config, e.g. dev-bastion-us-east-1
  })

  # Id format checks run at plan so REPLACE-ME placeholders fail there, not at apply.
  lifecycle {
    precondition {
      condition     = can(regex("^subnet-[0-9a-f]{8}([0-9a-f]{9})?$", each.value.subnet_id)) && can(regex("^vpc-[0-9a-f]{8}([0-9a-f]{9})?$", var.vpc_id))
      error_message = "Instance ${each.key}: subnet_id (subnet-<hex>) and vpc_id (vpc-<hex>) must be real ids - replace the placeholders with the network stack outputs."
    }
  }
}
