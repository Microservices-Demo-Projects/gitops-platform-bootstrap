# Reloader (Kubernetes)

When a Secret or ConfigMap changes, the pods using it don't notice — they keep
running with the old values. Reloader watches for those changes and restarts the
affected pods for you.

That matters here because Vault rotates database passwords. Without Reloader you'd
have to restart apps by hand every time a password changed.

## What's here

```text
values.yaml          2 replicas with leader election         (wave 30)
../common/chart/     Helm chart for Reloader
../manual/           Install by hand instead
```

There's no `config/` stage — Reloader is installed once and just runs.

## Install

Nothing to do — ArgoCD handles it. See the [ArgoCD guide](../../argocd/README.md).

## Verify

```bash
kubectl get pods -n stakater-reloader
```

## Using it

Add an annotation to any Deployment you want restarted automatically:

```yaml
metadata:
  annotations:
    reloader.stakater.com/auto: "true"     # watch everything this pod mounts
```

Or watch one specific Secret:

```yaml
    secret.reloader.stakater.com/reload: "my-db-credentials"
```

That's the whole feature.
