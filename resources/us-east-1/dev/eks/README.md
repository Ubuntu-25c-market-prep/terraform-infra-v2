# EKS stack (cluster + node groups + security groups + identity)

One stack owns the cluster, its managed node groups, any extra security
groups, and cluster identity: `iam.yaml` (template format) holds
`access_entries` — who may call the Kubernetes API, keyed by principal;
an `arn:` key is used verbatim, any other key is a name resolved at plan
time from `role_name`/`role_name_pattern` (SSO) — plus `service_accounts`
(the IRSA roles workloads assume, keyed by role name with
`namespace_service_account: <ns>/<sa>` and `attached_policies` and/or
inline `policy`) and `iam_role_tags` (extra tags on the IRSA roles).
`config.yaml` keeps only infrastructure settings, in the org eks
template shape: flat cluster/infra keys
(`cluster_name`, `cluster_version`, `kms_key_id`, ...) up top and the
cluster behaviour under `eks:`. `vpc_id`/`cluster_subnet_ids` are the
network stack's output ids, pasted in after that stack is applied - this
stack reads no remote state; `kms_key_id` is a key id, ARN or alias.
`ssh_key_name` (an EC2 key pair, e.g. the bastion stack's
`key_pair_name`) plus `node_jump_server_ssh` (the bastion's private IP
as a /32) enable SSH to the nodes from the bastion only; both `null` =
no remote access. IRSA roles are named exactly as their `iam.yaml` key
(`<env>-irsa-<workload>-<region>` - the region is in the name because the
role is bound to this cluster's OIDC provider) and get the cluster's OIDC
provider wired directly. Non-cluster IAM stays in the separate `iam-roles/` stack. Addons (vpc-cni, kube-proxy, coredns, ...) are **not**
managed here — Flux CD owns them after the cluster is up. EKS still
installs its default self-managed versions at creation, so nodes join
before Flux runs.

## Naming

The cluster is `<env>-eks-<region>` (`dev-eks-us-east-1`, README "Naming")
and prefixes what it owns: `dev-eks-us-east-1-role` (cluster role),
`dev-eks-us-east-1-node-role`, `dev-eks-us-east-1-node-ssh-sg`, and every
extra security group (`dev-eks-us-east-1-cluster-ingress`). Node groups are
`<env>-<ng file name>` (`dev-ng-system-od-us-east-1`); IRSA roles
`<env>-irsa-<workload>-<region>`. Changing `cluster_name` recreates the
cluster.

## Access model

- **Kubernetes API**: the public endpoint is off; the private endpoint is
  reached from inside the VPC only. `eks.cluster_ingress_rules` opens :443
  on the control-plane ENIs to the bastion's security group, so kubectl
  goes through the bastion (SSH tunnel or SSM port-forward). Terraform in
  CI never talks to the Kubernetes API (Flux owns addons), so CI needs no
  path in. `public_access_cidrs` stays at the VPC CIDR so that flipping
  `endpoint_public_access` back on does not expose the endpoint.
- **Nodes** sit in public subnets with public IPs (no NAT), so inbound is
  only what security groups allow: the EKS cluster SG itself, the bastion's
  private IP on :22 (`node_jump_server_ssh`, a /32 on the SSH SG), and the
  ALB's security group on registered target ports (added by the alb
  stack). `shared_node_ingress_rules` stays `{}` unless something else
  must reach the nodes directly.
- **Secrets encryption** uses the EKS default (AWS-managed);
  `kms_key_id: null`. A customer-managed key is a KMS ARN there.

## Extra security groups

Each file in `sg/` is one extra security group, **self-contained** in the
template format — there is no defaults layer in `config.yaml`. Rules are maps
keyed by rule name under `ingress_rules` / `egress_rules`; a rule's
sources are `cidrs` and/or `referenced_security_group_ids`, and omitting
`from_port`/`to_port`/`ip_protocol` means all traffic (CIDRs are
written literally - each environment has its own files), and
`attach_to_cluster: true` adds the group to the control plane ENIs.
Groups are named `<cluster>-<name>`.
Per-group `tags` are merged over the stack tags. `cidrs_ipv6` is not
wired (the VPC is IPv4-only). `.example` files are inactive documentation — copy, drop
the suffix, adjust. With no active files, no extra groups are created
(EKS still creates its own cluster security group).

