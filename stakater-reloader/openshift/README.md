# Reloader (OpenShift)

Same job as on Kubernetes — watches Secrets and ConfigMaps and restarts the
pods using them. No OLM operator exists for Reloader, so this installs the
same [Helm chart](https://github.com/stakater/Reloader) as Kubernetes, from
`../common/chart/`.

## What's here

```text
values.yaml          Single replica, and unsets the subchart's UID  (wave 30)
config/namespace/    The namespace, labelled for GitOps
../common/chart/     Helm chart for Reloader
../manual/           Install by hand instead
```

There's no `config/` stage beyond the namespace — Reloader is installed once
and just runs.

## Install

Nothing to do — ArgoCD handles it. See the [ArgoCD guide](../../argocd/README.md).

## Verify

```bash
oc get pods -n stakater-reloader
```

## Using it

Identical to Kubernetes — see
[../kubernetes/README.md](../kubernetes/README.md#using-it) for the
annotation examples.

## Notes

### Why `values.yaml` has to be an ArgoCD overlay

`../common/chart/values.yaml` — the wrapper chart's own defaults — is mostly
OpenShift-shaped already (`isOpenshift: true`, `readOnlyRootFilesystem: true`).
One thing it can't fix from inside the chart's own default values file: the
vendored `reloader` subchart hardcodes
`reloader.deployment.securityContext.runAsUser: 65534`, which `restricted-v2`
rejects (65534 isn't in the namespace's allocated UID range), so pods fail to
schedule with `FailedCreate ... must be in the ranges: [...]`.

Unsetting a subchart's hardcoded default has to come from a genuine
user-supplied values overlay. Helm's dependency-value merging does not treat a
`null` set in a chart's *own* defaults as "remove the subchart's key" — only a
`-f` / `helm.valueFiles` layer on top does. Verified with `helm template`: the
same `null` baked into `common/chart/values.yaml` renders as the subchart's
unchanged 65534; passed here via `helm.valueFiles`, it actually removes the key.

### Known gap vs. Kubernetes

This runs a single replica with no PodDisruptionBudget, unlike the Kubernetes
side's 2-replica HA setup with leader election. Acceptable for a demo, but worth
knowing if you're comparing the two paths.
