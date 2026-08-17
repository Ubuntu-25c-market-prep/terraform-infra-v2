# Terraform CI/CD Workflows

> **Currently DISABLED**: both workflow files are fully commented out so
> nothing can plan or apply while the code is still being built. Remove
> the leading `# ` from every line (below each file's header note) to
> re-enable them.

Two workflows automate Terraform for this repo:

| File | Trigger | What it runs |
|---|---|---|
| `terraform-plan.yml` | Push to any branch **except** `main` | `terraform init` → `validate` → `plan` |
| `terraform-apply.yml` | Push to `main` (i.e. a merge) | `terraform init` → `apply` |

Both read **which stack folder to run Terraform in from the commit message**, using this convention:

```text
[<action>][<stack>] <short description> - Path: /<stack-folder>
```

For example:

```text
[update][network] added a private subnet - Path: /resources/us-east-1/dev/network
[create][eks] tainted node group for ELK - Path: /resources/us-east-1/uat/eks
```

The folder comes from the `Path: /...` part — the full path from the repo
root, environment included. The second bracket tag (`[network]`) is a
**typo cross-check**: a warning is printed when it doesn't match the stack
folder's name. It never picks the folder itself — a bare tag like `eks`
can't say *which environment's* eks stack is meant.

The rest of this doc explains every block, top to bottom. The two files are ~90% identical, so the shared blocks are explained once and the differences are called out at the end.

---

## Top-level blocks

### `name`

```yaml
name: Terraform Plan
```

The display name in the GitHub Actions UI (the "Actions" tab and the checks on a commit/PR). Cosmetic only.

### `on` — the trigger

```yaml
# plan
on:
  push:
    branches-ignore:
      - main

# apply
on:
  push:
    branches:
      - main
```

`on` declares which GitHub events start the workflow.

- **Plan** runs on a push to *any branch except* `main` — every push to a feature branch gets a fresh plan.
- **Apply** runs on a push *to* `main`. Merging a PR into `main` **is** a push to `main`, so "apply on merge" is expressed as `push: branches: [main]`. This also means a direct push to `main` triggers apply — branch protection on `main` is what prevents that in practice.

### `permissions`

```yaml
permissions:
  contents: read
  id-token: write   # required for AWS OIDC
```

Restricts what the workflow's auto-generated `GITHUB_TOKEN` can do (least privilege):

- `contents: read` — enough to check out the repo.
- `id-token: write` — allows the job to request an **OIDC token** from GitHub. AWS exchanges that token for temporary credentials (see the OIDC step below). Without this line the AWS credentials step fails.

### `env`

```yaml
env:
  AWS_REGION: us-east-1   # must match regional-values.yaml
```

The AWS region, hardcoded at the top of each file so it is visible at a glance. It is not sensitive, and it must match `region:` in `resources/us-east-1/regional-values.yaml`. If the team ever deploys to more regions, this is the value to move into an Actions variable or derive from the Path.

---

## The steps

### Checkout

```yaml
- name: Checkout
  uses: actions/checkout@v5
```

`uses:` pulls a reusable action from the marketplace — checkout clones the repo onto the runner so the stack folders (and their `.tf` files) exist on disk.

### Read stack folder from commit message (`id: target`)

The step that decides *where* Terraform runs. In plain English:

1. **Extract the Path** — `Path: /resources/us-east-1/dev/network` → `resources/us-east-1/dev/network` (case-insensitive, leading/trailing slashes stripped).
2. **Check it is a real folder** — a missing or misspelled Path fails with a clear error showing the expected format. There is no fallback: the Path is the single source of truth.
3. **Typo cross-check** — the second bracket tag is compared against the folder's *name* (`[network]` vs `.../dev/network` → ok). On mismatch a warning is printed; the Path still wins.
4. **Refuse child modules** — `Path: /modules/...` fails: modules are not runnable roots, the commit must name the stack that consumes the module.
5. **Publish the result** — `echo "dir=$dir" >> "$GITHUB_OUTPUT"` makes the folder available to later steps as `steps.target.outputs.dir`.

Two details worth knowing:

- In the plan workflow, the commit message is passed in through `env:` rather than pasted into the script — that avoids shell-injection issues from `'` or `$` characters in commit messages.
- On a push with several commits, GitHub's `head_commit` is the **last** commit — that one's message decides (plan workflow only; see below for apply).

**The apply workflow scans the merged commits instead.** A merge commit's own message is usually GitHub's default "Merge pull request #12 …", which has no `Path:`. So the apply version of this step doesn't read one message — it walks *every commit the merge brought in* (`git rev-list before..HEAD`, newest first) and uses the first message whose Path names a valid folder. Since the branch commits already carry the convention (the plan workflow ran on them), **any merge style works** — merge commit, squash, or rebase. This is also why the apply workflow's checkout uses `fetch-depth: 0`: it needs git history, not just the tip commit.

### Configure AWS credentials (OIDC)

```yaml
- name: Configure AWS credentials (OIDC)
  uses: aws-actions/configure-aws-credentials@v5
  with:
    role-to-assume: ${{ vars.AWS_ROLE_ARN_PLAN }}    # plan workflow
    role-to-assume: ${{ vars.AWS_ROLE_ARN_APPLY }}   # apply workflow
    aws-region: ${{ env.AWS_REGION }}
```

No long-lived AWS keys anywhere. The action asks GitHub for a short-lived OIDC token (allowed by `id-token: write`), sends it to AWS STS, and assumes the IAM role. AWS verifies the token really came from this repo (the role's trust policy pins the repo/branch). The resulting temporary credentials are exported as env vars, which the Terraform AWS provider picks up automatically.

Each workflow assumes its own role. **Both roles — and the state bucket — are deliberately NOT managed in this repo** (point the Actions variables at existing roles, modified ones, or new ones - the workflows only reference them), so no pipeline change can ever touch CI's own identity or the state:

- **Plan role** — assumable from any branch of this repo; read-only plus write access to the state lockfile.
- **Apply role** — assumable only from `main` or the `aws-apply` GitHub environment; write access.

The role ARNs are not sensitive, so they live in **Actions variables** (`vars.`, Settings → Secrets and variables → Actions → Variables) where they're visible and auditable — secrets are reserved for values that must stay hidden.

### Setup Terraform

```yaml
- name: Setup Terraform
  uses: hashicorp/setup-terraform@v3
  with:
    terraform_version: "1.12.2"   # PLACEHOLDER: pin to your version
```

Installs the Terraform CLI on the runner at a pinned version, so CI always runs the same version regardless of runner image updates.

### Terraform steps

```yaml
- name: Terraform Init
  working-directory: ${{ steps.target.outputs.dir }}
  run: terraform init -input=false
```

`working-directory` is where the commit-message parsing pays off: every Terraform command runs inside the chosen stack folder. `-input=false` makes Terraform fail instead of waiting for interactive input that will never come in CI.

- **Plan workflow:** `init` → `validate` (syntax/consistency check, needs no AWS) → `plan`.
- **Apply workflow:** `init` → `apply -auto-approve`. The `-auto-approve` skips the interactive "yes" prompt; the human review already happened at PR time via the plan output.

The commented `-backend-config` block under `init` is a **placeholder** for the future S3 remote state backend. The bucket name contains the account id, so it is never committed (public repo) — it goes in the `TFSTATE_BUCKET` Actions variable. **State keys mirror the repo layout, prefixed with the repo name** — `<repo-name>/resources/us-east-1/dev/network/terraform.tfstate` — so finding a stack's state in S3 is the same path you'd use in the repo, and one bucket can host state for several repos without collisions. The repo name comes from `github.event.repository.name` at runtime; the stack path is the parsed folder, so each stack in each environment gets its own state file automatically.

---

## Differences between the two files

| | `terraform-plan.yml` | `terraform-apply.yml` |
|---|---|---|
| Trigger | push to any branch except `main` | push to `main` |
| Where the folder comes from | the pushed head commit's message | the merged commits' messages, newest first (any merge style works) |
| Checkout | shallow (default) | `fetch-depth: 0` — needs history to read the merged commits |
| Terraform | `init`, `validate`, `plan` | `init`, `apply -auto-approve` |
| Extra safety | — | commented-out `environment: aws-apply` — uncomment it (and create the environment with required reviewers) to add a manual approval gate before every apply |

## Rules the team must follow

Because commit messages are the source of truth, the workflows only work when they are written correctly:

1. **Every commit that should trigger Terraform needs the convention** — `[<action>][<stack>] <description> - Path: /<stack-folder>`, with the FULL path from the repo root (environment included). Merge however you like: apply finds the convention in the branch commits, so the merge commit message doesn't matter.
2. **One stack per commit/PR** — a message can only name one folder, and the apply uses the first valid one it finds. Pushing changes for two stacks to one branch means only one gets applied — silently.
3. **Changes to `modules/` name the consuming stack** — `Path: /modules/...` is refused; plan the change through a stack that sources the module (and remember the other environments consume it too).

## Required repository configuration

| Where | Name | Purpose |
|---|---|---|
| Actions variable | `AWS_ROLE_ARN_PLAN` | read-only role for plans — an existing or new role ARN; not managed in this repo |
| Actions variable | `AWS_ROLE_ARN_APPLY` | write role for applies — an existing or new role ARN; not managed in this repo |
| Actions variable | `TFSTATE_BUCKET` | S3 state bucket name (contains the account id — never committed); needed once the S3 backend is enabled |
| Workflow `env:` block (hardcoded) | `AWS_REGION` | AWS region — set to `us-east-1`, must match `regional-values.yaml` |

Everything on the AWS side (state bucket, both OIDC CI roles) is **deliberately not managed here** — the Actions variables above are the only link, and they can point at existing roles, modified ones, or new ones. The account-level GitHub OIDC identity provider is likewise only referenced, never created.
