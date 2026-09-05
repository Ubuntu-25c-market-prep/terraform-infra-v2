# iam-roles - non-cluster IAM

Standalone **policies** and **roles** declared in `config.yaml`. Cluster
identity (access entries, IRSA roles) lives in `eks/iam.yaml`; CI
identity (the GitHub Actions plan/apply roles) is not managed in this
repo at all.

## Policies

`policies[]` creates customer-managed policies named exactly as their
`name` (`<env>-<Name>-<region>`, e.g. `dev-AWSLoadBalancerControllerBindingPolicy-us-east-1`). They exist so any role can attach them **by ARN**:
roles in this file (`policy_arns`) or IRSA roles in `eks/iam.yaml`
(`attached_policies`). Flow: add the entry → apply this stack → read the
ARN from the `policy_arns` output → paste it where it is used. The
commented entries are the policies the `eks/iam.yaml` examples expect.

| Key | Meaning |
|---|---|
| `name` | unique; the full policy name, `<env>-<Name>-<region>` |
| `description` | optional |
| `statements[]` | `effect` (default `Allow`), `actions`, `resources` |

## Roles

`roles[]` entries merge over `role_defaults`. Two types:

| Type | Assumed by | Required keys |
|---|---|---|
| `service` | AWS service principals (`ec2.amazonaws.com`, …) | `services` (at least one) |
| `irsa` | exactly one Kubernetes service account | `namespace`, `service_account` - the trust policy is conditioned on `system:serviceaccount:<ns>:<sa>`; without it any pod could assume the role. Needs `oidc_provider_arn` / `oidc_issuer_url` from the eks stack |

| Key | Meaning |
|---|---|
| `name` | the full role name, `<env>-<name>-<region>` |
| `description`, `max_session_duration`, `permissions_boundary` | optional |
| `policy_arns` | managed policy ARNs to attach (AWS-managed, or this stack's `policy_arns` output) |
| `policy` | inline statements; a role must grant something via `policy_arns` and/or `policy` |

## Outputs

`policy_arns`, `role_arns` - maps keyed by the config name.
