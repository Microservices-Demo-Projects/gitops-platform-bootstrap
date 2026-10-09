# External Secrets (Kubernetes)

Copies secrets out of Vault into ordinary Kubernetes Secrets, and keeps them in sync.

This is what lets your apps stay simple. They read a normal Secret — no Vault
client, no token, no Vault-specific code. External Secrets does the talking.

## What's here

```text
values.yaml          Kubernetes-specific chart values          (wave 30)
../common/chart/     The ESO controller (Helm chart)           (wave 30)
../common/config/certificate/           ESO's mTLS certificate                      (wave 30)
../common/config/clustersecretstore/    The ClusterSecretStore - the link to Vault  (wave 50)
../common/tests/     Prereq gate, then a smoke test that pulls a real secret from Vault
../manual/           Install by hand instead
```

Two waves because the link to Vault can't be tested until Vault is configured
(wave 40).

## Install

Nothing to do — ArgoCD handles it. See the [ArgoCD guide](../../argocd/README.md).

## Verify

```bash
# Controller, webhook and cert-controller pods
kubectl get pods -n external-secrets

# The link to Vault. Must say Valid.
kubectl get clustersecretstore local-vault-backend
```

If that says `InvalidProviderConfig`, Vault isn't up yet — check Vault first.

## Using it

Ask for a secret from Vault by writing an `ExternalSecret`:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: my-db-credentials
  namespace: my-app
spec:
  secretStoreRef:
    name: local-vault-backend
    kind: ClusterSecretStore
  target:
    name: my-db-credentials        # the Kubernetes Secret it creates
  data:
    - secretKey: password
      remoteRef:
        key: database/creds/app-ro  # the path in Vault
        property: password
```

A Secret named `my-db-credentials` appears in your namespace. Mount it like any
other. Pair it with [Reloader](../../stakater-reloader/README.md) and your pods restart
automatically when the value rotates.

## Notes

### How it authenticates to Vault

Two things at once, no passwords involved:

- **Kubernetes auth** — ESO proves who it is with its own ServiceAccount token
- **mTLS** — it presents a cert-manager certificate (`external-secrets-tls`), and
  Vault presents one back, both signed by the shared `demo-ca`

Vault grants it read-only access to `kv/*` and `database/creds/*`, nothing more.

### Difference from the manual path

The manual install needs two passes: install ESO, configure Vault, then re-run
`helm upgrade --set clusterSecretStore.required=true`. Here the `ClusterSecretStore`
is declared once and simply waits for Vault, retrying until it's ready.
