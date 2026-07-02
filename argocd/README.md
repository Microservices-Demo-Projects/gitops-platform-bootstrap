# ArgoCD GitOps Automation Guide

> [!NOTE]
> **Status: 🛠️ Coming Soon / Work in Progress**  
> This directory is being structured to support fully automated cluster bootstrapping using ArgoCD via the App-of-Apps or ApplicationSet pattern.

---

## 🎯 What's Coming?

Instead of manually deploying the platform components one by one, you will be able to point ArgoCD to this folder to provision the entire "Landing Zone" with a single command. 

The automation will handle:
* **Dependency Ordering:** Ensuring infrastructure prerequisites (like `cert-manager` and `hashicorp-vault`) are fully ready before data layers (like `postgres` or `kafka`) attempt to deploy.
* **Automated Sync & Self-Healing:** Continuously tracking the `gitops-platform-bootstrap` repository to automatically fix configuration drift.
* **Multi-Environment Overlays:** Utilizing Kustomize overlays to seamlessly adjust cluster configurations between local development (`Kind` / `CRC`) and cloud environments (`EKS`, etc.).

---

## 📝 To-Do List

- [ ] Create the root ArgoCD `Application` / `ApplicationSet` manifest.
- [ ] Define the synchronization waves (`argocd.argoproj.io/sync-wave`) for each component to ensure correct installation order.
- [ ] Add configurations for automated secret handling and Vault integration during the bootstrap process.
- [ ] Document the initial login and port-forwarding steps for accessing the ArgoCD UI.

---

## How it Will Work (Preview)

Once complete, setting up your entire cluster infrastructure will be as simple as running:

```bash
kubectl apply -f argocd/root-application.yaml