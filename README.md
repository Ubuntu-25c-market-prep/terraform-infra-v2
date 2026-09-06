# terraform-infra-v2

Terraform infrastructure for the v2 platform: one directory per
environment, all values in YAML, CI driven by commit messages.

## Layout

```
.
├── .github/workflows/     # plan on branch push, apply on merge - the stack
│                          # folder comes from the commit message (see below)
├── modules/               # Reusable child modules - never run directly
│   ├── vpc/               # VPC, public+private subnets, S3+DynamoDB gateway endpoints, no NAT
│   ├── ecr/               # Repositories + lifecycle policies
│   ├── iam-roles/         # Roles: type service (AWS principals) or irsa
│   ├── s3/                # Hardened buckets (encrypted, private, TLS-only)
│   ├── bastion/           # jump host reached over SSM (no inbound port)
│   ├── alb/               # Terraform-owned ALB + ip target groups; pods
│   │                      # join via TargetGroupBinding (never Ingress)
│   ├── nlb/               # Terraform-owned NLB (L4: TCP/UDP/TLS) + ip target
│   │                      # groups, one listener per group; same binding model
│   └── eks/
│       ├── cluster/       # Cluster, OIDC, access entries (SSO patterns)
│       ├── node-groups/   # Managed node groups
│       └── security-groups/
└── resources/
    ├── global-values.yaml           # org, repo, shared tags
    └── us-east-1/
        ├── regional-values.yaml     # region + regional tags
        ├── dev/                     # one complete set of stacks per env
        │   ├── dev-values.yaml      # env name + env tags
        │   ├── network/             # VPC: 2 public + 2 private subnets, no NAT
        │   ├── ecr/                 # repositories array in config.yaml
        │   ├── iam-roles/           # non-cluster IAM roles (roles array in config.yaml)
        │   ├── s3/                  # buckets array in config.yaml
        │   ├── eks/                 # ONE stack: cluster + node groups (ng/)
        │   │                        # + extra SGs (sg/) + identity (iam.yaml)
        │   ├── alb/                 # ALB in front of the cluster - target
        │   │                        # groups array in config.yaml
        │   └── nlb/                 # NLB for L4 traffic (mesh ingress, TCP/
        │                            # UDP) - target groups array in config.yaml
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

## Naming

Resources are named `<env>-<component>-<region>` - `dev-vpc-us-east-1`,
`dev-eks-us-east-1`, `dev-bastion-us-east-1`, `dev-alb-us-east-1` - with
the parts a component owns appended (`dev-eks-us-east-1-node`,
`dev-vpc-us-east-1-public-a`). The org is not in the name: every
resource carries it as the `Org` default tag. Exceptions: IRSA roles
(`<env>-irsa-<workload>-<region>`), node groups (`<env>-ng-<pool>-<region>`,
the `ng/` file name), route tables (`<env>-route-<region>-<public|private>`),
S3 buckets (`<env>-s3-<region>-<name>-<account-id>`) and ECR
repositories (`<env>-ecr-<region>/<app>`; the dev registry serves every
environment until uat and prod have their own accounts).

## Getting in

Laptop setup, node shells and kubectl through the bastion:
[`docs/access.md`](docs/access.md).

## Configuration model

Each stack merges four YAML layers into one config, most specific last:

```
global-values.yaml → regional-values.yaml → <env>-values.yaml → <stack>/config.yaml
```

- **Strict lookups on purpose**: every value a stack uses is stated in
  YAML; a missing key fails the plan instead of silently using a module
  default. `# default:` comments are reference only.
- **Per-item arrays**: repositories, buckets, roles and target groups are
  arrays in their stack's `config.yaml` (`ecr.repositories`, `s3.buckets`,
  `iam.roles`, `alb.target_groups`, `nlb.target_groups`), each entry merged
  over that stack's `*_defaults`; a commented example entry under each
  array is the template. The eks stack is the exception: node groups and
  security groups stay one file each under `eks/ng/` and `eks/sg/`
  (`.example` files are inactive documentation).
