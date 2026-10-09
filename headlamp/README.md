# Headlamp

A web UI for the cluster — browse pods, read logs, check why something's failing.
Served over HTTPS with a certificate from the shared `demo-ca`.

**Kubernetes only.** OpenShift has its own built-in console, so there is no
OpenShift path — see [kubernetes/README.md](kubernetes/README.md).

`common/` holds its TLS certificate and RBAC, kept separate from `kubernetes/`
for consistency with the rest of the repo even though there's only one consumer.
The wrapper chart is in `kubernetes/chart/` for the same reason.
`manual/` has hand-install instructions for going without ArgoCD.
