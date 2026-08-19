#!/bin/bash
set -e

GITLAB_URL="http://localhost:8443"
REPO_NAME="inception-of-things"

echo "Setting up local git repo with manifests..."

# Create a temporary directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

git init
git checkout -b main

# Create the manifests folder
mkdir -p manifests

# Create deployment.yaml
cat > manifests/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wil-playground
  namespace: dev
spec:
  replicas: 1
  selector:
    matchLabels:
      app: wil-playground
  template:
    metadata:
      labels:
        app: wil-playground
    spec:
      containers:
        - name: wil-playground
          image: wil42/playground:v1
          ports:
            - containerPort: 8888

---

apiVersion: v1
kind: Service
metadata:
  name: wil-playground
  namespace: dev
spec:
  type: LoadBalancer
  selector:
    app: wil-playground
  ports:
    - protocol: TCP
      port: 8888
      targetPort: 8888
EOF

git add .
git commit -m "v1 - initial deployment"

# Push to local GitLab
git remote add origin "${GITLAB_URL}/root/${REPO_NAME}.git"
git push -u origin main

echo ""
echo "===== Manifests pushed to local GitLab ====="
echo "Argo CD will now detect and deploy the app."
echo ""
echo "To update to v2 later:"
echo "  1. cd $TEMP_DIR"
echo "  2. sed -i 's/playground:v1/playground:v2/g' manifests/deployment.yaml"
echo "  3. git add . && git commit -m 'v2' && git push"

# Save the path for later use
echo "$TEMP_DIR" > /tmp/bonus-repo-path
echo "Repo path saved to /tmp/bonus-repo-path"