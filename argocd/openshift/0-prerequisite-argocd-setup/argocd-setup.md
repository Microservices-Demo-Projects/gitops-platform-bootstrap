# ArgoCD Setup (OpenShift)

GitOps installation for an OpenShift cluster. Written against a local CRC cluster,
but the same steps work unchanged on any dev/test-sized OpenShift cluster — nothing
here is CRC-specific. For plain Kubernetes, see the [kubernetes/](../../kubernetes/0-prerequisite-argocd-setup/argocd-setup.md) setup docs.

This is not a production install guide. The operator ships a single-instance
`ArgoCD` CR by default; for production sizing and HA, follow the guidance in the
official docs linked below instead of this doc.

Reference: https://docs.redhat.com/en/documentation/red_hat_openshift_gitops

## Install

Set the `oc` context first:
```bash
oc login -u kubeadmin https://api.crc.testing:6443
```

Install the **Red Hat OpenShift GitOps Operator** via OLM rather than the raw
`install.yaml` used on Kubernetes — it wires up the SCCs and RBAC for you:
```bash
oc apply -f - <<'EOF'
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: openshift-operators
spec:
  channel: latest
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

oc get csv -n openshift-operators -w
```

The operator creates the `openshift-gitops` namespace, a default `openshift-gitops`
ArgoCD instance in it, and a Route for the UI — there's no ArgoCD CR to author.

Verify:
```bash
oc wait pod --all --for=condition=Ready --namespace=openshift-gitops --timeout=180s
oc get all -n openshift-gitops
```

## Access UI

**Route (preferred on OpenShift):**
```bash
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'
```
Open `https://<that-host>/` in a browser.

**Port-forward (fallback):**
```bash
nohup oc port-forward svc/openshift-gitops-server -n openshift-gitops 8080:443 &
```
Open: `https://localhost:8080/`

**Credentials:**
- Username: `admin`
- Password:
  ```bash
  oc -n openshift-gitops get secret openshift-gitops-cluster -o jsonpath='{.data.admin\.password}' | base64 -d
  ```

**Stop port-forward:**
```bash
pkill -f "oc port-forward"
```

## CLI Setup

```bash
# Install CLI (macOS)
brew install argocd

# Port-forward past the router: logging in through the Route hits
# `gRPC connection not ready` even with --grpc-web.
nohup oc port-forward svc/openshift-gitops-server -n openshift-gitops 8080:443 &

# Get password and login
PASSWORD=$(oc -n openshift-gitops get secret openshift-gitops-cluster -o jsonpath='{.data.admin\.password}' | base64 -d)
argocd login localhost:8080 --username admin --password "$PASSWORD" --insecure

# Verify
argocd account list
argocd repo list
argocd app list
```

## Configure Git Access

**HTTPS (Personal Access Token):**
```bash
oc create secret generic github-credentials \
  --from-literal=type=git \
  --from-literal=url=https://github.com \
  --from-literal=username=<USERNAME> \
  --from-literal=password=<PERSONAL_ACCESS_TOKEN> \
  -n openshift-gitops

oc label secret github-credentials argocd.argoproj.io/secret-type=repository -n openshift-gitops
```

**SSH — `secret-type=repository` (one secret per exact repo):**

`url` must be the exact clone URL of this repo — ArgoCD matches a
`secret-type=repository` secret against the `repoURL` in each
`Application`/`AppProject`, and a bare host matches nothing.

```bash
# Generate key (if needed), or point --from-file at an existing private key
ssh-keygen -t ed25519 -f argocd-key -N ""

oc create secret generic github-ssh \
  --from-literal=type=git \
  --from-literal=name=github-ssh \
  --from-literal=project=default \
  --from-literal=url=git@github.com:<ORG>/<REPO>.git \
  --from-literal=username=<USERNAME> \
  --from-file=sshPrivateKey=<path-to-private-key> \
  -n openshift-gitops

oc label secret github-ssh argocd.argoproj.io/secret-type=repository -n openshift-gitops
```

Add the public key (`argocd-key.pub`) to your GitHub SSH keys.

**SSH — `secret-type=repo-creds` (credential template for every repo under a prefix):**

Here `url` *is* a bare host or prefix: ArgoCD applies these credentials to any
repo whose `repoURL` starts with it, so one secret covers a whole GitHub org.

```bash
oc create secret generic github-ssh-creds \
  --from-literal=type=git \
  --from-literal=url=git@github.com:<ORG>/ \
  --from-literal=username=<USERNAME> \
  --from-file=sshPrivateKey=<path-to-private-key> \
  -n openshift-gitops

oc label secret github-ssh-creds argocd.argoproj.io/secret-type=repo-creds -n openshift-gitops
```

**Repository-specific credentials (HTTPS, `secret-type=repository`):**

Same exact-URL matching as the SSH `secret-type=repository` case, over HTTPS with
a username and PAT instead of a key.

```bash
oc create secret generic repo-specific \
  --from-literal=type=git \
  --from-literal=url=https://github.com/<USERNAME>/<REPO>.git \
  --from-literal=username=<USERNAME> \
  --from-literal=password=<PERSONAL_ACCESS_TOKEN> \
  -n openshift-gitops

oc label secret repo-specific argocd.argoproj.io/secret-type=repository -n openshift-gitops
```

## Grant the App Controller Access to the Platform's Namespaces

OpenShift-only, and a cluster-admin has to do it once. The default
`argocd-application-controller` ClusterRole can write only a short allowlist of
apiGroups, so each namespace this platform deploys into must be registered before
the controller may create ordinary namespaced resources in it. Each component's
`openshift/config/namespace/` already applies the
`argocd.argoproj.io/managed-by: openshift-gitops` label via GitOps; this patch is
what tells the ArgoCD instance it may act on that label.

```bash
oc patch argocd openshift-gitops -n openshift-gitops --type merge -p '
spec:
  namespaceManagement:
    - name: cert-manager
      allowManagedBy: true
    - name: external-secrets
      allowManagedBy: true
    - name: vault
      allowManagedBy: true
    - name: postgres
      allowManagedBy: true
    - name: stakater-reloader
      allowManagedBy: true
'
```

That grants a namespace-scoped `admin` RoleBinding in each. Cluster-scoped
resources (CRDs, `ClusterIssuer`, `ClusterSecretStore`) are handled separately by
[../apps/wave-005-argocd-extra-rbac.yaml](../apps/wave-005-argocd-extra-rbac.yaml),
which is safe to self-apply because `rbac.authorization.k8s.io` is already
permitted.

## Next Steps

- [OpenShift GitOps Docs](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops)
- Bootstrap the platform → [../../README.md](../../README.md)
