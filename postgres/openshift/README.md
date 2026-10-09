# PostgreSQL (OpenShift)

Same job as on Kubernetes — a 3-node HA PostgreSQL cluster with Vault-issued,
hour-lived passwords — but installed via the certified **CloudNativePG**
operator (OLM Subscription) instead of the upstream Helm chart.

## What's here

```text
config/operator/     Subscription for the cloudnative-pg package  (wave 30)
config/namespace/    The namespace, labelled for GitOps           (wave 30)
../common/config/    The database cluster + its certificates      (wave 60)
tests/               A smoke test using a real Vault password
../common/tests/     Prereq gate
../manual/           The older Bitnami-chart path
```

Last wave, because it needs Vault (40) and External Secrets (50) working first
— same ordering as Kubernetes.

## Install

Nothing to do — ArgoCD installs this. See the
[ArgoCD guide](../../argocd/README.md).

## Verify

```bash
# Operator installed successfully?
oc get csv -n openshift-operators

# 3 pods, all Running
oc get pods -n postgres

# INSTANCES 3, READY 3, and a PRIMARY named
oc get cluster postgres -n postgres
```

Connecting, roles and superuser access are identical to the Kubernetes install
— see [../kubernetes/README.md](../kubernetes/README.md). Only how the operator
gets installed, and the shape of the smoke test, differ.

## Notes

### Get the package name right

Use `cloudnative-pg` (the upstream CNCF project), **not**
`cloud-native-postgresql` — a separate, EDB-owned certified package whose CRDs
live under a different API group (`postgresql.k8s.enterprisedb.io`) and are not
compatible with the `Cluster` manifests in `../common/config/base/`.

The Subscription installs into `openshift-operators` and relies on the
`global-operators` OperatorGroup OpenShift already provides there — no custom
OperatorGroup needed, since this package supports `AllNamespaces`.

### The smoke test needs its own copy

`tests/` replaces `../common/tests/base/smoke-test-job.yaml`, asserting exactly
the same thing; only *how* it gets its two tools differs.

The Kubernetes version runs one container off the `hashicorp/vault` image and
`apk add`s the PostgreSQL client into it. That can't work here. Under
`restricted-v2` the container runs as an arbitrary non-root UID and `apk` needs
to write `/lib/apk` and `/var/log`, so it exits before the test starts:

```text
ERROR: Unable to open log: Permission denied
```

Granting a package manager write access, or using an SCC that allows root,
would be a much worse trade than splitting the work across images that already
carry the tool each step needs:

| Container | Image | Does |
| --- | --- | --- |
| `fetch-vault-token` | `alpine/k8s` | Waits for the primary, reads the root token |
| `fetch-db-creds` | `vault` | Requests the dynamic lease |
| `psql-check` | `postgresql` | The actual `SELECT 1` over verify-full TLS |
| `revoke-lease` | `vault` | Cleanup — the main container, so it runs last |

Init containers run in order and must each exit 0, so `revoke-lease` starting at
all proves `psql-check` passed.

The Kubernetes copy is deliberately left alone. If it ever needs the same
treatment, note that `hashicorp/vault:1.21` is no longer Alpine either — that
tag now resolves to a UBI/RHEL base with `microdnf` and no `apk` at all.
