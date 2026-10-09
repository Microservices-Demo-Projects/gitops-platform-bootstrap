# Local ArgoCD Setup (Kubernetes)

Quick-test GitOps installation for a local Kubernetes cluster (Kind). For AWS EKS, see the
[HA & multi-tenant setup](https://github.com/Microservices-Demo-Projects/infra-setup/blob/main/argocd-setup/ha-multi-tenant-argocd-setup.md).

Reference: https://argo-cd.readthedocs.io/en/stable/try_argo_cd_locally/

## Install

Set the `kubectl` context first:
```bash
kubectl cluster-info --context kind-local-poc-cluster
```

Install ArgoCD from the upstream manifests:
```bash
kubectl create namespace argocd

kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Verify:
```bash
kubectl wait pod --all --for=condition=Ready --namespace=argocd --timeout=180s
kubectl get all,pvc -n argocd
```

## Access UI

**Port-forward:**
```bash
nohup kubectl port-forward svc/argocd-server -n argocd 8080:443 &
```
Open: `https://localhost:8080/`

**Credentials:**
- Username: `admin`
- Password:
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
  ```

**Stop port-forward:**
```bash
pkill -f "kubectl port-forward"
```

## CLI Setup

```bash
# Install CLI (macOS)
brew install argocd

nohup kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# Get password and login
PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
argocd login localhost:8080 --username admin --password "$PASSWORD" --insecure

# Verify
argocd account list
argocd repo list
argocd app list
```

## Configure Git Access

**HTTPS (Personal Access Token):**
```bash
kubectl create secret generic github-credentials \
  --from-literal=type=git \
  --from-literal=url=https://github.com \
  --from-literal=username=<USERNAME> \
  --from-literal=password=<PERSONAL_ACCESS_TOKEN> \
  -n argocd

kubectl label secret github-credentials argocd.argoproj.io/secret-type=repository -n argocd
```

**SSH — `secret-type=repository` (one secret per exact repo):**

`url` must be the exact clone URL of this repo — ArgoCD matches a
`secret-type=repository` secret against the `repoURL` in each
`Application`/`AppProject`, and a bare host matches nothing.

```bash
# Generate key (if needed), or point --from-file at an existing private key
ssh-keygen -t ed25519 -f argocd-key -N ""

kubectl create secret generic github-ssh \
  --from-literal=type=git \
  --from-literal=name=github-ssh \
  --from-literal=project=default \
  --from-literal=url=git@github.com:<ORG>/<REPO>.git \
  --from-literal=username=<USERNAME> \
  --from-file=sshPrivateKey=<path-to-private-key> \
  -n argocd

kubectl label secret github-ssh argocd.argoproj.io/secret-type=repository -n argocd
```

Add the public key (`argocd-key.pub`) to your GitHub SSH keys.

**SSH — `secret-type=repo-creds` (credential template for every repo under a prefix):**

Here `url` *is* a bare host or prefix: ArgoCD applies these credentials to any
repo whose `repoURL` starts with it, so one secret covers a whole GitHub org.

```bash
kubectl create secret generic github-ssh-creds \
  --from-literal=type=git \
  --from-literal=url=git@github.com:<ORG>/ \
  --from-literal=username=<USERNAME> \
  --from-file=sshPrivateKey=<path-to-private-key> \
  -n argocd

kubectl label secret github-ssh-creds argocd.argoproj.io/secret-type=repo-creds -n argocd
```

**Repository-specific credentials (HTTPS, `secret-type=repository`):**

Same exact-URL matching as the SSH `secret-type=repository` case, over HTTPS with
a username and PAT instead of a key.

```bash
kubectl create secret generic repo-specific \
  --from-literal=type=git \
  --from-literal=url=https://github.com/<USERNAME>/<REPO>.git \
  --from-literal=username=<USERNAME> \
  --from-literal=password=<PERSONAL_ACCESS_TOKEN> \
  -n argocd

kubectl label secret repo-specific argocd.argoproj.io/secret-type=repository -n argocd
```

## Next Steps

- [ArgoCD Docs](https://argo-cd.readthedocs.io/)
- Bootstrap the platform → [../../README.md](../../README.md)
