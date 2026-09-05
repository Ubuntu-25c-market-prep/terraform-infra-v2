# bastion - SSH jump host

One small instance in a **public** subnet, the SSH way into the VPC:

```
ssh -J ec2-user@<bastion-public-ip> ec2-user@<private-ip>
```

It must be public: with no NAT gateway, a private instance would have
no route out (package updates) and no way in. Access is key-based SSH;
the instance runs AL2023 with the team's public key installed by
Terraform.

## Keys

| Key | Meaning |
|---|---|
| `name` | `<env>-bastion-<region>` (`prod-bastion-us-east-1`): the security group and key pair name; each instance states its own full name |
| `vpc_id` | network stack output |
| `create_security_group` | create the bastion SG (SSH in from `ssh_ingress_cidrs`, out per `egress_rules`) |
| `ssh_public_key` | the team's **public** key; Terraform creates the key pair named `name` from it. Only the private half is secret |
| `key_name` | use an existing EC2 key pair instead (set `ssh_public_key: null`) |
| `ssh_ingress_cidrs` | who may SSH in; keep generic, narrow at plan time in CI |
| `egress_rules` | deliberately narrow: SSH inside the VPC and HTTPS out for updates. DNS/NTP use link-local resolvers and need no rule |
| `instances[].subnet_id` | network stack output - **must be a public subnet** |
| `instances[].instance_type`, `root_volume_size` | sizing |

## Outputs used by other stacks

- `key_pair_name` → `eks/config.yaml` `ssh_key_name`
- `private_ips` → `eks/config.yaml` `node_jump_server_ssh` (as a `/32`)
- `public_ips` - the SSH target
