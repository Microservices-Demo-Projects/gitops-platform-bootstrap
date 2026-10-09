# PostgreSQL

A 3-node PostgreSQL cluster (1 primary, 2 replicas) with automatic failover, TLS
on every connection, and passwords issued by Vault that expire after an hour.
Run by [CloudNativePG](https://cloudnative-pg.io/) (CNPG), a CNCF operator.

- [Kubernetes install](kubernetes/README.md) — CNPG via its Helm chart
- [OpenShift install](openshift/README.md) — the certified `cloudnative-pg` operator (OLM)

`common/` holds the `Cluster` CR, its certificates, and PreSync/PostSync test
Jobs shared by both platforms — CNPG's CRDs are identical regardless of how the
operator itself got installed. The chart lives in `kubernetes/chart/`, not
`common/chart/`, because only Kubernetes installs it that way. `manual/` has the
older Bitnami-chart path.

## Notes

### Superuser access is a git commit

`enableSuperuserAccess` is `false` — CNPG's own recommendation, since the
operator manages the cluster through its own internal mechanism and doesn't need
it. Login is break-glass only: flip it to `true`, commit, push, and let ArgoCD
sync. CNPG generates a fresh password into the auto-created
`postgres-superuser` Secret and enables login with it. Flip it back and sync
again to disable. Each toggle is a commit, so there's an audit trail of every
time superuser access was opened.

### Why `vault` isn't a CNPG managed role

It's defined once, in `postInitApplicationSQL`, and deliberately left out of
`managed.roles`. CNPG's managed-role reconciler treats a role's `inRoles` list
(empty by default) as the sole source of truth for its memberships and
continuously `REVOKE`s anything outside it — including the `WITH ADMIN OPTION`
grants that `vault` needs. `inRoles` has no way to *request* `ADMIN OPTION`
either: it issues a plain `GRANT`, re-applied every reconcile, which silently
strips whatever option was there before.

Since PG16+ requires `ADMIN OPTION` to grant a role you didn't create
(`CREATEROLE` alone no longer suffices), letting CNPG manage `vault` breaks
dynamic credential creation within minutes of every start. `postInitApplicationSQL`
runs once at bootstrap and is never touched again, so that's where it lives.

### `pg_hba` matches dynamic users by role membership

The `+app_ro` / `+app_rw` syntax matches any role that is a *member* of those
roles, which is what Vault's `creation_statements` grant each `vlt_app_ro_*`
user at creation time. This replaced the old Bitnami config's `vlt_+` rule —
invalid glob syntax that never matched anything. `pg_hba` is first-match-wins
with no fallthrough on a non-match, so those two lines were silently dead and
every dynamic user was landing on the catch-all instead.

### Why CNPG and not Bitnami

The `manual/` path uses the Bitnami PostgreSQL chart and still works, but for GitOps
CNPG is a better fit:

- **Bitnami's images broke.** `docker.io/bitnami/postgresql:*` now 404s, and the
  current chart defaults to an unpinned `:latest` — not something you can sync
  repeatably.
- **HA is built in.** The `Cluster` resource handles primary/replica topology,
  failover and replication. No StatefulSet wiring by hand.
- **cert-manager works natively.** Server, client and replication TLS all take
  cert-manager secrets directly, reusing the shared `demo-ca`.
- **Schema and roles are declarative** instead of a hand-run `psql` session.

CNPG is Apache-2.0.
