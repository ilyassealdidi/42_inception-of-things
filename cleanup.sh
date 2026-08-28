#!/bin/bash
set -euo pipefail

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