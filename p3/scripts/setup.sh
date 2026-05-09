#!/bin/bash
set -e

ARCH="$(uname -m)"
[ "$ARCH" = "aarch64" ] && ARCH="arm64" || ARCH="amd64"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFS_DIR="$(cd "$SCRIPT_DIR/../confs" && pwd)"

echo "===== [1/7] Installing Docker ====="
if ! command -v docker &> /dev/null; then
  . /etc/os-release
  sudo apt-get update
  sudo apt-get install -y ca-certificates curl gnupg
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/${ID}/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io
  sudo usermod -aG docker "$USER"
  echo "Docker installed."
else
  echo "Docker already installed, skipping."
fi

echo "===== [2/7] Installing kubectl ====="
if ! command -v kubectl &> /dev/null; then
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm kubectl
  echo "kubectl installed."
else
  echo "kubectl already installed, skipping."
fi

echo "===== [3/7] Installing K3d ====="
if ! command -v k3d &> /dev/null; then
  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
  echo "K3d installed."
else
  echo "K3d already installed, skipping."
fi

echo "===== [4/7] Creating K3d cluster ====="
k3d cluster delete iot-cluster 2>/dev/null || true

k3d cluster create iot-cluster \
  --api-port 6443 \
  -p "8888:8888@loadbalancer" \
  --wait

echo "Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
mkdir -p "$REAL_HOME/.kube"
k3d kubeconfig get iot-cluster > "$REAL_HOME/.kube/config"
chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.kube/config"

echo "K3d cluster created."

echo "===== [5/7] Creating namespaces ====="
kubectl create namespace argocd 2>/dev/null || true
kubectl create namespace dev    2>/dev/null || true

echo "===== [6/7] Installing Argo CD ====="
docker exec k3d-iot-cluster-server-0 sh -c 'echo "nameserver 8.8.8.8" > /etc/resolv.conf'

kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Waiting for Argo CD pods..."
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s

echo ""
echo "=============================="
echo "Argo CD initial admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo -e "\n=============================="
echo "Username: admin"

# Enable x86 image emulation on ARM64 hosts
sudo apt-get install -y qemu-user-static binfmt-support 2>/dev/null || true
docker run --privileged --rm tonistiigi/binfmt --install amd64 2>/dev/null || true

echo "===== [7/7] Configuring Argo CD application ====="
kubectl apply -f "$CONFS_DIR/argocd-app.yaml"

nohup kubectl port-forward --address 0.0.0.0 svc/argocd-server -n argocd 9090:443 \
  > /tmp/argocd-portforward.log 2>&1 &
disown

echo ""
echo "===== SETUP COMPLETE ====="
echo "Check status:  kubectl get pods -n dev"
echo "Test app:      curl http://localhost:8888/"
echo "Argo CD UI:    https://<droplet-ip>:9090  (admin / <password above>)"
