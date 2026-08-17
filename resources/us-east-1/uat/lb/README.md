# lb - Terraform-owned ALB + TargetGroupBinding

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
         -> listener rule (path/host, from tg/*.yaml)
         -> target group (ip mode)
         -> pod ENI (private subnets, EKS cluster SG)
```

`ip` targets on purpose: the ALB reaches pods directly on their VPC CNI
addresses - no NodePort hop, no second SG to manage. The module opens the
cluster SG to the ALB SG per target port; nothing else gets through.

## Adding a service

1. Copy `tg/example-tg.yaml.example` to `tg/<service>.yaml`, set port and
   routing, open a PR against this stack. Merge + apply creates the
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
  IRSA role - see the commented `aws-lb-controller` block in
  `../eks/iam.yaml`. Because Terraform creates the LB resources, the role
  is register/deregister + describe, a fraction of the upstream policy.
- The `network` and `eks` stacks applied (remote state).

## What this stack is NOT for

L4/NLB (static IPs, PrivateLink), multi-cluster routing, API Gateway /
Global Accelerator edges - out of scope for v1. The TargetGroupBinding
split is the piece that makes the multi-cluster path cheap later.
