#!/usr/bin/env bash
#
# Tear the platform down and leave the cluster as it started. The OpenShift
# GitOps operator and ArgoCD are never touched. Why deleting platform-root alone
# isn't enough: ../README.md#tearing-it-down
#
#   ./argocd/openshift/teardown.sh
set -euo pipefail

CLI=oc
NAMESPACE=openshift-gitops
NAMESPACES="cert-manager-operator cert-manager external-secrets vault postgres stakater-reloader"

echo "==> Checking the platform AppProject exists"
# Every Application references spec.project: platform; without it no finalizer resolves.
if ! $CLI get appproject platform -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "    platform AppProject is missing - reapplying it so finalizers can resolve"
  $CLI apply -f "$(dirname "$0")/bootstrap/appproject.yaml"
fi

echo "==> Clearing in-flight sync operations"
for app in $($CLI get applications -n "$NAMESPACE" -o name 2>/dev/null); do
  phase=$($CLI get "$app" -n "$NAMESPACE" -o jsonpath='{.status.operationState.phase}' 2>/dev/null || true)
  if [ "$phase" = "Running" ]; then
    echo "    terminating stuck operation on ${app#*/}"
    $CLI patch "$app" -n "$NAMESPACE" --type merge \
      -p '{"status":{"operationState":{"phase":"Terminating"}}}' >/dev/null
  fi
done

echo "==> Deleting platform-root (cascades to every child app)"
$CLI delete application platform-root -n "$NAMESPACE" --ignore-not-found --wait=false

echo "==> Waiting up to 5 minutes for the cascade"
for _ in $(seq 1 60); do
  remaining=$($CLI get applications -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
  [ "$remaining" = "0" ] && break
  sleep 5
done

# Orphaning a wedged app's resources is safe - the sweeps below remove them.
if $CLI get applications -n "$NAMESPACE" --no-headers 2>/dev/null | grep -q .; then
  echo "==> Cascade did not finish; releasing the remaining apps"
  $CLI get applications -n "$NAMESPACE" --no-headers | awk '{print $1}' | while read -r app; do
    echo "    releasing $app"
    $CLI patch "application/$app" -n "$NAMESPACE" --type merge \
      -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1 || true
  done
fi

echo "==> Deleting the platform namespaces (takes the untracked leftovers with them)"
# Reverse dependency order, so each operator outlives the CRs it has to finalize.
for ns in $NAMESPACES; do
  $CLI delete namespace "$ns" --ignore-not-found --timeout=180s || \
    echo "    WARNING: $ns did not delete cleanly - check '$CLI get ns $ns -o yaml'"
done

echo "==> Cleaning up the CloudNativePG operator Subscription"
# Lives in the shared openshift-operators namespace, so remove only its own
# Subscription/CSV - never the namespace.
$CLI delete subscription cloudnative-pg -n openshift-operators --ignore-not-found
csv=$($CLI get csv -n openshift-operators -o name 2>/dev/null | grep -i cloudnative-pg || true)
[ -n "$csv" ] && $CLI delete "$csv" -n openshift-operators --ignore-not-found

echo "==> Sweeping CRDs"
# `|| true` because grep exits 1 on no match, which pipefail would treat as failure.
orphaned_crds=$($CLI get crd -o name | grep -E \
  'cert-manager\.io|vault\.banzaicloud\.com|external-secrets\.io|postgresql\.cnpg\.io' || true)
if [ -n "$orphaned_crds" ]; then
  echo "$orphaned_crds" | xargs $CLI delete --ignore-not-found --timeout=120s
fi

echo "==> Removing the orphaned openshift-gitops-cm ConfigMap"
# Left by an earlier wave-000 revision; unprunable, so it wedges platform-root
# OutOfSync on the next bootstrap. See ../README.md#tearing-it-down
$CLI delete configmap openshift-gitops-cm -n "$NAMESPACE" --ignore-not-found

echo "==> Deleting the AppProject"
$CLI delete -f "$(dirname "$0")/bootstrap/appproject.yaml" --ignore-not-found

echo
echo "==> What's left"
$CLI get applications -n "$NAMESPACE" 2>/dev/null || echo "    no Applications"
$CLI get ns -o name | grep -E "$(echo "$NAMESPACES" | tr ' ' '|')" || echo "    no platform namespaces"
echo
echo "Done. Re-bootstrap with: $CLI apply -f argocd/openshift/bootstrap/"
