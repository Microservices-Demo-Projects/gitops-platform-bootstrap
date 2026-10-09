# Deploy everything with ArgoCD

One command and the whole platform comes up: cert-manager, Vault (auto-initialised
and unsealed), External Secrets, PostgreSQL. No manual steps in between.

`kubernetes/` and `openshift/` hold the same set of Applications and are meant to be
read side by side — `diff argocd/kubernetes/apps/wave-040-vault.yaml
argocd/openshift/apps/wave-040-vault.yaml` shows two lines, and that is the whole
difference between the platforms for that app.

## Quick start

You need a cluster with ArgoCD already installed — see
`<platform>/0-prerequisite-argocd-setup/`.

```bash
kubectl apply -f argocd/kubernetes/bootstrap/    # Kubernetes
oc apply -f argocd/openshift/bootstrap/          # OpenShift
```

That's two files: the project the apps live in, and `platform-root`, which creates
everything else.

Then watch it come up (10-15 minutes):

```bash
kubectl get applications -n argocd -w             # Kubernetes
oc get applications -n openshift-gitops -w        # OpenShift
```

You're done when all apps show `Synced` and `Healthy`.

## What comes up, in order

Each app has an `argocd.argoproj.io/sync-wave` number, and ArgoCD finishes one wave
before starting the next.

| Wave | App | What it does | Platform |
| --- | --- | --- | --- |
| 0 | health checks | Two Lua health checks ArgoCD lacks (see below) | both |
| 5 | `argocd-extra-rbac` | Cluster-scoped grants the app controller lacks | OpenShift |
| 10 | `cert-manager` | Issues TLS certificates for everything below | both |
| 20 | `cert-manager-config` | Creates `demo-ca`, the shared CA all certs come from | both |
| 30 | `vault-operator`, `external-secrets`, `cloudnative-pg-operator`, `stakater-reloader` | The operators and controllers | both |
| 30 | `headlamp` | Web UI (OpenShift has its own console) | Kubernetes |
| 40 | `vault` | The Vault server itself: 3-node HA, auto-unsealed | both |
| 50 | `external-secrets-config` | Connects External Secrets to Vault | both |
| 60 | `postgres` | 3-node PostgreSQL with credentials from Vault | both |

Each app self-heals, so once it's up it stays up.

## Conventions every app file shares

Rather than repeat these as comments in all 22 files:

- **`finalizers: [resources-finalizer.argocd.argoproj.io]`** — cascades deletion, so
  removing `platform-root` tears down what each app deployed instead of orphaning it.
