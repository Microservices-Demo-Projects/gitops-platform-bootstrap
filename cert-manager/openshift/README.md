# cert-manager (OpenShift)

Same job as on Kubernetes — issues and auto-renews TLS certificates, and creates
the shared `demo-ca` certificate authority — but installed via the Red Hat
**cert-manager Operator** (OLM Subscription) instead of the upstream Helm chart.

## What's here

```text
config/operator/     OperatorGroup + Subscription            (wave 10)
config/namespace/    The namespace, labelled for GitOps     (wave 10)
../common/config/    The demo-ca certificate authority       (wave 20)
../common/tests/     Prereq gate, then a smoke test that issues a throwaway cert
../manual/           Install by hand instead
```

## Install

Nothing to do — ArgoCD installs this first. See the
[ArgoCD guide](../../argocd/README.md).

## Verify

```bash
# Operator installed successfully?
oc get csv -n cert-manager-operator

# All three operand pods running?
oc get pods -n cert-manager

# The shared CA ready? Both should say True.
oc get clusterissuer
```

Expect the CSV to be `Succeeded`, and `self-signed`/`demo-ca` clusterissuers
both `READY=True`.

## Notes

### How the CA works

Same three-resource chain as Kubernetes, in
`../common/config/base/root-ca.yaml` — see
[../kubernetes/README.md](../kubernetes/README.md#how-the-ca-works) for details.
It's shared because the CA chain itself has no OpenShift-specific requirements;
only how cert-manager gets installed differs.

### The operator's namespaces aren't configurable

The operator (`redhat-operators`, channel `stable-v1`) hardcodes both its own
namespace (`cert-manager-operator`) and the operand's (`cert-manager`). It
auto-creates a default `CertManager` CR named `cluster` if none exists, so
nothing else needs authoring to get the operand running.
