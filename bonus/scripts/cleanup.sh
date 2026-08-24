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


# (optional) delete namespace-scoped resources first
kubectl delete all --all -n gitlab --ignore-not-found

# delete the namespace
kubectl delete namespace gitlab --ignore-not-found

# wait for deletion (120s)
kubectl wait --for=delete namespace/gitlab --timeout=120s || echo "Namespace still exists or timed out"

# if still stuck, remove finalizers (no jq required) and retry
kubectl patch namespace gitlab -p '{"spec":{"finalizers":[]}}' --type=merge || true
kubectl delete namespace gitlab --ignore-not-found
kubectl wait --for=delete namespace/gitlab --timeout=60s || echo "Namespace still exists"



# verify
kubectl get namespaces

#!/bin/bash
set -e

# Usage:
#   ./cleanup.sh              # interactive, asks before destructive steps
#   ./cleanup.sh -y           # no prompts, clean everything
#   ./cleanup.sh -y --keep-repo   # clean everything except ~/inception-of-things-repo

AUTO_YES=false
KEEP_REPO=false

for arg in "$@"; do
  case "$arg" in
    -y|--yes) AUTO_YES=true ;;
    --keep-repo) KEEP_REPO=true ;;
  esac
done

confirm() {
  if $AUTO_YES; then
    return 0
  fi
  read -r -p "$1 [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

echo "===== [1/6] Stopping port-forwards ====="
# Covers both the nohup-based version and the older systemd-service version
pkill -f "kubectl port-forward.*argocd-server" 2>/dev/null || true
pkill -f "kubectl port-forward.*gitlab-webservice" 2>/dev/null || true

if systemctl list-unit-files 2>/dev/null | grep -q gitlab-portforward.service; then
  sudo systemctl stop gitlab-portforward.service 2>/dev/null || true
  sudo systemctl disable gitlab-portforward.service 2>/dev/null || true
  sudo rm -f /etc/systemd/system/gitlab-portforward.service
fi
if systemctl list-unit-files 2>/dev/null | grep -q argocd-portforward.service; then
  sudo systemctl stop argocd-portforward.service 2>/dev/null || true
  sudo systemctl disable argocd-portforward.service 2>/dev/null || true
  sudo rm -f /etc/systemd/system/argocd-portforward.service
fi
sudo systemctl daemon-reload 2>/dev/null || true
echo "Port-forwards stopped."

echo "===== [2/6] Deleting K3d clusters ====="
k3d cluster delete iot-bonus   2>/dev/null || true
k3d cluster delete iot-cluster 2>/dev/null || true
echo "K3d clusters deleted."

echo "===== [3/6] Removing dangling k3d Docker network/volumes (if any) ====="
docker network rm k3d-iot-bonus   2>/dev/null || true
docker network rm k3d-iot-cluster 2>/dev/null || true
docker volume rm k3d-iot-bonus-images   2>/dev/null || true
docker volume rm k3d-iot-cluster-images 2>/dev/null || true
echo "Done (any 'no such network/volume' messages above are expected and harmless)."

echo "===== [4/6] Removing kubeconfig ====="
if [ -f "$HOME/.kube/config" ]; then
  if confirm "Remove $HOME/.kube/config? (only needed if it's dedicated to this project)"; then
    rm -f "$HOME/.kube/config"
    echo "Removed."
  else
    echo "Skipped."
  fi
fi

echo "===== [5/6] Removing local git clone ====="
if [ -d "$HOME/inception-of-things-repo" ]; then
  if $KEEP_REPO; then
    echo "Skipped (--keep-repo)."
  elif confirm "Remove $HOME/inception-of-things-repo?"; then
    rm -rf "$HOME/inception-of-things-repo"
    echo "Removed."
  else
    echo "Skipped."
  fi
fi

echo "===== [6/6] Removing leftover temp files ====="
rm -rf /tmp/gitlab-chart
rm -f /tmp/bonus-repo-path
rm -f /tmp/argocd-portforward.log /tmp/gitlab-portforward.log
echo "Temp files removed."

echo ""
echo "===== CLEANUP COMPLETE ====="
echo "Verify with:"
echo "  k3d cluster list"
echo "  docker ps -a"
echo "  docker network ls | grep k3d"

docker container prune    # removes stopped containers
docker image prune -a     # removes unused images (careful: re-downloads next time you need them)
docker volume prune       # removes unused volumes
echo "===== Cleanup complete ====="
echo "You can now run the setup script."