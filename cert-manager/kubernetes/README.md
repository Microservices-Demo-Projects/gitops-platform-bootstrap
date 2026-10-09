# cert-manager (Kubernetes)

Issues and auto-renews TLS certificates. Everything else in this platform gets its
certificates from here, so it goes in first.

It also creates **`demo-ca`** — one shared certificate authority for the whole
cluster. Vault, PostgreSQL, External Secrets and Headlamp all ask `demo-ca` for
their certificates, which means they automatically trust each other.

## What's here

```text
chart/               Helm chart for cert-manager itself      (wave 10)
values.yaml          Kubernetes-specific chart values (HA tuning)
../common/config/    The demo-ca certificate authority       (wave 20)
../common/tests/     Prereq gate, then a smoke test that issues a throwaway cert
../manual/           Install by hand instead
```

## Install

Nothing to do — ArgoCD installs this first. See the
[ArgoCD guide](../../argocd/README.md).

## Verify

```bash
# All three pods running?
kubectl get pods -n cert-manager

# The shared CA ready? Both should say True.
kubectl get clusterissuer
```

Expect `self-signed` and `demo-ca`, both `READY=True`. If `demo-ca` isn't ready,
nothing downstream will get a certificate.

## Notes

### How the CA works

Three resources in a chain, all in `../common/config/base/root-ca.yaml`:

1. `self-signed` — a bootstrap issuer that can sign its own certificates
2. `demo-root-ca` — the CA certificate, signed by `self-signed`
3. `demo-ca` — the issuer everything else uses, backed by that certificate

Certificates are valid for a year and renew automatically 10 days before expiry.

Because this is a demo CA, browsers won't trust it — you'll get a warning when
opening Headlamp. That's expected.
