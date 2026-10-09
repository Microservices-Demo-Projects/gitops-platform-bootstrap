# Headlamp (Kubernetes)

A web UI for the cluster — browse pods, read logs, check why something's failing.
Served over HTTPS with a certificate from the shared `demo-ca`.

> **Kubernetes only.** OpenShift has its own console, so this component is skipped
> there entirely — there is no `openshift/` directory.

## What's here

```text
chart/               Helm chart for Headlamp          (wave 30)
values.yaml          Kubernetes-specific chart values  (wave 30)
../common/config/    Its TLS certificate and RBAC      (wave 30)
../manual/           Install by hand instead
```

## Install

Nothing to do — ArgoCD handles it. See the [ArgoCD guide](../../argocd/README.md).

## Verify

```bash
kubectl get pods,certificate -n headlamp
```

Pod should be `1/1 Running` and `headlamp-tls` should be `READY=True`.

## Open it

```bash
kubectl port-forward -n headlamp svc/headlamp 8443:443
```

Go to `https://localhost:8443`. Your browser will warn about the certificate —
expected, it's signed by the demo CA. Click through.

Then get a login token:

```bash
kubectl create token headlamp-view --namespace headlamp
```

Paste it into the login box. Done.

| Command | Access |
| --- | --- |
| `kubectl create token headlamp-view -n headlamp` | Read-only. Use this. |
| `kubectl create token headlamp -n headlamp` | Full cluster-admin. |

Both last an hour. Just run the command again when it expires.

## Notes

### If you need a token that doesn't expire

For CI or an integration that can't re-run `kubectl`:

```bash
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Secret
metadata:
  name: headlamp-view-token
  namespace: headlamp
  annotations:
    kubernetes.io/service-account.name: "headlamp-view"
type: kubernetes.io/service-account-token
YAML

kubectl get secret headlamp-view-token -n headlamp \
  -o jsonpath='{.data.token}' | base64 -d
```

This token is stored in the cluster and lives until you delete it — less safe than
the one-hour tokens above.

### Note on the chart

The upstream chart moved from `headlamp-k8s/headlamp` (now a dead 404 URL) to
`kubernetes-sigs/headlamp`, and this uses version `0.44.0` instead of `0.39.0`. The
newer version supports `probes.scheme: HTTPS` in values, which removes the manual
`kubectl patch` the older chart needed.
