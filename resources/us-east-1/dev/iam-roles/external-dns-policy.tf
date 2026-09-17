# Standalone, not through modules/iam-roles: this policy needs a Condition
# block (route53:ChangeResourceRecordSetsRecordTypes limited to A/AAAA/CNAME),
# which the module's policies[].statements[] schema cannot express
# (effect/actions/resources only, no condition). Same reasoning and pattern
# as aws-load-balancer-controller-policy.tf and cert-manager-policy.tf.
#
# Hand-written to match the intent of infra-aws/modules/external-dns/controller.tf's
# data.aws_iam_policy_document.controller (25c-shared's equivalent role) - not
# an upstream file, so keep it in sync by hand if that module ever changes.
#
# Zone id Z033052035FXAKF23D1RR is 25c-team1.art, the same zone cert-manager
# already solves DNS-01 challenges in (dev-CertManagerRoute53Policy-us-east-1)
# and the same zone 25c-shared's external-dns publishes into - verified live
# via `aws route53 list-hosted-zones`, same account (808540602855).
#
# Scoped to this one zone ARN, not hostedzone/*, and further restricted by
# Condition to the record types external-dns actually manages (A/AAAA/CNAME -
# matches infrastructures/base/external-dns/helmrelease.yaml's
# managedRecordTypes in gitops-flux) - not NS/SOA (keeps zone delegation
# intact) and not CAA (this role cannot authorise a different certificate
# authority for the domain cert-manager issues from). No GetChange statement:
# unlike cert-manager's ACME propagation check, external-dns never polls
# route53:GetChange.
resource "aws_iam_policy" "external_dns" {
  name        = "dev-ExternalDnsPolicy-us-east-1"
  description = "external-dns Route53 record management - A/AAAA/CNAME writes only, scoped to hostedzone/Z033052035FXAKF23D1RR (25c-team1.art)"
  policy      = file("${path.module}/external-dns-route53-policy.json")

  tags = merge(local.tags, {
    Name = "dev-ExternalDnsPolicy-us-east-1"
  })
}
