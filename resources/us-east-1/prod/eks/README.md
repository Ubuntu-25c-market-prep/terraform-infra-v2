# EKS stack (cluster + node groups + security groups + identity)

One stack owns the cluster, its managed node groups, any extra security
groups, and cluster identity: `iam.yaml` (org format) holds
`access_entries` — who may call the Kubernetes API, keyed by principal;
an `arn:` key is used verbatim, any other key is a name resolved at plan
time from `role_name`/`role_name_pattern` (SSO) — plus `service_accounts`
(the IRSA roles workloads assume, keyed by role name with
`namespace_service_account: <ns>/<sa>` and `attached_policies` and/or
inline `policy`) and `iam_role_tags` (extra tags on the IRSA roles).
`config.yaml` keeps only infrastructure settings, in the org eks
template shape: flat cluster/infra keys
(`cluster_name`, `cluster_version`, `kms_key_id`, ...) up top and the
cluster behaviour under `eks:`. Unset `vpc_id`/`cluster_subnet_ids`
resolve from the network stack's remote state (ids never live in this
public repo); `kms_key_id` holds an ALIAS by org rule for the same
reason. `ssh_key_name`/`node_jump_server_ssh` are commented and not
wired - managed node groups carry no SSH remote access. IRSA roles get the cluster's OIDC provider wired directly, no
remote state. Non-cluster IAM stays in the separate `iam/` stack. Addons (vpc-cni, kube-proxy, coredns, ...) are **not**
managed here — Flux CD owns them after the cluster is up. EKS still
installs its default self-managed versions at creation, so nodes join
before Flux runs.

## Extra security groups

Each file in `sg/` is one extra security group, **self-contained** in the
org format — there is no defaults layer in `config.yaml`. Rules are maps
keyed by rule name under `ingress_rules` / `egress_rules`; a rule's
sources are `cidrs` and/or `referenced_security_group_ids`, and omitting
`from_port`/`to_port`/`ip_protocol` means all traffic. `"@vpc"` in
`cidrs` resolves to this environment's VPC CIDR at plan time, and
`attach_to_cluster: true` adds the group to the control plane ENIs.
`cidrs_ipv6` and per-group `tags` are not wired (the module carries
neither yet). `.example` files are inactive documentation — copy, drop
the suffix, adjust. With no active files, no extra groups are created
(EKS still creates its own cluster security group).

## Node security group rules

`eks.shared_node_ingress_rules` in `config.yaml` adds ingress to the
**EKS-managed cluster security group** — the SG every managed node
actually uses — for traffic that must reach the nodes directly (peered
ranges, an internal appliance, another cluster). Keyed by rule name;
sources are `cidrs` (`"@vpc"` resolves as above) and/or
`referenced_security_group_ids`. `ip_protocol: -1` means all traffic and
must omit the ports. An empty map (the default) leaves only EKS's own
rules. Its sibling `eks.cluster_ingress_rules` (same rule format) becomes
a dedicated extra security group attached to the **control plane ENIs**
instead.

## Node roles from other stacks (EC2_LINUX access entries)

Node pools whose IAM role is created elsewhere (e.g. the Karpenter node
role) join the cluster via `eks.additional_node_pools_iam_roles` in
`config.yaml` — a plain list of role names, each becoming an `EC2_LINUX`
access entry (the org-template shorthand) — or via a full entry in
`iam.yaml`. Either way the exact IAM role name is resolved to an ARN at
plan time, and no `policy` is set — EKS grants node permissions itself.
Managed node groups from THIS stack still get their entries
auto-created; never list those.

## Node groups

Each file in `ng/` is one managed node group, **self-contained** in the
org format — there is no `node_group_defaults` layer in `config.yaml`;
every key deploys from the file itself. The keys:

- `instance_type_list` — instance types (more than one helps spot pools)
- `use_on_demand_instance` — `true` = ON_DEMAND, `false` = SPOT
- `use_al2023_ami` — `true` = AL2023 (the only value we deploy)
- `min_size` / `desired_size` / `max_size` / `disk_size` — scaling + disk
- `k8s_labels` — node labels
- `k8s_taints` — map of `<key>: <value>:<Effect>` with the Kubernetes
  effect spelling (e.g. `dedicated: elk:NoSchedule`); translated to the
  EKS API values in `main.tf`
- `public_instance` — `false` = this environment's private subnets,
  `true` = public; resolved from the network stack at plan time
- `subnet_ids` — explicit subnet ids override `public_instance`; kept
  commented (ids never live in this public repo)
- `tags` — extra per-group tags (org tags come from `default_tags`)

`name:` in each file is the filename minus the env prefix; the module
prepends `<org>-<env>-`, so `ng/prod-ng-system-od-us-east-1.yaml` with
`name: ng-system-od-us-east-1` becomes `u25c-prod-ng-system-od-us-east-1`.

| Group | Profile | Purpose |
| --- | --- | --- |
| `ng-system-od-us-east-1` | m5.large, on-demand, 2/3/5 | kube-system / cluster-critical |
| `ng-base-spot-us-east-1` | SPOT, 3 instance types, 0/1/4 | general stateless workloads |
| `ng-elk-od-us-east-1` | m5.large, taint `dedicated=elk` | Elasticsearch / Logstash / Kibana |
| `ng-monitoring-od-us-east-1` | m5.large, taint `dedicated=monitoring` | Prometheus / Grafana |
| `ng-istio-od-us-east-1` | m5.large, label only | istiod + ingress gateways |

Instance types and sizes are prod-sized judgment calls — adjust freely in
the group files.

## Tainted pools need matching tolerations in Flux

The `elk` and `monitoring` pools carry `NO_SCHEDULE` taints so other
workloads stay off them. **The Flux-managed releases that should run there
must set both** — or their pods schedule elsewhere (or nowhere):

```yaml
# in the HelmRelease values (e.g. kube-prometheus-stack)
nodeSelector:
  workload: monitoring
tolerations:
  - key: dedicated
    value: monitoring
    effect: NoSchedule
```

Same pattern for ELK with `workload: elk` / `value: elk`. The istio pool has
a `workload: istio` label but no taint — a `nodeSelector` is enough to pin
the mesh there; add a taint (like the elk pool) if it should have the nodes
to itself.

## Adding a group

Copy an existing file in `ng/`, set a unique `name:`, and state the full
profile — files are self-contained, nothing is inherited. No `.tf`
changes needed — the stack discovers files via `fileset()`.
