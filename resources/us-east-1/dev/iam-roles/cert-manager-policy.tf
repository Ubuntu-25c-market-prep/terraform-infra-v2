# Standalone, not through modules/iam-roles: the policy needs a Condition
# block (scoping ChangeResourceRecordSets to TXT records named
# _acme-challenge.* in one zone), which the module's policies[].statements[]
# schema cannot express (effect/actions/resources only, no condition).
# Same reasoning and pattern as aws-load-balancer-controller-policy.tf, but
# this document is OUR OWN, hand-written to match the existing 25c-shared
# policy's intent exactly (infra-aws/modules/cert-manager/controller.tf's
# data.aws_iam_policy_document.controller) - not an upstream file, so keep
# it in sync by hand if that module ever changes, not by re-downloading.
#
# Zone id Z033052035FXAKF23D1RR is 25c-team1.art, the same zone 25c-shared
# uses (confirmed live via `aws route53 list-hosted-zones` - both clusters
# are in the same AWS account, 808540602855). Scoping ChangeResourceRecordSets
# to this one zone ARN - not hostedzone/* - is what stops this role from
# touching any other zone in the account if one is ever created; the TXT +
# _acme-challenge.* conditions on top of that stop it from touching anything
# in THIS zone except the ACME challenge record.
resource "aws_iam_policy" "cert_manager" {
  name        = "dev-CertManagerRoute53Policy-us-east-1"
  description = "cert-manager DNS-01 via Route53 - TXT _acme-challenge.* writes only, scoped to hostedzone/Z033052035FXAKF23D1RR (25c-team1.art)"
  policy      = file("${path.module}/cert-manager-route53-policy.json")

  tags = merge(local.tags, {
    Name = "dev-CertManagerRoute53Policy-us-east-1"
  })
}
