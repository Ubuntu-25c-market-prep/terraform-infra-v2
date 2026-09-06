# bastion - the way into the VPC

A small instance in a public subnet with no open port. You reach it through
AWS Session Manager with your own AWS login, and from it you reach the
nodes and the cluster API. Every session is logged under your name.

How to use it - laptop setup, node shells, the kubectl tunnel, common
mistakes: [`docs/access.md`](../../../../docs/access.md).

## Keys (`config.yaml`)

| Key | Meaning |
|---|---|
| `name` | `<env>-bastion-<region>` (`prod-bastion-us-east-1`): security group, key pair and instance role name; each instance states its own full name |
| `vpc_id` | network stack output |
| `enable_ssm` | instance profile with `AmazonSSMManagedInstanceCore` (`<name>-role`) |
| `create_security_group` | create the bastion SG (inbound per `ssh_ingress_cidrs`, outbound per `egress_rules`) |
| `ssh_public_key` | the team's **public** key; Terraform creates the key pair named `name` from it. The private half lives in SSM Parameter Store `/prod/bastion/ssh-private-key` |
| `key_name` | use an existing EC2 key pair instead (set `ssh_public_key: null`) |
| `ssh_ingress_cidrs` | `[]` = no inbound rule; SSH arrives over SSM. A CIDR here reopens :22 as a deliberate fallback |
| `egress_rules` | SSH inside the VPC (node hops) and HTTPS out (SSM, dnf) |
| `instances[].subnet_id` | network stack output - **must be a public subnet** |
| `instances[].instance_type`, `root_volume_size` | sizing |

## Outputs used by other stacks

- `key_pair_name` -> `eks/config.yaml` `ssh_key_name`
- `private_ips` -> `eks/config.yaml` `node_jump_server_ssh` (as a `/32`)
- `security_group_id` -> `eks/config.yaml` `cluster_ingress_rules` (API :443 from the bastion)
- `instance_ids` - the `--target` for Session Manager
