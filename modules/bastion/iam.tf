# Session Manager: shell and SSH-over-SSM without an open port 22.
data "aws_iam_policy_document" "assume" {
  count = var.enable_ssm ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  count = var.enable_ssm ? 1 : 0

  name               = "${var.name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume[0].json

  tags = merge(var.tags, {
    Name = "${var.name}-role"
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  count = var.enable_ssm ? 1 : 0

  role       = aws_iam_role.this[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  count = var.enable_ssm ? 1 : 0

  name = "${var.name}-role"
  role = aws_iam_role.this[0].name

  tags = var.tags
}