- **`retry: {limit: 5, backoff: 10s ×2, max 3m}`** — rides out transient bootstrap
  failures (a dependency's webhook or API not answering yet) without a manual re-sync.
- **`ServerSideApply=true`** — lets an app own only the fields it declares, which is
  what makes it safe for wave 0 to patch a live ArgoCD CR.
- **`<component>/openshift/config/namespace/` has no Kubernetes counterpart.** OpenShift needs an
  `argocd.argoproj.io/managed-by: openshift-gitops` label that `CreateNamespace=true`
  won't add, and the namespace must also be listed in the ArgoCD CR's
  `spec.namespaceManagement` — a one-time manual step, see
  `openshift/0-prerequisite-argocd-setup/local-argocd-setup.md`.

## Each app checks its own prerequisites

Waves say what order to go in. They don't say whether the previous wave is *usable*
yet — so the four apps with real dependencies check for themselves, with two Jobs
ArgoCD runs for them:

- **Before** anything is applied, a **PreSync gate** waits for what this app needs:
  the CRDs it uses, the operator that reconciles it, `demo-ca`, Vault having a
  leader. It then proves cert-manager's webhook is really answering by sending it a
  throwaway object as a server-side dry-run — admitted by the real webhook, created
  in the cluster as nothing.
- **After** it's synced, a **PostSync smoke test** proves the component actually
  works: Vault really unseals, PostgreSQL really hands out a Vault-issued password.

Either one failing fails the wave, so nothing downstream starts and a broken
component can't be mistaken for a working one. Both live in `<component>/common/tests/`.

Conventions shared by all of them, so they behave the same way everywhere:

- **A `retry()` helper**, bounded at ~5 minutes. Used instead of bare `kubectl
  wait` because `wait` errors out immediately on an object that doesn't exist yet
  rather than waiting for it to appear.
- **`activeDeadlineSeconds` on every Job.** A pod that can never start leaves the
  hook `Running` forever, and ArgoCD's `retry` only fires on a sync that
  terminates as `Failed` — the deadline turns a stall into something retryable.
- **`--dry-run=server` to probe a webhook.** It runs the real admission chain and
  then discards the object, so it proves the path works and creates nothing.
  `Available` on the webhook Deployment only means its pods are Ready; the Service
  endpoints and the injected CA bundle can each still be a moment behind.
- **Hook RBAC is annotated as a hook too**, so it doesn't outlive the test. It
  includes `patch` because a retry's `kubectl apply` patches rather than creates.

This is what fixed the bootstrap. `Certificate/vault-tls` used to be applied about
three seconds before cert-manager's webhook started serving; it was rejected with
`connection refused`, while the `Vault` resource next to it applied fine — leaving
the operator looping forever on a certificate that would never arrive. The gate
makes that ordering impossible rather than unlikely.

## The two health checks in wave 0

Sync waves only work if ArgoCD can tell whether a resource is healthy. Two kinds it
can't, both fixed in `<platform>/apps/wave-000-argocd-health-checks.yaml`:

- **A child `Application`.** ArgoCD removed this check in 1.8. Without it the waves
  are ignored entirely: all apps get created in the same 15 seconds, Vault tries
  to start before cert-manager can issue its certificate, and the bootstrap fails.
- **A `Vault` resource.** No built-in check exists, so `vault` would look Healthy the
  moment the resource is created — before Vault is unsealed. The check waits for
  Vault to elect a leader.

Both live in that one file on purpose. ArgoCD applies with a single shared field
manager, so if a second app also declared part of `argocd-cm` it would silently
delete these keys.

The two platforms get there differently. On Kubernetes the file *is* `argocd-cm`. On
OpenShift the operator owns that ConfigMap and reverts hand-edits, so the checks go
into the ArgoCD CR's `spec.resourceHealthChecks` — the operator-supported route —
with `ServerSideApply=true,Delete=false,Prune=false` so the app owns only that one
field and can never prune the ArgoCD instance itself.

## If something goes wrong

```bash
kubectl describe application <name> -n argocd   # why it's unhealthy
kubectl get certificate -A                     # certs Ready?
kubectl logs -n vault -l app.kubernetes.io/name=vault-operator
```

Failed gates and smoke tests leave their pods behind on purpose — check their logs.

## Tearing it down

To remove everything — Vault's keys, the database, the namespaces — and get back
to the cluster you started with:

```bash
./argocd/kubernetes/teardown.sh    # or ./argocd/openshift/teardown.sh
```

Deleting `platform-root` by hand is *not* enough, and it fails quietly:

- **It leaves things behind.** Only resources ArgoCD tracks get deleted. The
  namespaces aren't tracked (ArgoCD made them via `CreateNamespace=true`), and
  neither is anything an operator made for itself: Vault's raft volumes and unseal
  keys, cert-manager's issued TLS Secrets, PostgreSQL's data. Leftover raft data is
  the nasty one — the next Vault adopts a cluster it has no unseal keys for. The
  script deletes the namespaces, which takes all of it. CRDs have also been seen to
  outlive a cascade that otherwise completed cleanly, hence the sweep.
- **It can wedge permanently.** On Kubernetes, `argocd-cm` is declared in wave 0, so
  the cascade deleted ArgoCD's own ConfigMap — and the controller reads it on *every*
  delete, so `finalizeApplicationDeletion` then failed for every app and
  `platform-root` sat in `Deleting` forever. On OpenShift the same trap is the
  `platform` AppProject: every Application references it via `spec.project`, so if it
  goes first, nothing can finalize (`DeletionError: appproject.argoproj.io "platform"
  not found`). Each script's first step puts its own back before deleting anything.
- **It can just be slow.** Every child app's finalizer runs a sync before it can go
  away, and that sync still runs PreSync hooks — including gates that wait on another
  component being torn down in the same cascade. The gate keeps failing and the app
  retries with backoff instead of finishing. The wait-then-release loop doesn't care
  why an app is still around, so it resolves this the same way it resolves a wedge.

One OpenShift-only leftover the sweeps can't reach: `openshift-gitops-cm`, written by
an earlier wave-0 revision. It still carries `platform-root`'s tracking-id and the
`Delete=false,Prune=false` options that revision gave it, so ArgoCD wants to prune it,
refuses, and reports `platform-root` permanently `OutOfSync`. The namespace sweep
misses it because `openshift-gitops` is never deleted, so the script removes it by name.

Neither script ever touches ArgoCD itself.

## Notes

- Kafka isn't wired in yet.
- Every component can also be installed by hand — see `<component>/manual/README.md`.
