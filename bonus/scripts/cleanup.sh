#!/bin/bash
set -euo pipefail

NAMESPACE=gitlab

echo "===== Cleaning up ${NAMESPACE} namespace ====="

# Uninstall Helm releases first
helm uninstall gitlab -n "${NAMESPACE}" 2>/dev/null || true
helm uninstall gitlab-postgresql -n "${NAMESPACE}" 2>/dev/null || true
helm uninstall gitlab-redis -n "${NAMESPACE}" 2>/dev/null || true

echo "Helm releases uninstalled."

# Delete all common resources in the namespace (ignore errors if none)
kubectl delete all --all -n "${NAMESPACE}" 2>/dev/null || true
kubectl delete serviceaccount --all -n "${NAMESPACE}" 2>/dev/null || true
kubectl delete configmap --all -n "${NAMESPACE}" 2>/dev/null || true
kubectl delete secret --all -n "${NAMESPACE}" 2>/dev/null || true
kubectl delete networkpolicy --all -n "${NAMESPACE}" 2>/dev/null || true
kubectl delete pvc --all -n "${NAMESPACE}" 2>/dev/null || true
kubectl delete rolebinding --all -n "${NAMESPACE}" 2>/dev/null || true
kubectl delete role --all -n "${NAMESPACE}" 2>/dev/null || true
kubectl delete ingress --all -n "${NAMESPACE}" 2>/dev/null || true
kubectl delete endpoints --all -n "${NAMESPACE}" 2>/dev/null || true

echo "All namespace-scoped resources deleted (if any)."

echo "Deleting namespace ${NAMESPACE} (if present)..."
kubectl delete namespace "${NAMESPACE}" --ignore-not-found || true

echo "Waiting up to 120s for namespace to be removed..."
if kubectl wait --for=delete namespace/${NAMESPACE} --timeout=120s 2>/dev/null; then
  echo "Namespace ${NAMESPACE} deleted."
else
  echo "Namespace ${NAMESPACE} still exists after timeout. Attempting safe finalizer removal if possible."
  if command -v jq >/dev/null 2>&1; then
    if kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
      echo "Removing finalizers from namespace ${NAMESPACE}..."
      kubectl get namespace "${NAMESPACE}" -o json | jq 'del(.spec.finalizers)' | kubectl replace --raw "/api/v1/namespaces/${NAMESPACE}/finalize" -f - || true
      kubectl wait --for=delete namespace/${NAMESPACE} --timeout=60s 2>/dev/null || true
    else
      echo "Namespace ${NAMESPACE} not found; nothing to finalize."
    fi
  else
    echo "jq not installed; cannot remove finalizers automatically. Install jq to enable this step."
  fi
fi

# Recreate namespace if missing
if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "Recreating namespace ${NAMESPACE}..."
  kubectl create namespace "${NAMESPACE}"
else
  echo "Namespace ${NAMESPACE} already exists."
fi

echo "===== Cleanup complete ====="
echo "You can now run the setup script."