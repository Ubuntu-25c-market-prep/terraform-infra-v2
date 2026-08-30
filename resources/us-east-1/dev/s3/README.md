# s3 - buckets

Hardened buckets (encrypted, private, TLS-only), one per entry in
`config.yaml` `buckets`, merged over `bucket_defaults`. The final name
is `<org>-<env>-<name>-<account-id>` - the account id is appended at
plan time so names are globally unique.

## Keys

| Key | Meaning |
|---|---|
| `versioning` | keep previous object versions |
| `force_destroy` | `true` lets `terraform destroy` delete a bucket that still holds objects |
| `lifecycle_rules[]` | `id`, optional `prefix`, `expiration_days` (current versions), `noncurrent_expiration_days` (old versions) |
| `buckets[].name` | required; other keys override the defaults for that bucket |
