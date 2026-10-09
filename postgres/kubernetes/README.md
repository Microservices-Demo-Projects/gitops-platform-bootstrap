# PostgreSQL (Kubernetes)

A 3-node PostgreSQL cluster (1 primary, 2 replicas) with automatic failover, TLS on
every connection, and **passwords issued by Vault that expire after an hour**.

Run by [CloudNativePG](https://cloudnative-pg.io/) (CNPG), a CNCF operator.

## What's here

```text
chart/               The CNPG operator (Helm chart)             (wave 30)
values.yaml          Kubernetes-specific chart values           (wave 30)
../common/config/    The database cluster + its certificates    (wave 60)
../common/tests/     Prereq gate, then a smoke test using a real Vault password
../manual/           The older Bitnami-chart path
```

Last wave, because it needs Vault (40) and External Secrets (50) working first.

## Install

Nothing to do — ArgoCD handles it. See the [ArgoCD guide](../../argocd/README.md).

## Verify

```bash
# 3 pods, all Running
kubectl get pods -n postgres

# INSTANCES 3, READY 3, and a PRIMARY named
kubectl get cluster postgres -n postgres
```

## Connecting

CNPG creates three Services — pick based on what you need:

| Service | Use for |
| --- | --- |
| `postgres-rw.postgres.svc.cluster.local:5432` | Reads and writes (the primary) |
| `postgres-ro.postgres.svc.cluster.local:5432` | Read-only (replicas, spreads load) |
| `postgres-r.postgres.svc.cluster.local:5432` | Reads from any instance |

The database is `pocdb`. Get credentials through Vault, not a fixed password — see
the `ExternalSecret` example in the
[External Secrets guide](../../external-secrets/kubernetes/README.md), using
`database/creds/app-ro` or `database/creds/app-rw`.

Every password Vault issues creates a **new PostgreSQL user**, deleted after an
hour. Nothing to rotate, nothing to leak.

| Role | Can do |
| --- | --- |
| `app_ro` | Read the `app` schema |
| `app_rw` | Read and write the `app` schema |
| `vault` | Create and drop the temporary users above. Logs in with a certificate, no password. |

Superuser access is off by default and is a break-glass toggle — see
[../README.md#notes](../README.md#notes), which also covers why Vault doesn't
manage that password and how `pg_hba` matches the dynamic users.
