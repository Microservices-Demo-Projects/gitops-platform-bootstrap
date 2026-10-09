# External Secrets (OpenShift)

Same job as on Kubernetes — copies secrets out of Vault into ordinary
Kubernetes Secrets — from the same upstream Helm chart (`../common/chart/`),
just with different values. The OLM operator is deliberately not used; see the
notes.

## What's here

```text
values.yaml          OpenShift overrides for ../common/chart   (wave 30)
config/namespace/    The namespace, labelled for GitOps        (wave 30)
../common/chart/     The upstream external-secrets chart       (wave 30)
../common/config/certificate/           ESO's mTLS certificate                      (wave 50)
../common/config/clustersecretstore/    The ClusterSecretStore - the link to Vault  (wave 50)
../common/tests/     Prereq gate, then a smoke test that pulls a real secret from Vault
../manual/           Install by hand instead
```

## Install

Nothing to do — ArgoCD installs this. See the
[ArgoCD guide](../../argocd/README.md).

## Verify

```bash
# Controller, webhook and cert-controller pods
oc get pods -n external-secrets

# Confirm the platform assigned the UID rather than the chart pinning 1000
oc get pod -n external-secrets -o jsonpath='{.items[*].spec.securityContext.runAsUser}{"\n"}'

# The link to Vault. Must say Valid.
oc get clustersecretstore local-vault-backend
```

If that says `InvalidProviderConfig`, Vault isn't up yet — check Vault first.

## Using it

Same as Kubernetes — see
[../kubernetes/README.md](../kubernetes/README.md#using-it) for the
`ExternalSecret` example and how authentication to Vault works.

## Notes

### Why the Helm chart and not the OLM operator

This used to install the community **external-secrets-operator** via an OLM
`Subscription`. That path is retired, on portability grounds rather than as a
one-cluster workaround:

- The operator's own image,
  `ghcr.io/external-secrets/external-secrets-helm-operator`, publishes a
  **single `linux/amd64` manifest** — there is no arm64 build. On an arm64 node
  it runs under emulation and dies inside the Go runtime's garbage collector:
  `CrashLoopBackOff` with `asm_amd64.s` / `runtime.gcBgMarkWorker` in the panic
  trace.
- The chart's operand image, `ghcr.io/external-secrets/external-secrets`, is a
  proper **multi-arch manifest list** (`linux/amd64`, `linux/arm64`,
  `linux/ppc64le`, `linux/s390x`). The container runtime picks the right
  architecture per node, so the identical manifests work on an arm64 CRC laptop
  and on amd64 cloud nodes with nothing to parameterize.

The `Subscription` manifests are in git history if you're on an amd64-only
cluster and prefer OLM lifecycle management.

### What `values.yaml` overrides, and why

Only two things, both platform-shaped:

1. **Single replica, no PodDisruptionBudget** — a CRC/demo cluster is typically
   single-node. (The chart itself defaults to 1 replica; it's
   `../kubernetes/values.yaml` that opts into 2 + a PDB.)
2. **`runAsUser: null`** on all three workloads (controller, webhook,
   cert-controller). The upstream chart hardcodes `runAsUser: 1000`, and
   OpenShift's `restricted-v2` SCC rejects a fixed UID outside the namespace's
   dynamically allocated range:

   ```text
   .spec.securityContext.runAsUser: Invalid value: 1000: must be in the ranges: [1000xxxxxx, 1000xxxxxx]
   ```

   An explicit `null` in user values makes Helm drop the key during merge, so
   OpenShift assigns a UID from the namespace's own range instead.
   `runAsNonRoot`, `readOnlyRootFilesystem`, dropped capabilities and the
   seccomp profile all stay exactly as upstream ships them — `restricted-v2` is
   happy with those; the pinned UID is the only thing it objects to.

   Same idea as stakater-reloader's `isOpenshift` flag and the Vault CR's
   `platformManagedSecurityContext: true`: let the platform pick the UID.

### If you're migrating from the OLM path

OLM does not remove CRDs when a CSV goes away, so the `external-secrets.io`
CRDs from the old operator may still be on the cluster. The Application syncs
with `ServerSideApply=true` so the chart adopts them instead of failing on
"already exists". If the `OperatorConfig` CRD lingers, it's inert once the
Subscription and CSV are gone.
