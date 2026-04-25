#!/bin/bash
set -e

# ============================================
# This script installs everything needed for Part 3:
#   1. Docker
#   2. kubectl
#   3. K3d
#   4. Creates a K3d cluster
#   5. Installs Argo CD
#   6. Creates the dev namespace
#   7. Configures the Argo CD application
# ============================================

echo "===== [1/7] Installing Docker ====="
# Only install if Docker is not already present
if ! command -v docker &> /dev/null; then
  sudo apt-get update
  sudo apt-get install -y ca-certificates curl gnupg
  # Add Docker's official GPG key
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  # Add Docker repository
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io
  # Let current user run Docker without sudo
  sudo usermod -aG docker $USER
  echo "Docker installed successfully."
else
  echo "Docker already installed, skipping."
fi

echo "===== [2/7] Installing kubectl ====="
if ! command -v kubectl &> /dev/null; then
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm kubectl
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
# Delete existing cluster if it exists (for clean re-runs)
k3d cluster delete iot-cluster 2>/dev/null || true

# Create a new cluster
# --api-port 6443         → Kubernetes API will listen on port 6443
# -p "8888:8888@loadbalancer" → forward port 8888 from host to cluster
#                               so we can curl localhost:8888 to reach our app
k3d cluster create iot-cluster \
  --api-port 6443 \
  -p "8888:8888@loadbalancer" \
  --wait

# Verify cluster is running
echo "Waiting for cluster to be ready..."
kubectl get nodes
echo "K3d cluster created successfully."

echo "===== [5/7] Creating namespaces ====="
# Create the argocd namespace
kubectl create namespace argocd
# Create the dev namespace where our app will live
kubectl create namespace dev
echo "Namespaces created."

echo "===== [6/7] Installing Argo CD ====="
# Install Argo CD into the argocd namespace
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for Argo CD pods to be ready
echo "Waiting for Argo CD pods to start (this may take a minute)..."
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s

# Get the initial admin password
# Argo CD generates a random password stored in a secret
echo ""
echo "=============================="
echo "Argo CD initial admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""
echo "=============================="
echo ""
echo "Username: admin"

# Expose Argo CD server so you can access the web UI
# This runs in the background — access it at https://localhost:8080
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
echo "Argo CD UI available at https://localhost:8080"

echo "===== [7/7] Configuring Argo CD application ====="
# Apply the Argo CD application manifest
# This tells Argo CD: "watch this GitHub repo and deploy into the dev namespace"
kubectl apply -f confs/argocd-app.yaml

echo ""
echo "===== SETUP COMPLETE ====="
echo "Your app will be deployed automatically by Argo CD."
echo "Check status:  kubectl get pods -n dev"
echo "Test app:      curl http://localhost:8888/"
echo "Argo CD UI:    https://localhost:8080 (admin / <password above>)"
