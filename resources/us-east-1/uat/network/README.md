# network - VPC

## Design

Two public /20 subnets (EKS nodes and their pods, load balancers,
bastion) and two private /24 subnets (control-plane ENIs only) across
two AZs. One public and one private route table: without a NAT gateway
a private table holds only the S3 endpoint route, so one table serves
both private subnets. The public subnets are /20s because the CNI's prefix delegation
needs whole free /28s - /24s fragment (gitops-flux#142). **No NAT
gateway**: the private subnets have no internet egress at all
(~$33/month + per-GiB saved per NAT); anything that must reach the
internet lives in the public subnets with its own public IP. The
free S3 and DynamoDB **gateway** endpoints keep both services - S3
including ECR image layers - reachable from every subnet; they are the
only free endpoint type (every other service, MongoDB Atlas included, is
a billed interface endpoint). NAT is not implemented in the vpc module; private egress would be a
module change (the previous implementation is in git history).

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
| `name` | `<env>-vpc-<region>` (e.g. `uat-vpc-us-east-1`); prefixes every network resource name (subnets, IGW, S3 endpoint) |
| `cidr_prefix` / `cidr_suffix` | VPC CIDR = prefix.suffix (prefix quoted - YAML would read `10.0` as a number) |
| `instance_tenancy`, `enable_dns_*`, `enable_network_address_usage_metrics` | VPC attributes, AWS defaults |
| `map_public_ip_on_launch` | public subnets assign public IPs to instances (bastion, public node groups) |
| `gateway_endpoints` | free gateway endpoints to create: `s3`, `dynamodb` (wired to every table with `enable_endpoint_route: true`) |
| `public_subnet_tags` / `private_subnet_tags` | extra tags on the subnets (see discovery-tag note above) |
| `subnets.<name>` | `availability_zone` + `cidr_suffix`; referenced by name from `route_tables` |
| `route_tables.<name>` | `enable_igw: true` = attached subnets are public; `enable_endpoint_route` = gateway endpoints on this table (wired all-or-nothing across tables); `attach_to_subnets` - exactly one table per subnet; several subnets may share one table (the private subnets do: with no NAT, per-AZ tables would be identical) |
| `nat_gateway`, `enable_peering_route`, `vpc_endpoint`, `custom_route`, `attach_to_igw` | template keys, **not wired** (no peering, firewall GWLBE or edge routing in this design) |
| `peering_*`, `transit_gateway_attachment`, `vpn_gateway` | template sections, **not wired** - placeholders for future connectivity |

## Outputs used by other stacks

`vpc_id`, `public_subnet_ids`, `private_subnet_ids` - pasted into the
eks, bastion, alb and nlb stacks' `config.yaml` (see the repo README
"Apply order and id hand-off").
