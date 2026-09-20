# Temporary: state moves for the per-file layout; delete once applied.
moved {
  from = aws_iam_policy.aws_load_balancer_controller
  to   = module.iam_roles.aws_iam_policy.this["dev-AWSLoadBalancerControllerPolicy-us-east-1"]
}

moved {
  from = aws_iam_policy.cert_manager
  to   = module.iam_roles.aws_iam_policy.this["dev-CertManagerRoute53Policy-us-east-1"]
}

moved {
  from = aws_iam_policy.external_dns
  to   = module.iam_roles.aws_iam_policy.this["dev-ExternalDnsPolicy-us-east-1"]
}
