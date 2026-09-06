# Getting into the dev cluster

```
 your laptop ──(AWS Session Manager)──▶ bastion ──ssh──▶ nodes
      │                                    └── tunnel ──▶ cluster API (kubectl)
```

**You only ever type on your laptop.** The bastion and the nodes are places
you arrive at, not places you work from - they hold no cluster identity and
no tools. Your AWS login is the identity for everything below.

The bastion is found by its Name tag and nodes by asking the cluster, so
replaced instances need no doc change. The API host is fixed for the
cluster's life.

## 1. Set up your laptop, once

1. **AWS credentials** for the account: `aws sso login`, or temporary
   credentials pasted from the SSO portal. Check with `aws sts get-caller-identity`.
   Set `AWS_DEFAULT_REGION=us-east-1` (or `region` in your profile).
2. **The Session Manager plugin**: `brew install --cask session-manager-plugin`.
3. **The team SSH key**, fetched with your own credentials:
   ```bash
   aws ssm get-parameter --region us-east-1 --name /dev/bastion/ssh-private-key \
     --with-decryption --query Parameter.Value --output text > ~/.ssh/dev-bastion-us-east-1
   chmod 600 ~/.ssh/dev-bastion-us-east-1
   ```
4. **SSH config**: append these blocks to the file `~/.ssh/config` (create it
   if it does not exist). `dev-bastion` resolves the instance by its Name
   tag every time, so a rebuilt bastion needs no change here.
   ```
   Host dev-bastion
     User ec2-user
     IdentityFile ~/.ssh/dev-bastion-us-east-1
     ProxyCommand sh -c "aws ssm start-session --region us-east-1 --document-name AWS-StartSSHSession --parameters 'portNumber=%p' --target $(aws ec2 describe-instances --region us-east-1 --filters Name=tag:Name,Values=dev-bastion-us-east-1 Name=instance-state-name,Values=running --query 'Reservations[0].Instances[0].InstanceId' --output text)"

   Host 10.1.*
     User ec2-user
     IdentityFile ~/.ssh/dev-bastion-us-east-1
   ```
5. **kubectl context** named after the cluster, pointed at a local tunnel port. This adds
   to your existing `~/.kube/config`; other clusters' contexts stay as they
   are. (`--alias` names the context you switch to; the cluster entry keeps
   its ARN name, which is why the second command uses the ARN.)
   ```bash
   aws eks update-kubeconfig --name dev-eks-us-east-1 --region us-east-1 --alias dev-eks-us-east-1
   kubectl config set-cluster arn:aws:eks:us-east-1:808540602855:cluster/dev-eks-us-east-1 \
     --server=https://localhost:8443 --tls-server-name=CA6B52FC8EE02FF57009E02F583036A5.gr7.us-east-1.eks.amazonaws.com
   ```
   You never repeat this when credentials expire: kubectl asks `aws` for a
   fresh token on every call, so renewing your AWS login (step 1) is enough -
   in the same shell, if you use pasted temporary credentials.
   The API host above is fixed for the life of the cluster
   (`aws eks describe-cluster --name dev-eks-us-east-1 --region us-east-1 --query cluster.endpoint`).

## 2. The three things you do - all from your laptop

**kubectl** - open the tunnel (it stays in the background), then work:
```bash
ssh -fN -L 8443:CA6B52FC8EE02FF57009E02F583036A5.gr7.us-east-1.eks.amazonaws.com:443 dev-bastion
kubectl get nodes -o wide
```
While the tunnel is open, `localhost:8443` is the cluster API. Close it with
`pkill -f 8443:CA6B52FC`.

**A shell on a node** (kubelet, disk, network debugging) - the IP comes from
`kubectl get nodes -o wide` (INTERNAL-IP), or without kubectl:
`aws ec2 describe-instances --region us-east-1 --filters Name=tag:eks:cluster-name,Values=dev-eks-us-east-1 --query 'Reservations[].Instances[].PrivateIpAddress' --output text`
```bash
ssh -J dev-bastion ec2-user@<node-private-ip>
```
`exit` brings you back to the laptop.

**A shell on the bastion** (curl a private address; rarely needed):
```bash
ssh dev-bastion
```

## 3. Troubleshooting

Wrong machine first, then setup steps in order, then daily use.

| Symptom | Cause | Fix |
|---|---|---|
| `kubectl: command not found` or `update-kubeconfig` errors on the bastion or a node | you are on the wrong machine: kubectl and kubeconfig belong on your laptop only; the bastion and nodes never run them and have no cluster identity | `rm -rf ~/.kube` on that machine, `exit` back to the laptop and run it there |
| `You must specify a region` / `Unable to locate credentials` | no default region, or the login has expired | setup step 1 |
| `SessionManagerPlugin is not found` | the plugin is not installed | setup step 2 |
| `Permission denied (publickey)` on a node | the `Host 10.1.*` block is missing | setup step 4 |
| `bind [127.0.0.1]:8443: Address already in use` | a tunnel from earlier is still open | keep using it, or `pkill -f 8443:CA6B52FC` and reopen |
| kubectl hangs or reports "connection refused" | the tunnel is not open, or the current context is not `dev-eks-us-east-1` | re-run the `ssh -fN` line; `kubectl config use-context dev-eks-us-east-1` |

**Several clusters**: kubectl keeps one context per cluster.
`kubectl config get-contexts` lists them, `kubectl config use-context dev-eks-us-east-1`
selects this one (needs the tunnel); clusters with a public endpoint need no tunnel.

**If Session Manager is down**: `ssh_ingress_cidrs` in the bastion
`config.yaml` reopens :22 to a CIDR through a normal PR and apply.