- **Cluster identity lives in `eks/iam.yaml`** — access entries (keyed by
  ARN, or by a short name resolved via SSO role-name pattern) and IRSA
  roles for workloads (full names, policies by ARN), with
  ready-to-uncomment blocks for ebs-csi, the LB controller, Velero,
  external-dns, cert-manager and Bedrock. The customer-managed policies
  they reference are declared in the `iam-roles` stack's `policies` array.
- EKS **addons are not managed here** — Flux CD owns them (see
  `resources/*/*/eks/README.md`).

## Environments

| | dev | uat | prod |
|---|---|---|---|
| VPC | 10.1.0.0/16 | 10.2.0.0/16 | 10.3.0.0/16 |
| NAT | none | none | none |
| Cluster API | private, via bastion | private, via bastion | private, via bastion |
| Nodes (default) | t3.medium 1/2/3 | t3.large 1/2/4 | m5.large 2/3/5 |
| ECR tags | mutable | immutable | immutable |

Nodes run in the public subnets in all environments, alongside the
bastion and internet-facing load balancers: no NAT gateway anywhere, so
`map_public_ip_on_launch` gives nodes public IPs and internet egress via
the IGW, with security groups as the only inbound barrier - the cluster
SG itself, the bastion on :22, and the ALB SG on target ports. The
Kubernetes API has no public endpoint; the bastion's security group is
allowed to :443 on the control plane (`eks/README.md` "Access model"). The private
subnets hold only the control-plane ENIs and have no internet egress
(S3 and DynamoDB via the free gateway endpoints only). NAT is not implemented in the vpc module;
if private egress is ever needed it is a deliberate module change.

## State

State lives in one S3 bucket **per environment**, named
`<env>-u25c-tfstate-infra-v2-<account-id>` (each environment's `TFSTATE_BUCKET`
Actions variable holds its bucket; only dev exists today), and **every state
key mirrors this repo's layout, prefixed with the repo name**:

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
- **Personal/office IPs and secrets** (private keys, tokens). Resource
  ids and ARNs (VPC, subnets, security groups, KMS keys, ACM
  certificates, the OIDC provider) ARE committed: stacks read no remote
  state, each states the ids it needs in its `config.yaml`. Where a
  lookup is still offered (KMS by alias, SSO roles by name pattern) it is
  a convenience, not a rule.

## Local runs

```bash
cd resources/us-east-1/dev/<stack>
terraform init -backend=false
terraform plan
```

The eks stack's access-entry lookup needs IAM read on the SSO path -
it works in CI and as PlatformAdmin; PlatformEngineer is denied locally.

## Apply order and id hand-off

Stacks never read each other's state. Ids flow between them through
`config.yaml`, pasted from the previous stack's outputs - once per env,
and again only if the resource is recreated:

1. `network` → outputs `vpc_id`, `public_subnet_ids`, `private_subnet_ids`
2. paste into `eks/config.yaml` (+ `eks/ng/*.yaml`), `bastion/config.yaml`,
   `alb/config.yaml`, `nlb/config.yaml`
3. `eks` → outputs `cluster_security_group_id`, `oidc_provider_arn`,
   `oidc_issuer_url`
4. paste into `alb`/`nlb` (`backend_security_group_id`) and `iam-roles`
   (`oidc_*`, only needed for irsa roles)
4b. IRSA policies: `iam-roles` (`policies` array) → output `policy_arns` →
   paste into `eks/iam.yaml` `attached_policies`, then apply `eks`
5. `bastion`, `alb`, `nlb`, `iam-roles` in any order; `ecr`/`s3` anytime
6. `bastion` → outputs `private_ips` (as a /32 into `eks/config.yaml`
   `node_jump_server_ssh`) and `security_group_id` (into
   `eks.cluster_ingress_rules`); `ssh_key_name` is already the bastion key
   pair name. Node SSH is creation-only, so `bastion` applies before `eks`

`REPLACE-ME` placeholders fail the plan on purpose until real ids are in.
