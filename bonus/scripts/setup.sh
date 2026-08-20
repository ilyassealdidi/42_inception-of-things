#!/bin/bash
set -e

ARCH="$(uname -m)"
[ "$ARCH" = "aarch64" ] && ARCH="arm64" || ARCH="amd64"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFS_DIR="$(cd "$SCRIPT_DIR/../confs" && pwd)"

echo "===== [1/10] Installing Docker ====="
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

echo "===== [2/10] Installing kubectl ====="
if ! command -v kubectl &> /dev/null; then
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm kubectl
  echo "kubectl installed."
else
  echo "kubectl already installed, skipping."
fi

echo "===== [3/10] Installing K3d ====="
if ! command -v k3d &> /dev/null; then
  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
  echo "K3d installed."
else
  echo "K3d already installed, skipping."
fi

echo "===== [4/10] Installing Helm ====="
if ! command -v helm &> /dev/null; then
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  echo "Helm installed."
else
  echo "Helm already installed, skipping."
fi

echo "===== [5/10] Creating K3d cluster ====="
k3d cluster delete iot-cluster 2>/dev/null || true
k3d cluster delete iot-bonus   2>/dev/null || true

k3d cluster create iot-bonus \
  --api-port 6444 \
  -p "8888:8888@loadbalancer" \
  -p "8080:8080@loadbalancer" \
  -p "8443:8443@loadbalancer" \
  --wait

echo "Waiting for cluster nodes..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
mkdir -p "$REAL_HOME/.kube"
k3d kubeconfig get iot-bonus > "$REAL_HOME/.kube/config"
chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.kube/config"

echo "Cluster ready."

echo "===== [6/10] Creating namespaces ====="
kubectl create namespace argocd 2>/dev/null || true
kubectl create namespace dev    2>/dev/null || true
kubectl create namespace gitlab 2>/dev/null || true

echo "===== [7/10] Installing PostgreSQL and Redis ====="

docker exec k3d-iot-bonus-server-0 sh -c 'echo "nameserver 8.8.8.8" > /etc/resolv.conf'

helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
helm repo add gitlab https://charts.gitlab.io/ 2>/dev/null || true
helm repo update

helm upgrade --install pg bitnami/postgresql \
  --namespace gitlab \
  --set auth.username=gitlab \
  --set auth.password=gitlabpassword \
  --set auth.database=gitlabhq_production \
  --wait --timeout 120s

helm upgrade --install rd bitnami/redis \
  --namespace gitlab \
  --set auth.password=redispassword \
  --set architecture=standalone \
  --wait --timeout 120s

echo "Waiting for PostgreSQL and Redis to be ready..."
kubectl wait --for=condition=Ready pods \
  -l app.kubernetes.io/name=postgresql \
  -n gitlab --timeout=120s
kubectl wait --for=condition=Ready pods \
  -l app.kubernetes.io/name=redis \
  -n gitlab --timeout=120s

echo "===== [8/10] Installing GitLab ====="

helm upgrade --install gitlab gitlab/gitlab \
  --version 9.11.12 \
  --namespace gitlab \
  -f "$CONFS_DIR/gitlab-values.yaml" \
  --timeout 600s

echo "Waiting for GitLab webservice pod (this takes several minutes)..."
kubectl wait --for=condition=Ready pods \
  -l app=webservice \
  -n gitlab \
  --timeout=600s

echo ""
echo "=============================="
echo "GitLab root password:"
kubectl get secret gitlab-gitlab-initial-root-password \
  -n gitlab -o jsonpath="{.data.password}" | base64 -d
echo -e "\n=============================="
echo "Username: root"

echo "===== [9/10] Installing Argo CD ====="
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Waiting for Argo CD pods..."
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s

echo ""
echo "=============================="
echo "Argo CD admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
echo -e "\n=============================="

echo "===== [10/10] Configuring Argo CD application ====="
kubectl apply -f "$CONFS_DIR/argo-cd-app.yaml"

# Create systemd services for port-forwards so they survive SSH disconnect
cat > /etc/systemd/system/gitlab-portforward.service << EOF
[Unit]
Description=GitLab Port Forward
After=network.target

[Service]
ExecStart=/usr/local/bin/kubectl port-forward --address 0.0.0.0 svc/gitlab-webservice-default -n gitlab 8443:8181
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/argocd-portforward.service << EOF
[Unit]
Description=ArgoCD Port Forward
After=network.target

[Service]
ExecStart=/usr/local/bin/kubectl port-forward --address 0.0.0.0 svc/argocd-server -n argocd 8080:443
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable gitlab-portforward argocd-portforward
systemctl start gitlab-portforward argocd-portforward

PUBLIC_IP=$(hostname -I | awk '{print $1}')

echo ""
echo "===== SETUP IS COMPLETED ====="
echo ""
echo "Next: push your manifests to GitLab, then ArgoCD will deploy automatically."
echo "  Run:  bash $SCRIPT_DIR/push2gitlab.sh"
echo ""
echo "GitLab UI:   http://${PUBLIC_IP}:8443  (root / <password above>)"
echo "Argo CD UI:  https://${PUBLIC_IP}:8080  (admin / <password above>)"
echo "Test app:    curl http://${PUBLIC_IP}:8888/"