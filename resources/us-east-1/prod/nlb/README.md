# nlb - Terraform-owned NLB + TargetGroupBinding

One internet-facing NLB in front of the cluster for L4 traffic (TCP, UDP,
TLS passthrough or termination), with the same ownership split as the
`alb` stack:

- **Terraform owns the load balancer**: NLB, listeners, target groups and
  security-group wiring all live in this stack, next to every other piece
  of infra. Certificates and static IPs attach here, in IaC, reviewed
  like everything else.
- **The cluster only fills the target groups**: the AWS Load Balancer
  Controller (a Flux-managed addon) watches `TargetGroupBinding` objects
  and registers/deregisters pod IPs as they come and go. It never creates
  or deletes AWS resources.

Why not the controller's default mode, where a `Service` of type
`LoadBalancer` conjures the NLB? Same reason as the ALB: the LB's
lifecycle would be coupled to a Kubernetes object - delete the Service
(or lose the cluster) and the NLB, its DNS name and its static IPs go
with it, and its config lives in annotations outside this repo's
config.yaml convention. With this split the NLB survives cluster rebuilds,
and a second cluster can bind into the same target groups later
(blue-green) with zero LB changes.

## When to use this instead of the ALB

| Need | Stack |
|---|---|
| HTTP routing by path/host, WAF, HTTP redirects | `alb` |
| Non-HTTP protocols (TCP/UDP), TLS passthrough (mTLS to the pod) | `nlb` |
| A service mesh ingress gateway that terminates TLS itself (Istio) | `nlb` |
| Static IPs / PrivateLink endpoint service | `nlb` |

## Traffic path

```
internet -> NLB (public subnets, own SG)
         -> listener (one port per target_groups entry - no rules on an NLB)
         -> target group (ip mode, TCP/UDP)
         -> pod ENI (private subnets, EKS cluster SG)
```

`ip` targets on purpose: the NLB reaches pods directly on their VPC CNI
addresses - no NodePort hop, no second SG to manage. The NLB carries a
security group, so the cluster SG is opened to the **NLB SG** per target
port (not to client CIDRs), which keeps working with client IP
preservation on: SG evaluation happens at the NLB, pods still see the
real source address.

`cross_zone_load_balancing` is on: NLBs default it off, and with one
replica per AZ an AZ that loses its pod would otherwise black-hole its
share of traffic.

## Adding a service

1. Add an entry to `target_groups` in `config.yaml` (the commented example
   there is the template), set the target port, the listener port and the
   health check, open a PR against this stack. Merge + apply creates the (empty) target group and its
   listener; read the ARN from the `target_group_arns` output.
2. Ship a `TargetGroupBinding` with the app's Flux release:

   ```yaml
   apiVersion: elbv2.k8s.aws/v1beta1
   kind: TargetGroupBinding
   metadata:
     name: istio-ingress
     namespace: istio-ingress
   spec:
     targetGroupARN: <target_group_arns["istio-ingress"] output>
     serviceRef:
       name: istio-ingressgateway # a plain ClusterIP Service
       port: 443
     # no spec.networking on purpose: SG rules are Terraform's job here
   ```

Order matters: target group first (this stack), binding second - same
merge-before-release rule as IRSA roles in the eks stack.

One listener port maps to exactly one target group. A service that needs
several ports (e.g. 80 and 443 on an ingress gateway) gets one
`target_groups` entry per port.

## TLS

- `listener.protocol: TCP` (default) passes TLS through untouched - the
  pod terminates it. This is the normal mode for an Istio gateway or
  anything doing mTLS.
- `listener.protocol: TLS` terminates at the NLB with the certificate
  `certificate_arn` from `config.yaml` and forwards plain TCP to the pod.
  A TLS listener without a `certificate_arn` fails the
  plan.

## Prerequisites

- The AWS Load Balancer Controller addon (Flux) with the **binding-only**
  IRSA role - see the commented `aws-lb-controller` block in
  `../eks/iam.yaml`. Because Terraform creates the LB resources, the role
  is register/deregister + describe, a fraction of the upstream policy.
- The `network` and `eks` stacks applied, and their output ids
  (`vpc_id`, subnet ids, `cluster_security_group_id`) pasted into
  `config.yaml` - this stack reads no remote state.

## What this stack is NOT for

HTTP-level routing (paths, hosts, redirects, WAF) - that is the `alb`
stack. Elastic IP allocation and PrivateLink endpoint services are not
wired yet; the security-group-on-NLB design is what keeps both cheap to
add later.

## Keys (`config.yaml`)

| Key | Meaning |
|---|---|
| `name` | the full NLB name, `<env>-nlb-<region>` (`prod-nlb-us-east-1`); also the NLB SG name and the target group prefix (32-char limit overall) |
| `vpc_id`, `subnet_ids` | network stack outputs. Public subnets for an internet-facing NLB, private for an internal one - must agree with `internal`. One per AZ, at least two |
| `backend_security_group_id` | the eks stack's `cluster_security_group_id` - pod ENIs carry it under the VPC CNI; the module opens it to the NLB SG per target port |
| `internal` | `true` = no public IPs (scheme internal) |
| `ingress_cidrs` | who may reach the listener ports |
| `ip_address_type` | `ipv4` or `dualstack` |
| `cross_zone_load_balancing` | spread traffic across all AZs' targets; NLBs default it off, and with one replica per AZ an AZ losing its pod would otherwise black-hole its share |
| `deletion_protection` | the NLB's DNS name is an external contract - `true` in prod; destroy = flip, apply, then destroy |
| `certificate_arn` | ACM certificate for `listener.protocol: TLS` entries (NLB terminates TLS, forwards TCP). `null` = TLS passes through to the pod |
| `ssl_policy` | AWS predefined TLS policy name for TLS listeners |
| `target_group_defaults` | applied to every `target_groups` entry; shallow merge - an entry that sets `health_check` replaces the whole map. `listener` has no defaults |
| `protocol` | `TCP`, `UDP` or `TCP_UDP` on the target group |
| `preserve_client_ip` | pods see the real client source IP (always on for UDP, never for TLS listeners). Hairpin caveat: an in-VPC client landing on a pod on its own node cannot connect |
| `proxy_protocol_v2` | send PROXY v2 headers - only if the pod-side proxy parses them |
| `deregistration_delay` | connection-draining seconds when a target leaves; pair with the pod's `terminationGracePeriodSeconds` |
| `health_check.*` | `TCP` probes the port only; `HTTP`/`HTTPS` also check `path` + `matcher`; `timeout` < `interval` |
| `target_groups[].listener` | one listener per entry (`port`, `protocol`; `alpn_policy` for TLS). Listener ports must be unique - an NLB listener forwards to exactly one target group |
