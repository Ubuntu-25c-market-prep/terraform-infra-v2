# alb - Terraform-owned ALB + TargetGroupBinding

One internet-facing ALB in front of the cluster, with a deliberate split
of ownership:

- **Terraform owns the load balancer**: ALB, listeners, listener rules,
  target groups and security-group wiring all live in this stack, next to
  every other piece of infra. WAF, access logs and certificates attach
  here, in IaC, reviewed like everything else.
- **The cluster only fills the target groups**: the AWS Load Balancer
  Controller (a Flux-managed addon) watches `TargetGroupBinding` objects
  and registers/deregisters pod IPs as they come and go. It never creates
  or deletes AWS resources.

Why not the controller's default mode, where a Kubernetes `Ingress`
conjures the ALB? Because then the LB's lifecycle is coupled to a
Kubernetes object: delete the Ingress (or lose the cluster) and the ALB -
and the DNS name everything points at - goes with it, and its config
lives in annotations outside this repo's config.yaml convention. With
this split the ALB survives cluster rebuilds, and a second cluster can
bind into the same target groups later (blue-green) with zero LB changes.

## Traffic path

```
internet -> ALB (public subnets, own SG)
         -> listener rule (path/host, from target_groups in config.yaml)
         -> target group (ip mode)
         -> pod ENI (private subnets, EKS cluster SG)
```

`ip` targets on purpose: the ALB reaches pods directly on their VPC CNI
addresses - no NodePort hop, no second SG to manage. The module opens the
cluster SG to the ALB SG per target port; nothing else gets through.

## Adding a service

1. Add an entry to `target_groups` in `config.yaml` (the commented example
   there is the template), set port and routing, open a PR against this
   stack. Merge + apply creates the
   (empty) target group; read its ARN from the `target_group_arns` output.
2. Ship a `TargetGroupBinding` with the app's Flux release:

   ```yaml
   apiVersion: elbv2.k8s.aws/v1beta1
   kind: TargetGroupBinding
   metadata:
     name: demo-api
     namespace: demo
   spec:
     targetGroupARN: <target_group_arns["demo-api"] output>
     serviceRef:
       name: demo-api # a plain ClusterIP Service
       port: 8080
     # no spec.networking on purpose: SG rules are Terraform's job here
   ```

Order matters: target group first (this stack), binding second - same
merge-before-release rule as IRSA roles in the eks stack.

## Prerequisites

- The AWS Load Balancer Controller addon (Flux) with the **binding-only**
  IRSA role: the `prod-AWSLoadBalancerControllerBindingPolicy-us-east-1`
  policy is active in `../iam-roles/config.yaml`; paste its ARN (output
  `policy_arns`) into the `prod-irsa-aws-load-balancer-controller-us-east-1`
  entry in `../eks/iam.yaml` and uncomment it. Because Terraform creates
  the LB resources, the role is register/deregister + describe, a
  fraction of the upstream policy.
- The `network` and `eks` stacks applied, and their output ids
  (`vpc_id`, subnet ids, `cluster_security_group_id`) pasted into
  `config.yaml` - this stack reads no remote state.

## What this stack is NOT for

L4 traffic (TCP/UDP, TLS passthrough, static IPs, PrivateLink) - that is
the `nlb` stack. Multi-cluster routing and API Gateway / Global
Accelerator edges are out of scope for v1. The TargetGroupBinding
split is the piece that makes the multi-cluster path cheap later.

## Keys (`config.yaml`)

| Key | Meaning |
|---|---|
| `name` | the full ALB name, `<env>-alb-<region>` (`prod-alb-us-east-1`); also the ALB SG name and the target group prefix. Target group names are `<name>-<entry name>` and limited to 32 characters, so 14 remain for the entry name - it is a label, not the Service name |
| `vpc_id`, `subnet_ids` | network stack outputs. Public subnets for an internet-facing ALB, private for an internal one - must agree with `internal`. One per AZ, at least two |
| `backend_security_group_id` | the eks stack's `cluster_security_group_id` - pod ENIs carry it under the VPC CNI; the module opens it to the ALB per target port |
| `internal` | `true` = no public IPs (scheme internal) |
| `ingress_cidrs` | who may reach the listeners (:80, :443); narrow for internal/admin ALBs |
| `ip_address_type` | `ipv4` or `dualstack` |
| `idle_timeout` | seconds a connection may sit idle before the ALB closes it; raise for slow endpoints or quiet WebSockets. Keep the pods' keep-alive timeout longer than this to avoid sporadic 502s |
| `drop_invalid_header_fields` | strip HTTP headers with invalid names before forwarding - closes request-smuggling gaps; keep `true` |
| `deletion_protection` | the ALB's DNS name is an external contract - a delete severs every record pointing at it. `true` in prod; destroy = flip, apply, then destroy |
| `certificate_arn` | ACM certificate for the HTTPS `:443` listener (`:80` then redirects); `null` = plain HTTP only |
| `ssl_policy` | AWS predefined TLS policy name (`aws elbv2 describe-ssl-policies`); the default allows TLS 1.2 + 1.3 |
| `target_group_defaults` | applied to every `target_groups` entry; the merge is shallow - an entry that sets `health_check` replaces the whole map |
| `target_groups[].name`, `port` | required; `port` is the containerPort (ip targets - no NodePort hop) |
| `target_groups[].routing` | listener rule: `priority` (unique, lower wins) and at least one of `path_patterns` / `host_headers` |
| `protocol`, `deregistration_delay`, `health_check.*` | pod-side protocol; connection-draining seconds when a target leaves (pair with the pod's `terminationGracePeriodSeconds`); health check path/port/thresholds |
