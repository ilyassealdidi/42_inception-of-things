#!/bin/bash
set -e

OS="$(uname -s)"
ARCH="$(uname -m)"
[ "$ARCH" = "aarch64" ] && ARCH="arm64"
[ "$ARCH" = "x86_64" ]  && ARCH="amd64"

# Resolve the path to the confs directory relative to this script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFS_DIR="$(cd "$SCRIPT_DIR/../confs" && pwd)"

echo "===== [1/7] Installing Docker ====="
if ! command -v docker &> /dev/null; then
  if [ "$OS" = "Linux" ]; then
    . /etc/os-release
    DISTRO=$ID
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/${DISTRO}/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${DISTRO} \
      ${VERSION_CODENAME} stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io
    sudo usermod -aG docker $USER
    echo "Docker installed successfully."
  else
    echo "ERROR: Docker not found. On macOS install Docker Desktop from https://www.docker.com/products/docker-desktop/" >&2
    exit 1
  fi
else
  echo "Docker already installed, skipping."
fi

echo "===== [2/7] Installing kubectl ====="
if ! command -v kubectl &> /dev/null; then
  if [ "$OS" = "Darwin" ]; then
    if command -v brew &> /dev/null; then
      brew install kubectl
    else
      curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/${ARCH}/kubectl"
      sudo install -m 0755 kubectl /usr/local/bin/kubectl
      rm kubectl
    fi
  else
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
  fi
  echo "kubectl installed successfully."
else
  echo "kubectl already installed, skipping."
fi

echo "===== [3/7] Installing K3d ====="
if ! command -v k3d &> /dev/null; then
  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
  echo "K3d installed successfully."
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

# Write kubeconfig for the calling user
REAL_USER=${SUDO_USER:-$USER}
if [ "$OS" = "Darwin" ]; then
  REAL_HOME=$(dscl . -read /Users/"$REAL_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
fi
[ -z "$REAL_HOME" ] && REAL_HOME=$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f6)
[ -z "$REAL_HOME" ] && REAL_HOME=$(eval echo "~$REAL_USER")

mkdir -p "$REAL_HOME/.kube"
k3d kubeconfig get iot-cluster > "$REAL_HOME/.kube/config"
chown "$REAL_USER" "$REAL_HOME/.kube/config"

echo "K3d cluster created successfully."

echo "===== [5/7] Creating namespaces ====="
kubectl create namespace argocd 2>/dev/null || echo "Namespace argocd already exists."
kubectl create namespace dev    2>/dev/null || echo "Namespace dev already exists."
echo "Namespaces created."

echo "===== [6/7] Installing Argo CD ====="
# Fix DNS inside k3d node so it can pull images
docker exec k3d-iot-cluster-server-0 sh -c 'echo "nameserver 8.8.8.8" > /etc/resolv.conf'

kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Waiting for Argo CD pods to start..."
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s

echo ""
echo "=============================="
echo "Argo CD initial admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""
echo "=============================="
echo "Username: admin"

# Enable x86 image emulation on ARM64 (Linux only; macOS Rosetta handles this)
if [ "$OS" = "Linux" ]; then
  sudo apt-get install -y qemu-user-static binfmt-support 2>/dev/null || true
fi
docker run --privileged --rm tonistiigi/binfmt --install amd64 2>/dev/null || true

echo "===== [7/7] Configuring Argo CD application ====="
kubectl apply -f "$CONFS_DIR/argocd-app.yaml"

# Port-forward ArgoCD UI on 9090 (8080 may conflict with k3d)
# nohup + disown keeps the process alive after the SSH session ends
if [ "$OS" = "Darwin" ]; then
  nohup kubectl port-forward svc/argocd-server -n argocd 9090:443 \
    > /tmp/argocd-portforward.log 2>&1 &
else
  nohup kubectl port-forward --address 0.0.0.0 svc/argocd-server -n argocd 9090:443 \
    > /tmp/argocd-portforward.log 2>&1 &
fi
disown

echo ""
echo "===== SETUP COMPLETE ====="
echo "Check status:  kubectl get pods -n dev"
echo "Test app:      curl http://localhost:8888/"
echo "Argo CD UI:    https://localhost:9090 (admin / Mplq3RfXrgu-OGmj)"