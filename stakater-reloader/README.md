# Reloader

Watches Secrets and ConfigMaps for changes and restarts the pods using them —
needed here because Vault rotates database passwords.

- [Kubernetes install](kubernetes/README.md) — upstream Helm chart
- [OpenShift install](openshift/README.md) — same Helm chart, no operator exists

`common/` holds the wrapper Helm chart, in `common/chart/` because both platforms
install from it, differing only in their `values.yaml`. `manual/` has
hand-install instructions for going without ArgoCD.
