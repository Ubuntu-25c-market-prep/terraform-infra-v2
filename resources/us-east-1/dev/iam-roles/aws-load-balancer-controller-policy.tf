# Standalone, not through modules/iam-roles: this policy is AWS's own
# published document (not something anyone here writes or reviews field by
# field), copied verbatim from
# https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v3.5.0/docs/install/iam_policy.json
# into aws-load-balancer-controller-iam-policy.json in this directory.
# Upgrading the controller version means replacing that file with the new
# release's iam_policy.json, nothing here changes.
#
# This is the FULL controller policy (creates/owns load balancers tagged
# elbv2.k8s.aws/cluster) - separate from, and not replacing,
# dev-AWSLoadBalancerControllerBindingPolicy-us-east-1 in config.yaml, which
# belongs to the alb/nlb stacks' Terraform-owns-the-LB design.
resource "aws_iam_policy" "aws_load_balancer_controller" {
  name        = "dev-AWSLoadBalancerControllerPolicy-us-east-1"
  description = "AWS Load Balancer Controller v3.5.0 upstream policy (full mode) - see this file's header for the source"
  policy      = file("${path.module}/aws-load-balancer-controller-iam-policy.json")

  tags = merge(local.tags, {
    Name = "dev-AWSLoadBalancerControllerPolicy-us-east-1"
  })
}
