# ecr - container repositories

One repository per entry in `config.yaml` `repositories`, each merged
over `repository_defaults`. Names come out as `<env>-ecr-<region>/<name>`
(`dev-ecr-us-east-1/storefront`). The dev registry serves every
environment until uat and prod have their own accounts; the uat/prod
stacks stay unapplied until then. Tags are mutable in dev.

## Adding a repository

1. Add an entry under `repositories` in `config.yaml` (the commented
   example is the template); any `repository_defaults` key can be
   overridden per entry.
2. Open a PR with `- Path: /resources/us-east-1/dev/ecr` in the commit
   message. The plan shows the new repository; merge applies it.
3. Read the URL from the `repository_urls` output:
   `<account>.dkr.ecr.us-east-1.amazonaws.com/dev-ecr-us-east-1/<name>`.

Pulling from the cluster already works: the node role carries
`AmazonEC2ContainerRegistryReadOnly`. Pushing needs a CI role with
`ecr:GetAuthorizationToken` and push rights on
`repository/dev-ecr-us-east-1/*`; CI identities are not managed in this repo.

## Keys

| Key | Meaning |
|---|---|
| `image_tag_mutability` | `MUTABLE` (dev: tags can be re-pushed) or `IMMUTABLE` (uat/prod: a deployed tag can never be overwritten) |
| `scan_on_push` | ECR vulnerability scan on every push |
| `force_delete` | `true` lets `terraform destroy` delete a repository that still holds images |
| `untagged_expiry_days` | lifecycle rule: expire untagged images after N days; `null` = never |
| `max_image_count` | lifecycle rule: keep at most N images. **Counts tagged images too** - a busy repo can expire images still in use; size generously or set `null` and rely on `untagged_expiry_days` |
| `repositories[].name` | required, lowercase with `. _ / -`; other keys override the defaults for that repo |
