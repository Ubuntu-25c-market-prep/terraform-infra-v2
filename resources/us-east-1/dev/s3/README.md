# s3 - buckets

Hardened buckets (encrypted, private, TLS-only, versioned, incomplete
multipart uploads aborted after 7 days), one per entry in `config.yaml`
`buckets`, merged over `bucket_defaults`. The
final name is `<env>-s3-<region>-<name>-<account-id>`
(`dev-s3-us-east-1-velero-<account-id>`); the account id is appended at
plan time for global uniqueness, which leaves 33 characters for `name`
(checked at plan).

## Adding a bucket

1. Add an entry under `buckets` in `config.yaml` (the commented example
   is the template); any `bucket_defaults` key can be overridden.
2. Open a PR with `- Path: /resources/us-east-1/dev/s3` in the commit
   message; merge applies it. Read the ARN from the `bucket_arns` output.
3. Give the workload access: a policy in `../iam-roles/config.yaml`
   (`policies`) naming that ARN, then an IRSA role in `../eks/iam.yaml`
   with the policy ARN in `attached_policies`, bound to the app's
   service account. The commented Velero entries in both files show the
   full path.

## Keys

| Key | Meaning |
|---|---|
| `versioning` | keep previous object versions |
| `force_destroy` | `true` lets `terraform destroy` delete a bucket that still holds objects |
| `lifecycle_rules[]` | `id`, optional `prefix`, `expiration_days` (current versions), `noncurrent_expiration_days` (old versions) |
| `buckets[].name` | required, lowercase with dashes, at most 33 characters; other keys override the defaults for that bucket |
