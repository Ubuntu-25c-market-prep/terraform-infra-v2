# iam - non-cluster IAM

One file per resource: customer-managed **policies** under `policies/`,
**roles** under `roles/`, both self-contained (no defaults layer). The stack
reads `*.yaml` in each folder; `.yaml.example` files are inactive
documentation - copy one to `<name>.yaml` and edit. `config.yaml` holds
only the GitHub OIDC provider ARN. **IRSA roles are not declared here**:
they are cluster identity and live in `eks/iam.yaml` (`service_accounts`),
which attaches this stack's policies by ARN. CI identity (the GitHub Actions plan/apply roles)
is not managed in this repo at all.

**Nothing is active in uat yet.** The policies and the `uat-ecr-push`
role this env will need are staged as `<name>.yaml.example`; rename one to
`<name>.yaml` to create it.

Adding a policy or role = adding one file, named after its `name`. No
`.tf` changes.

## Policies (`policies/<name>.yaml`)

Each file is one customer-managed policy named exactly as its `name`
(`<env>-<Name>-<region>`, e.g. `uat-ExternalDnsPolicy-us-east-1`). They
exist so any role can attach them **by ARN**: roles in this stack
(`policy_arns`) or IRSA roles in `eks/iam.yaml` (`attached_policies`).
Flow: add the file → apply this stack → read the ARN from the
`policy_arns` output → paste it where it is used.

| Key | Meaning |
|---|---|
| `name` | the full policy name, must equal the file name |
| `description` | optional |
| `statements[]` | `actions`, `resources`; optional `sid`, `effect` (default `Allow`), `conditions` |
| `statements[].conditions` | IAM Condition as written in JSON: `{operator: {key: [values]}}`, e.g. `"ForAllValues:StringEquals": {route53:ChangeResourceRecordSetsRecordTypes: [TXT]}`; values are always lists |

## Roles (`roles/<name>.yaml`)

Each file is one role. Two types (IRSA: `eks/iam.yaml`):

| Type | Assumed by | Required keys |
|---|---|---|
| `service` | AWS service principals (`ec2.amazonaws.com`, …) | `services` (at least one) |
| `github` | one GitHub repository's workflow on one ref (a CI pipeline, e.g. an app build pushing to ECR) | `github_org` (`<org>@<org id>`), `github_repository` (`<repo>@<repo id>`), `github_ref` - the trust is `StringEquals` on `repo:<org>/<repo>:ref:<ref>` in this org's immutable-id form; a plain `repo:<org>/<repo>` matches nothing. Needs `github_oidc_provider_arn` (the account's GitHub OIDC provider) |

| Key | Meaning |
|---|---|
| `name` | the full role name, must equal the file name |
| `type` | `service` (default) or `github` |
| `description`, `max_session_duration`, `permissions_boundary` | optional |
| `policy_arns` | managed policy ARNs to attach (AWS-managed, or this stack's `policy_arns` output) |
| `policy` | inline statements, same shape as a policy file's `statements[]`; a role must grant something via `policy_arns` and/or `policy` |

## Outputs

`policy_arns`, `role_arns` - maps keyed by the config name.
