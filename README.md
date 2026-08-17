# market-prep-project

Terraform infrastructure for the v2 platform: one directory per
environment, all values in YAML, CI driven by commit messages.

## Layout

```
.
├── .github/workflows/     # plan on branch push, apply on merge - the stack
│                          # folder comes from the commit message (see below)
├── modules/               # Reusable child modules - never run directly
│   ├── vpc/               # VPC, public+private subnets, NAT, S3 endpoint
│   ├── ecr/               # Repositories + lifecycle policies
│   ├── iam/               # Roles: type service (AWS principals) or irsa
│   ├── s3/                # Hardened buckets (encrypted, private, TLS-only)
│   ├── ec2/               # SSM-only instances (no SSH) - for the jump host
│   ├── lb/                # Terraform-owned ALB + ip target groups; pods
│   │                      # join via TargetGroupBinding (never Ingress)
│   └── eks/
│       ├── cluster/       # Cluster, OIDC, access entries (SSO patterns)
│       ├── node-groups/   # Managed node groups
│       └── security-groups/
└── resources/
    ├── global-values.yaml           # org, repo, org-wide tags
    └── us-east-1/
        ├── regional-values.yaml     # region + regional tags
        ├── dev/                     # one complete set of stacks per env
        │   ├── dev-values.yaml      # env name + env tags
        │   ├── network/             # VPC: 2 public + 2 private subnets, NAT
        │   ├── ecr/                 # one YAML per repository in config/
        │   ├── iam/                 # non-cluster IAM roles (config/)
        │   ├── s3/                  # one YAML per bucket in config/
        │   ├── eks/                 # ONE stack: cluster + node groups (ng/)
        │   │                        # + extra SGs (sg/) + identity (iam.yaml)
        │   └── lb/                  # ALB in front of the cluster - one
        │                            # YAML per target group in tg/
        ├── uat/                     # same shape, uat values
        └── prod/                    # same shape, prod values
```

## How changes ship

CI reads the stack folder from the commit message:

```text
[<action>][<stack>] <short description> - Path: /<stack-folder>
[update][network] added a private subnet - Path: /resources/us-east-1/dev/network
```

Push to a feature branch → plan runs in that folder. Merge to `main` →
apply runs there. One stack per PR. Full walkthrough:
[`.github/workflows/README.md`](.github/workflows/README.md).

## Configuration model

Each stack merges four YAML layers into one config, most specific last:

```
global-values.yaml → regional-values.yaml → <env>-values.yaml → <stack>/config.yaml
```

- **Strict lookups on purpose**: every value a stack uses is stated in
  YAML; a missing key fails the plan instead of silently using a module
  default. `# default:` comments are reference only.
- **Per-item files**: `ecr/config/`, `s3/config/`, `iam/config/`,
  `eks/ng/`, `eks/sg/`, `lb/tg/` — one YAML file per repository / bucket /
  role / node group / security group / target group, merged over that
  stack's `*_defaults`. `.example` files are inactive documentation.
- **Cluster identity lives in `eks/iam.yaml`** — access entries (SSO
  role-name patterns, never ARNs) and IRSA roles for workloads, with
  ready-to-uncomment blocks for ebs-csi, Velero, external-dns,
  cert-manager and Bedrock.
- EKS **addons are not managed here** — Flux CD owns them (see
  `resources/*/*/eks/README.md`).

## Environments

| | dev | uat | prod |
|---|---|---|---|
| VPC | 10.0.0.0/16 | 10.2.0.0/16 | 10.1.0.0/16 |
| NAT | single | single | per AZ |
| Cluster API | public | private + VPC-only public | private + VPC-only public |
| Nodes (default) | t3.medium 1/2/3 | t3.large 1/2/4 | m5.large 2/3/5 |
| ECR tags | mutable | immutable | immutable |

Nodes run in the private subnets in all environments; public subnets hold
NAT and internet-facing load balancers (tagged for controller discovery).

## State

State lives in one S3 bucket, and **every state key mirrors this repo's
layout, prefixed with the repo name**:

```
s3://<state-bucket>/<repo-name>/resources/us-east-1/dev/network/terraform.tfstate
                    └────────── same path as in the repo ──────────┘
```

Run Terraform in `resources/us-east-1/dev/network` → the state is at that
same path under the repo-name prefix. No lookup table needed: the repo
path IS the state path. The prefix also lets one bucket host state for
several repos without collisions.

CI injects the key at init time (`<repo-name>` from
`github.event.repository.name`, the stack path from the commit message),
so it is never hardcoded. For local runs use `-backend=false` (below) —
running init with the real backend requires passing the exact same key.

## What is deliberately NOT in this repo

- **State bucket and the CI OIDC roles** — referenced only via Actions
  variables (existing roles, modified ones, or new ones all work), so no
  pipeline change can touch CI's own identity or the state.
- **Account ids, IAM ARNs, personal IPs** — this repo is public. KMS keys
  are referenced by alias, SSO principals by name pattern, bucket names
  get the account id appended at plan time.

## Local runs

```bash
cd resources/us-east-1/dev/<stack>
terraform init -backend=false
terraform plan
```

The eks stack's access-entry lookup needs IAM read on the SSO path -
it works in CI and as PlatformAdmin; PlatformEngineer is denied locally.
Apply order within an env: network first (subnets before nodes), then eks;
ecr/s3/iam are independent.
