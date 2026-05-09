#!/bin/bash
set -e

# ============================================
# Bonus setup script
# This builds on Part 3 and adds a local GitLab
# instance. The flow becomes:
#
#   1. Install Docker, kubectl, K3d, Helm
#   2. Create K3d cluster
#   3. Install GitLab in "gitlab" namespace
#   4. Install Argo CD in "argocd" namespace
#   5. Create "dev" namespace
#   6. Push manifests to local GitLab
#   7. Point Argo CD at local GitLab instead of GitHub
# ============================================

echo "===== [1/9] Installing Docker ====="
if ! command -v docker &> /dev/null; then
  . /etc/os-release
  DISTRO=$ID   # "ubuntu" or "debian"
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
else
  echo "Docker already installed, skipping."
fi

echo "===== [2/9] Installing kubectl ====="
if ! command -v kubectl &> /dev/null; then
  ARCH=$(uname -m)
  [ "$ARCH" = "aarch64" ] && ARCH="arm64" || ARCH="amd64"
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm kubectl
else
  echo "kubectl already installed, skipping."
fi

echo "===== [3/9] Installing K3d ====="
if ! command -v k3d &> /dev/null; then
  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
else
  echo "K3d already installed, skipping."
fi

echo "===== [4/9] Installing Helm ====="
if ! command -v helm &> /dev/null; then
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  echo "Helm installed successfully."
else
  echo "Helm already installed, skipping."
fi

echo "===== [5/9] Creating K3d cluster ====="
k3d cluster delete iot-bonus 2>/dev/null || true

# More ports needed now:
# 8888  → our app
# 8080  → Argo CD UI
# 8443  → GitLab web UI
k3d cluster create iot-bonus \
  --api-port 6443 \
  -p "8888:8888@loadbalancer" \
  -p "8080:8080@loadbalancer" \
  -p "8443:8443@loadbalancer" \
  --wait

echo "Waiting for cluster nodes..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s
echo "Cluster ready."

# Make kubeconfig available to the sudo-calling user (not just root)
REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
mkdir -p "$REAL_HOME/.kube"
cp /root/.kube/config "$REAL_HOME/.kube/config"
chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.kube/config"

echo "===== [6/9] Creating namespaces ====="
kubectl create namespace argocd
kubectl create namespace dev
kubectl create namespace gitlab
echo "Namespaces created: argocd, dev, gitlab"

echo "===== [7/9] Installing GitLab ====="
# Add the GitLab Helm chart repository
helm repo add gitlab https://charts.gitlab.io/
helm repo update

# Install GitLab using Helm
# This is a MINIMAL install to keep resource usage low
# In production you'd want more replicas and resources
helm install gitlab gitlab/gitlab \
  --namespace gitlab \
  --set global.hosts.domain=gitlab.local \
  --set global.hosts.externalIP=127.0.0.1 \
  --set global.hosts.https=false \
  --set global.ingress.configureCertmanager=false \
  --set global.ingress.class=traefik \
  --set global.certmanager.install=false \
  --set nginx-ingress.enabled=false \
  --set registry.enabled=false \
  --set gitlab-runner.install=false \
  --set prometheus.install=false \
  --set global.kas.enabled=false \
  --set global.pages.enabled=false \
  --set gitlab.webservice.minReplicas=1 \
  --set gitlab.webservice.maxReplicas=1 \
  --set gitlab.sidekiq.minReplicas=1 \
  --set gitlab.sidekiq.maxReplicas=1 \
  --set gitlab.gitlab-shell.minReplicas=1 \
  --set gitlab.gitlab-shell.maxReplicas=1 \
  --timeout 600s

echo "Waiting for GitLab pods to start (this takes several minutes)..."
echo "GitLab is heavy — be patient..."

# Wait for the webservice pod specifically (it's the main one)
kubectl wait --for=condition=Ready pods \
  -l app=webservice \
  -n gitlab \
  --timeout=600s

# Get GitLab root password
echo ""
echo "=============================="
echo "GitLab root password:"
kubectl get secret gitlab-gitlab-initial-root-password \
  -n gitlab \
  -o jsonpath="{.data.password}" | base64 -d
echo ""
echo "=============================="
echo "Username: root"

echo "===== [8/9] Installing Argo CD ====="
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Waiting for Argo CD pods..."
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s

echo ""
echo "=============================="
echo "Argo CD admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
echo ""
echo "=============================="

echo "===== [9/9] Configuring Argo CD application ====="
# Apply the Argo CD app config that points to local GitLab
kubectl apply -f confs/argocd-app.yaml

# Port-forward Argo CD UI in background
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

echo ""
echo "===== BONUS SETUP COMPLETE ====="
echo ""
echo "Next steps:"
echo "1. Port-forward GitLab:  kubectl port-forward svc/gitlab-webservice-default -n gitlab 8443:8181 &"
echo "2. Access GitLab:        http://localhost:8443  (root / <password above>)"
echo "3. Create a project in GitLab called 'inception-of-things'"
echo "4. Push your manifests/deployment.yaml to that GitLab repo"
echo "5. Argo CD will detect and deploy automatically"
echo ""
echo "Argo CD UI:  https://localhost:8080  (admin / <password above>)"
echo "Test app:    curl http://localhost:8888/"