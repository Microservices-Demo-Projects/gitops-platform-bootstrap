# cert-manager

Issues and auto-renews TLS certificates, and creates `demo-ca` — the shared
certificate authority every other component in this platform trusts.

- [Kubernetes install](kubernetes/README.md) — upstream Helm chart
- [OpenShift install](openshift/README.md) — Red Hat cert-manager Operator (OLM)

`common/` holds the demo-ca certificate chain and the PreSync/PostSync test Jobs
shared by both platforms. The wrapper chart lives in `kubernetes/chart/` rather
than `common/chart/` because OpenShift installs the operator instead.
`manual/` has hand-install instructions for going without ArgoCD.
