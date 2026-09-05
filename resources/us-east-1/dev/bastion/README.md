# bastion - jump host

One small AL2023 instance in a **public** subnet (no NAT, so a private
instance would have no route out), reached through **Session Manager**:
the instance dials out to SSM over HTTPS and nothing listens on the
internet. Access is your SSO session plus `ssm:StartSession`, logged in
CloudTrail per person; the SSH key pair is only used for the hop from
the bastion to the nodes.

```bash
# shell
aws ssm start-session --target <instance-id>

# SSH over SSM (once, in ~/.ssh/config)
Host i-* mi-*
  User ec2-user
  ProxyCommand sh -c "aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters 'portNumber=%p'"

# node via the bastion
ssh -J <bastion-instance-id> ec2-user@<node-private-ip>

# kubectl: forward the private API endpoint
ssh -L 8443:<cluster-endpoint-host>:443 <bastion-instance-id>
```

## Keys

| Key | Meaning |
|---|---|
| `name` | `<env>-bastion-<region>` (`dev-bastion-us-east-1`): security group, key pair and instance role name; each instance states its own full name |
| `vpc_id` | network stack output |
| `enable_ssm` | instance profile with `AmazonSSMManagedInstanceCore` (`<name>-role`) |
| `create_security_group` | create the bastion SG (inbound per `ssh_ingress_cidrs`, outbound per `egress_rules`) |
| `ssh_public_key` | the team's **public** key; Terraform creates the key pair named `name` from it. Only the private half is secret |
| `key_name` | use an existing EC2 key pair instead (set `ssh_public_key: null`) |
| `ssh_ingress_cidrs` | `[]` = no inbound rule at all; SSH arrives over SSM. Set CIDRs only as a deliberate fallback |
| `egress_rules` | SSH inside the VPC (node hops) and HTTPS out (SSM endpoints, dnf). DNS/NTP use link-local resolvers and need no rule |
| `instances[].subnet_id` | network stack output - **must be a public subnet** |
| `instances[].instance_type`, `root_volume_size` | sizing |

## Outputs used by other stacks

- `key_pair_name` → `eks/config.yaml` `ssh_key_name`
- `private_ips` → `eks/config.yaml` `node_jump_server_ssh` (as a `/32`)
- `security_group_id` → `eks/config.yaml` `cluster_ingress_rules` (API :443 from the bastion)
- `instance_ids` - the `--target` for Session Manager
