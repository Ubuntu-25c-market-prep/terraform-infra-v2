# ecr - container repositories

One repository per entry in `config.yaml` `repositories`, each merged
over `repository_defaults`. Names come out as `<org>-<env>-<name>`.

## Keys

| Key | Meaning |
|---|---|
| `image_tag_mutability` | `MUTABLE` (dev: tags can be re-pushed) or `IMMUTABLE` (uat/prod: a deployed tag can never be overwritten) |
| `scan_on_push` | ECR vulnerability scan on every push |
| `force_delete` | `true` lets `terraform destroy` delete a repository that still holds images |
| `untagged_expiry_days` | lifecycle rule: expire untagged images after N days; `null` = never |
| `max_image_count` | lifecycle rule: keep at most N images. **Counts tagged images too** - a busy repo can expire images still in use; size generously or set `null` and rely on `untagged_expiry_days` |
| `repositories[].name` | required; other keys override the defaults for that repo |