## Node security group rules

`eks.shared_node_ingress_rules` in `config.yaml` adds ingress to the
**EKS-managed cluster security group** — the SG every managed node
actually uses — for traffic that must reach the nodes directly (peered
ranges, an internal appliance, another cluster). Keyed by rule name;
sources are `cidrs` and/or `referenced_security_group_ids`. `ip_protocol: -1` means all traffic and
must omit the ports. An empty map (the default) leaves only EKS's own
rules. Its sibling `eks.cluster_ingress_rules` (same rule format) becomes
a dedicated extra security group attached to the **control plane ENIs**
instead.

## Node roles from other stacks (EC2_LINUX access entries)

Node pools whose IAM role is created elsewhere (e.g. the Karpenter node
role) join the cluster via `eks.additional_node_pools_iam_roles` in
`config.yaml` — a plain list of role names, each becoming an `EC2_LINUX`
access entry (the template shorthand) — or via a full entry in
`iam.yaml`. Either way the exact IAM role name is resolved to an ARN at
plan time, and no `policy` is set — EKS grants node permissions itself.
Managed node groups from THIS stack still get their entries
auto-created; never list those.

## Node groups

Each file in `ng/` is one managed node group, **self-contained** in the
template format — there is no `node_group_defaults` layer in `config.yaml`;
every key deploys from the file itself. The keys:

- `instance_type_list` — instance types (more than one helps spot pools)
- `use_on_demand_instance` — `true` = ON_DEMAND, `false` = SPOT
- `use_al2023_ami` — must be `true` (AL2 is end-of-support; `false` fails
  the plan). The AMI architecture follows `instance_type_list`: Graviton
  families (`t4g`, `m7g`, `c7gn`, …) get the ARM AMI, anything else x86;
  one architecture per group
- `min_size` / `desired_size` / `max_size` / `disk_size` — scaling + disk
- `k8s_labels` — node labels
- `k8s_taints` — map of `<key>: <value>:<Effect>` with the Kubernetes
  effect spelling (e.g. `dedicated: elk:NoSchedule`); translated to the
  EKS API values in `main.tf`
- `subnet_ids` — the subnets the group launches in (network stack
  output ids, pasted in after that stack is applied)
- `public_instance` — template key, informational only; `subnet_ids`
  decides public vs private
- `tags` — extra per-group tags (org tags come from `default_tags`)

Every group launches through a module-made launch template: IMDSv2
(hop limit 1), gp3 root disk, the cluster SG, and the `node_max_pods`
user data. A template change rolls the group's nodes.

`name:` in each file is the filename minus the env prefix; the stack
prepends `<env>-`, so `ng/dev-ng-system-od-us-east-1.yaml` with
`name: ng-system-od-us-east-1` becomes `dev-ng-system-od-us-east-1` - the
EKS node group is named exactly like its file.

| Group | Profile | Purpose |
| --- | --- | --- |
| `ng-system-od-us-east-1` | t3.medium, on-demand, 1/2/3 | kube-system / cluster-critical / bootstrap floor |

Instance types and sizes are dev-sized judgment calls — adjust freely in
the group files.

## One group on purpose — workload capacity comes from Karpenter

The system group is the **bootstrap floor**: Flux's controllers, the
Karpenter controller and CoreDNS run here, because they must exist on
nodes Karpenter does not manage. All other node capacity is Karpenter
NodePools, delivered by Flux from `gitops-flux` — the placement contract
is `ops-program` `docs/node-placement.md` (ADR 0013). The former workload
groups (base-spot, elk, monitoring, istio) were removed with that split;
their files remain in git history if Terraform-managed groups are ever
needed again.

## Adding a group

Copy an existing file in `ng/`, set a unique `name:`, and state the full
profile — files are self-contained, nothing is inherited. No `.tf`
changes needed — the stack discovers files via `fileset()`.

## Keys (`config.yaml`)

