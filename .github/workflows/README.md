# Terraform CI/CD Workflows

Two workflows automate Terraform for this repo:

| File | Trigger | What it runs |
|---|---|---|
| `terraform-plan.yml` | Push to any branch **except** `main` | `terraform init` → `validate` → `plan` |
| `terraform-apply.yml` | Push to `main` (i.e. a merge) | `terraform init` → `apply` |
| `security.yml` | PRs, push to `main`, weekly | the org's shared `security-scan.yml` (gitleaks, forbidden files, trivy) |

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
root, environment included. The bracket tags (`[update][network]`) are for
humans reading the log; the workflows don't parse them. A bare tag like
`eks` couldn't pick the folder anyway — it can't say *which environment's*
eks stack is meant.

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

### `concurrency`

```yaml
# plan
concurrency:
  group: plan-${{ github.ref }}
  cancel-in-progress: true

# apply
concurrency:
  group: apply
```

Only one run per group at a time.

- **Plan**: the group is the branch name, and a newer run cancels the older one — push twice quickly and only the latest plan runs. The old plan was for code that no longer exists.
- **Apply**: one group for everything and nothing is cancelled — two merges close together apply one after the other instead of fighting over the state lock.

### `jobs` — two jobs, and why

```yaml
jobs:
  target:                 # reads the Path, outputs dir + env
    outputs:
      dir: ${{ steps.target.outputs.dir }}
      env: ${{ steps.target.outputs.env }}
  plan:                   # (apply in the other file)
    needs: target
    environment: ${{ needs.target.outputs.env }}
```

In one sentence each: **`target` reads the commit message and works out the stack folder and its env; `plan`/`apply` runs Terraform inside the GitHub environment with that name.**

Why two jobs: `environment:` is a job-level setting — it can't be set by a step in the same job. So the Path is read in a small first job, handed over as job `outputs`, and the second job uses it. Every later step refers to `needs.target.outputs.dir` (from the other job) instead of `steps.target.outputs.dir` (same job).

Why an environment at all: the env folder name (`dev`, `uat`, `prod` — the third segment of the Path) becomes the GitHub environment name. Variables are then looked up **per environment**: `vars.AWS_ROLE_ARN_PLAN` is one line in the workflow, but the `prod` environment holds the prod account's role ARN and `dev` holds dev's. One workflow, any number of environments/accounts, nothing hardcoded. The environment is also where **required reviewers** go — put them on `prod` and every prod apply waits for a human.

Since each job is a fresh runner, the second job checks out the repo again.

---

## The steps

### Checkout

```yaml
- name: Checkout
  uses: actions/checkout@v5
```

`uses:` pulls a reusable action from the marketplace — checkout clones the repo onto the runner so the stack folders (and their `.tf` files) exist on disk.

### Read stack folder from commit message (`id: target`)

The step that decides *where* Terraform runs. Three shell lines:

```bash
dir="$(echo "$COMMIT_MSG" | grep -o 'Path: */[^ ]*' | head -1 | sed 's|Path: */||')"
if [ ! -d "$dir" ] || [[ "$dir" != resources/* ]]; then ... exit 1; fi
echo "dir=$dir" >> "$GITHUB_OUTPUT"
```

In plain English:

1. **Extract the Path** — `grep` finds the first `Path: /...` in the message, `sed` drops the `Path: /` prefix: `Path: /resources/us-east-1/dev/network` → `resources/us-east-1/dev/network`.
2. **Check it is a real stack folder** — it must exist *and* be under `resources/`. A missing or misspelled Path, or `Path: /modules/...` (modules are not runnable roots), fails with an error showing the expected format. There is no fallback: the Path is the single source of truth.
3. **Work out the env** — `cut -d/ -f3` takes the third folder: `resources/us-east-1/prod/alb` → `prod`. This becomes the GitHub environment name.
4. **Publish the result** — writing `dir=...` and `env=...` to `$GITHUB_OUTPUT` makes them step outputs; the job's `outputs:` block re-exports them so the next job can read `needs.target.outputs.dir`. The same values written to `$GITHUB_STEP_SUMMARY` show on the run's overview page, and the Terraform steps put the folder in their names — `Terraform Apply (resources/us-east-1/prod/alb)` — so where Terraform ran is visible without opening any log.

Two details worth knowing:

- In the plan workflow, the commit message is passed in through `env:` rather than pasted into the script — that avoids shell-injection issues from `'` or `$` characters in commit messages.
- On a push with several commits, GitHub's `head_commit` is the **last** commit — that one's message decides (plan workflow only; see below for apply).

