# network - VPC

## Design

Two public /20 subnets (EKS nodes and their pods, load balancers,
bastion) and two private /24 subnets (control-plane ENIs only) across
two AZs. The public subnets are /20s because the CNI's prefix delegation
needs whole free /28s - /24s fragment (gitops-flux#142). **No NAT
gateway**: the private subnets have no internet egress at all
(~$33/month + per-GiB saved per NAT); anything that must reach the
internet lives in the public subnets with its own public IP. The
free S3 **gateway** endpoint keeps S3 - including ECR image layers -
reachable from every subnet. To restore private egress, uncomment the
`nat_gateway:` lines in `config.yaml` (one shared NAT = same host subnet
on every table; per-AZ NATs = a different host per table).

CIDRs compose as `<cidr_prefix>.<cidr_suffix>`: the VPC is
`<cidr_prefix>.0.0/16` and every subnet hangs off the same prefix, so an
environment re-prefixes wholesale.

**Discovery tags** are set in `config.yaml`: `kubernetes.io/role/elb` on
public subnets, `kubernetes.io/role/internal-elb` on private, and
`karpenter.sh/discovery: <cluster name>` on public only — nodes live in
public subnets (no NAT), so Karpenter must not place them in private ones.

## Keys

| Key | Meaning |
|---|---|
| `name` | `<org>-<env>-vpc`; prefixes every network resource name |
| `cidr_prefix` / `cidr_suffix` | VPC CIDR = prefix.suffix (prefix quoted - YAML would read `10.0` as a number) |
| `instance_tenancy`, `enable_dns_*`, `enable_network_address_usage_metrics` | VPC attributes, AWS defaults |
| `map_public_ip_on_launch` | public subnets assign public IPs to instances (bastion, public node groups) |
| `public_subnet_tags` / `private_subnet_tags` | extra tags on the subnets (see discovery-tag note above) |
| `subnets.<name>` | `availability_zone` + `cidr_suffix`; referenced by name from `route_tables` |
| `route_tables.<name>` | `enable_igw: true` = attached subnets are public; `nat_gateway: <public subnet>` = private egress via a NAT there; `enable_endpoint_route` = S3 gateway endpoint on this table (wired all-or-nothing across tables); `attach_to_subnets` - exactly one table per subnet |
| `enable_peering_route`, `vpc_endpoint`, `custom_route`, `attach_to_igw` | template keys, **not wired** (no peering, firewall GWLBE or edge routing in this design) |
| `peering_*`, `transit_gateway_attachment`, `vpn_gateway` | template sections, **not wired** - placeholders for future connectivity |

## Outputs used by other stacks

`vpc_id`, `public_subnet_ids`, `private_subnet_ids` - pasted into the
eks, bastion, alb and nlb stacks' `config.yaml` (see the repo README
"Apply order and id hand-off").