| Key | Meaning |
|---|---|
| `cluster_name` | immutable - changing it destroys and recreates the cluster |
| `cluster_version` | Kubernetes version; `null` = AWS picks the current one |
| `vpc_id`, `cluster_subnet_ids` | network stack outputs; the control-plane ENIs live in these subnets (private - they carry no public IP and need no internet route); both AZs must be covered |
| `ssh_key_name` | EC2 key pair for SSH to the nodes - the bastion stack's `key_pair_name`, which is that stack's `name` (`<env>-bastion-<region>`); `null` = no SSH |
| `node_jump_server_ssh` | the bastion's private IP as a `/32` (bastion output `private_ips`) - the only address allowed on :22. Required with `ssh_key_name`. The /32 is an SG rule, changeable anytime; changing `ssh_key_name` makes a new launch-template version and **rolls the nodes** |
| `node_max_pods` | kubelet pod ceiling on every node group (set via launch-template user data, fixed at boot). ENI default is 17 on small nodes; 110 = EKS recommendation. Requires CNI prefix delegation (Flux side) first; `null` = ENI default |
| `kms_key_id` | KMS key ARN for a customer-managed Secrets envelope key; `null` = the EKS default (AWS-managed) |
| `tags` | extra tags on everything in this stack (Org/Env/Component/Repo come from `default_tags`) |
| `eks.create_oidc` | create the IAM OIDC provider - required for IRSA |
| `eks.service_ipv4_cidr` | Kubernetes service CIDR; must not overlap the VPC |
| `eks.public_access_cidrs` | who may reach the public API endpoint while `endpoint_public_access` is `true`; kept at the VPC CIDR so re-enabling the public endpoint exposes nothing by accident |
| `eks.endpoint_public_access` / `endpoint_private_access` | API endpoint exposure: public off, private on - kubelets, the bastion and in-VPC tooling reach the API without an internet path ("Access model"). Free, changeable in place |
| `eks.enabled_log_types` | control-plane logs to CloudWatch |
| `eks.authentication_mode` | `API` = access entries only (the aws-auth ConfigMap is deprecated) |
| `eks.bootstrap_cluster_creator_admin_permissions` | the identity that creates the cluster (CI apply role) keeps admin |
| `eks.cluster_ingress_rules` | extra ingress to the control-plane ENIs; becomes one extra security group (`<cluster>-cluster-ingress`). Holds the :443-from-bastion rule (bastion output `security_group_id`). Rule format as in `sg/` |
| `eks.shared_node_ingress_rules` | extra ingress on the EKS-managed cluster SG (the SG every node uses): peered ranges, appliances, another cluster. `ip_protocol: -1` = all traffic, omit the ports |
| `eks.additional_node_pools_iam_roles` | role names of node pools created elsewhere (Karpenter); each becomes an `EC2_LINUX` access entry. Never list this stack's own node groups |

## Identity (`iam.yaml`)

| Section | Keyed by | Notes |
|---|---|---|
| `access_entries` | principal: a full ARN (used verbatim) or a short name resolved via `role_name` (exact) / `role_name_pattern` (regex, for SSO roles whose names carry a random suffix) | `access_entry_type` `STANDARD` or `EC2_LINUX`; grant with `policy_arn` (an EKS access policy, `scope`/`namespaces` optional) and/or `kubernetes_groups` (cluster RBAC). EKS auto-creates entries for this stack's node groups - never list those; node pools from other stacks go in `eks.additional_node_pools_iam_roles`. The pattern lookup needs `iam:ListRoles` - plan via CI or as PlatformAdmin |
| `service_accounts` | the **full** IRSA role name `<env>-irsa-<workload>-<region>`, used verbatim | `namespace_service_account: <ns>/<sa>` - the role is assumable only by that service account; `attached_policies` (ARNs: AWS-managed verbatim, customer-managed from the iam-roles stack `policy_arns` output); `description` optional. Put the role ARN (output `irsa_role_arns`) in the SA's `eks.amazonaws.com/role-arn` annotation. Merge the role before the Flux release that uses it |
| `iam_role_tags` | - | extra tags on every IRSA role |

Karpenter is not just an IRSA role (discovery tags, node role/instance
profile, SQS interruption queue) - it lands as its own change; the
`karpenter.sh/discovery` tags stay absent until then because another
cluster's Karpenter runs in this account.
