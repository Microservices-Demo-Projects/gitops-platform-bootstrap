# HashiCorp Vault (Kubernetes)

Stores the platform's secrets, and hands out **PostgreSQL passwords that expire on
their own** — every app that asks for database credentials gets a brand-new user,
automatically deleted an hour later.

The important part: **Vault initialises and unseals itself.** No `vault operator init`,
no typing in three unseal keys, and it stays unsealed across pod restarts.

## What's here

```text
values.yaml          Kubernetes-specific chart values                 (wave 30)
../common/chart/     The vault-operator (installs the operator only)  (wave 30)
../common/config/    The Vault server itself, as a Vault resource     (wave 40)
../common/tests/     Prereq gate, then a smoke test that writes and reads a secret
../manual/           Install by hand instead
```

Two waves because the operator has to exist before it can be given a `Vault`
resource to act on.

## Install

Nothing to do — ArgoCD handles it. See the [ArgoCD guide](../../argocd/README.md).

Vault takes the longest of any component (3 pods, plus init and unseal), so give it
a few minutes.

## Verify

```bash
# 3 vault pods, all Running
kubectl get pods -n vault

# Has Vault elected a leader? A name here means it's initialised and unsealed.
kubectl get vault vault -n vault -o jsonpath='{.status.leader}'
```

## Getting the root token

The operator generated it at startup and put it in a Secret:

```bash
kubectl get secret vault-unseal-keys -n vault \
  -o jsonpath='{.data.vault-root}' | base64 -d
```

Then open the UI:

```bash
kubectl port-forward -n vault svc/vault 8200:8200
# https://localhost:8200  (certificate warning is expected - it's the demo CA)
```

> **This Secret holds the unseal keys too.** Anyone with read access to it can
> unseal and read all of Vault. Fine for a demo; in production these belong in a
> cloud KMS.

## Notes

### What Vault is configured with

All declared in `../common/config/base/vault.yaml`, applied by the operator:

| | |
| --- | --- |
| Storage | Raft, 3 nodes, real HA |
| `kv` engine | General secrets, at `kv/` |
| `database` engine | Rotating PostgreSQL credentials |
| `kubernetes` auth | Lets External Secrets log in as itself, no password |

The database roles (`app-ro`, `app-rw`) mint a fresh PostgreSQL user per request,
valid 1 hour, then revoked automatically. See
[../README.md#notes](../README.md#notes) for how init/unseal works and why Vault
deliberately can't rotate the postgres superuser.

### Two things to know

**Vault connects to PostgreSQL with a certificate, not a password.** It uses the same
cert-manager certificate it serves HTTPS with, so there's no database password to
store anywhere.

**`verify_connection: false` is deliberate.** Vault comes up at wave 40, before
PostgreSQL exists at wave 60, so it can't test the connection yet. PostgreSQL's own
smoke test proves the link works once both are up.

### Why the operator instead of HashiCorp's chart

HashiCorp's official chart only runs Vault server pods — it has no automation for
init, unseal, or configuration, which is why the `manual/` path needs all those
hand-run steps. [bank-vaults](https://github.com/bank-vaults/vault-operator)
(Apache-2.0, community-run — not a HashiCorp project) adds exactly that.

Vault itself is [BUSL-1.1](https://github.com/hashicorp/vault/blob/main/LICENSE)
licensed: free for a demo like this, but check the terms before production use.