**The apply workflow reads the merged commits instead.** A merge commit's own message is usually GitHub's default "Merge pull request #12 …", which has no `Path:`. So the apply version feeds the same three lines with `git log --format=%B before..HEAD` — the messages of *every commit the merge brought in*, newest first — and the first `Path:` found wins. Since the branch commits already carry the convention (the plan workflow ran on them), **any merge style works** — merge commit, rebase, or squash (for squash, keep GitHub's default squash message "Pull request title and commit details" so the branch messages survive into the squash commit). This is also why the apply workflow's checkout uses `fetch-depth: 0`: it needs git history, not just the tip commit.

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

Each workflow assumes its own role, **per environment**. **The roles — and the state bucket — are deliberately NOT managed in this repo** (point the variables at existing roles, modified ones, or new ones - the workflows only reference them), so no pipeline change can ever touch CI's own identity or the state:

- **Plan role** — read-only plus write access to the state lockfile; its trust policy allows `repo:<org>/<repo>:environment:<env>`.
- **Apply role** — write access; trust policy likewise pinned to the environment.

With one AWS account per env, each account has its own plan and apply role (same names, different account id in the ARN) and its own GitHub OIDC identity provider. The role ARNs are not sensitive, so they live in **environment variables** (Settings → Environments → `<env>` → Variables) under the same name in every environment — `vars.AWS_ROLE_ARN_PLAN` resolves to whichever environment the job declared. Secrets are reserved for values that must stay hidden.

### Setup Terraform

```yaml
- name: Setup Terraform
  uses: hashicorp/setup-terraform@v3
  with:
    terraform_version: "1.12.2"   # PLACEHOLDER: pin to your version
```

Installs the Terraform CLI on the runner at a pinned version, so CI always runs the same version regardless of runner image updates.

### Terraform Format (plan only)

```yaml
- name: Terraform Format
  run: terraform fmt -check -recursive modules resources
```

Fails the plan if any `.tf` file isn't formatted the way `terraform fmt` would write it. Runs on the whole repo (it's instant), before anything touches AWS. Fix locally with `terraform fmt -recursive`.

### Terraform steps

```yaml
- name: Terraform Init (${{ needs.target.outputs.dir }})
  working-directory: ${{ needs.target.outputs.dir }}
  run: terraform init -input=false
```

`working-directory` is where the commit-message parsing pays off: every Terraform command runs inside the chosen stack folder (read from the `target` job via `needs.target.outputs.dir`). `-input=false` makes Terraform fail instead of waiting for interactive input that will never come in CI.

- **Plan workflow:** `init` → `validate` (syntax/consistency check, needs no AWS) → `plan`.
- **Apply workflow:** `init` → `apply -auto-approve`. The `-auto-approve` skips the interactive "yes" prompt; the human review already happened at PR time via the plan output.

The commented `-backend-config` block under `init` is a **placeholder** for the future S3 remote state backend. The bucket name differs per environment, so it lives in the `TFSTATE_BUCKET` environment variable (one bucket per account, so per environment) rather than in the workflow file. **State keys mirror the repo layout, prefixed with the repo name** — `<repo-name>/resources/us-east-1/dev/network/terraform.tfstate` — so finding a stack's state in S3 is the same path you'd use in the repo, and one bucket can host state for several repos without collisions. The repo name comes from `github.event.repository.name` at runtime; the stack path is the parsed folder, so each stack in each environment gets its own state file automatically.

---

## Differences between the two files

| | `terraform-plan.yml` | `terraform-apply.yml` |
|---|---|---|
| Trigger | push to any branch except `main` | push to `main` |
| Where the folder comes from | the pushed head commit's message | the merged commits' messages, newest first (any merge style works) |
| Checkout | shallow (default) | `fetch-depth: 0` — needs history to read the merged commits |
| Concurrency | per branch, newer run cancels older | one global group, runs queue, never cancelled |
| Terraform | `fmt -check`, `init`, `validate`, `plan` | `init`, `apply -auto-approve` |
| Environment | `dev`/`uat`/`prod` from the Path — picks the plan role | same — picks the apply role; **required reviewers on `prod`** = manual approval before every prod apply |

Note: reviewers on an environment gate *every* job that declares it, plans included. If approving prod plans is unwanted, use separate environments for plan (`prod-plan`, no reviewers) and apply (`prod`) — a one-line change in the plan workflow (`environment: ${{ needs.target.outputs.env }}-plan`).

## Rules the team must follow

Because commit messages are the source of truth, the workflows only work when they are written correctly:

1. **Every commit that should trigger Terraform needs the convention** — `[<action>][<stack>] <description> - Path: /<stack-folder>`, with the FULL path from the repo root (environment included). Merge however you like: apply finds the convention in the branch commits, so the merge commit message doesn't matter.
2. **One stack per commit/PR** — a message can only name one folder, and the apply uses the first valid one it finds. Pushing changes for two stacks to one branch means only one gets applied — silently.
3. **The Path must match the files you changed** — the workflows check that the Path is a real stack folder, not that it's the folder you edited. A Path naming `dev` with changes in `prod` plans and applies dev (no changes) and leaves prod unapplied, without any error. Read your own Path before pushing.
4. **Changes to `modules/` name the consuming stack** — `Path: /modules/...` is refused; plan the change through a stack that sources the module (and remember the other environments consume it too).

## Required repository configuration

| Where | Name | Purpose |
|---|---|---|
| GitHub environments | `dev`, `uat`, `prod` | one per env folder under `resources/<region>/` — names must match the folder names exactly. Required reviewers on `prod`. |
| Environment variable (in each) | `AWS_ROLE_ARN_PLAN` | read-only role for plans in that env's account — an existing or new role ARN; not managed in this repo |
| Environment variable (in each) | `AWS_ROLE_ARN_APPLY` | write role for applies in that env's account — an existing or new role ARN; not managed in this repo |
| Environment variable (in each) | `TFSTATE_BUCKET` | that account's S3 state bucket (per-environment value); needed once the S3 backend is enabled |
| Workflow `env:` block (hardcoded) | `AWS_REGION` | AWS region — set to `us-east-1`, must match `regional-values.yaml` |

Adding a new env = a new folder under `resources/<region>/` **and** a GitHub environment of the same name with its three variables. Nothing in the workflow files changes.

Everything on the AWS side (state buckets, OIDC CI roles, the per-account GitHub OIDC identity provider) is **deliberately not managed here** — the environment variables above are the only link, and they can point at existing roles, modified ones, or new ones.
