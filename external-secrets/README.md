# External Secrets

Copies secrets out of Vault into ordinary Kubernetes Secrets, and keeps them in
sync, so apps never need Vault-specific code.

- [Kubernetes install](kubernetes/README.md) — upstream Helm chart
- [OpenShift install](openshift/README.md) — same Helm chart, OpenShift values

`common/` holds the wrapper Helm chart, the mTLS certificate, the
`ClusterSecretStore` (the link to Vault), and the PreSync/PostSync test Jobs. The
chart lives in `common/chart/` because both platforms install from it, differing
only in their `values.yaml` — the OLM operator path is retired (amd64-only image;
see [openshift/README.md](openshift/README.md#notes)). `manual/` has hand-install
instructions for going without ArgoCD. `backup/` is an unrelated vendored CRD
bundle, not part of the GitOps flow.
