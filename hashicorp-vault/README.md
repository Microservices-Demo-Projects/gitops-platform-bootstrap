# HashiCorp Vault

Stores the platform's secrets, and hands out PostgreSQL passwords that expire on
their own, via the [bank-vaults](https://github.com/bank-vaults/vault-operator)
operator (auto-init/unseal, raft HA, kubernetes auth).

- [Kubernetes install](kubernetes/README.md)
- [OpenShift install](openshift/README.md) — no OLM operator exists for Vault, so
  it installs the same Helm chart via `common/chart/`, just with different values

`common/` holds the vault-operator chart, the `Vault` CR + certificate, and
PreSync/PostSync test Jobs, reused as-is by both platforms since there's no
operator to switch to. Because both platforms install the same chart it lives in
`common/chart/` rather than `kubernetes/chart/`. `manual/` has hand-install
instructions instead of going through ArgoCD.

## Notes

### Nobody ever unseals this by hand

`spec.unsealConfig.kubernetes` is what makes that true. On first boot the
operator generates the root token and unseal key shares, stores them in the
`vault-unseal-keys` Secret, and then re-unseals every Vault pod from it
automatically — including after a restart. `vault operator init` and `vault
operator unseal` are never run on this path, unlike `manual/README.md`.

`spec.externalConfig` — the policies, `kubernetes` auth roles and secrets
engines — is applied by the operator's bank-vaults sidecar once Vault is
unsealed. It's a free-form field; the CRD only declares
`x-kubernetes-preserve-unknown-fields`, and the shape matches bank-vaults' own
`vault-config.yml`.

Storage is a 3-node raft quorum, so this is real HA — the manual path is a
single node on file storage.

### Vault deliberately can't rotate the postgres superuser

The `database` secrets engine manages `app-ro`, `app-rw` and `app-setup`, and
stops there. PostgreSQL only lets a role with the actual `SUPERUSER` attribute
change another superuser's password — role membership isn't enough — so putting
the superuser under Vault would mean granting `vault` `SUPERUSER`. That's a far
bigger blast radius than a password rotation is worth. Superuser access is a
manual, audited break-glass toggle instead; see
[../postgres/README.md#notes](../postgres/README.md#notes).

The dynamic roles need no rotation job of their own: every credential request
mints a brand-new random user, auto-revoked at `default_ttl` and hard-capped at
`max_ttl`.
