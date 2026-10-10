# ArgoCD Setup (Kubernetes)

GitOps installation for a Kubernetes cluster, with a choice of two upstream
manifests below. Written against a local Kind cluster, but the same steps work
unchanged on any dev/test-sized cluster (EKS, GKE, etc.) — nothing here is
Kind-specific.

This is not a production install guide. For a production cluster, follow ArgoCD's
own [installation docs](https://argo-cd.readthedocs.io/en/stable/operator-manual/installation/)
and [High Availability guide](https://argo-cd.readthedocs.io/en/stable/operator-manual/high_availability/)
instead of this doc.

Reference: https://argo-cd.readthedocs.io/en/stable/try_argo_cd_locally/

For OpenShift specific setup, see the [OpenShift/](../../openshift/0-prerequisite-argocd-setup/argocd-setup.md) setup docs.

## Install

Set the `kubectl` context first:
```bash
kubectl cluster-info --context kind-local-poc-cluster
```

Both options below are pinned to a release tag (`v3.5.4`), not a moving branch like
`stable` or `master` — re-running this doc later installs the same thing every time.

```bash
kubectl create namespace argocd
```

**Option A — single-replica (quick-test, lighter on a laptop/Kind):**
```bash
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.4/manifests/install.yaml
```

**Option B — HA (2x `argocd-server`/`argocd-repo-server`, redis-ha with sentinel —
closer to a prod topology, heavier on cluster resources):**
```bash
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.4/manifests/ha/install.yaml
```

Pick one. `argocd-application-controller` stays a single-replica StatefulSet either
way — sharding it across more replicas is a separate, opt-in step upstream.

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
