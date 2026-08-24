#!/bin/bash
set -e

# Usage:
#   export GITLAB_TOKEN="glpat-xxxxxxxxxxxx"
#   ./push2gitlab.sh v1        # first deployment
#   ./push2gitlab.sh v2        # bump version later

GITLAB_URL="http://localhost:9444"
REPO_NAME="inception-of-things"
REPO_DIR="$HOME/${REPO_NAME}-repo"
VERSION="${1:-v1}"

if [ -z "${GITLAB_TOKEN:-}" ]; then
  echo "Error: export GITLAB_TOKEN=<your-personal-access-token> first."
  echo "Get one at: ${GITLAB_URL}/-/user_settings/personal_access_tokens (scope: api)"
  exit 1
fi

REMOTE_URL="http://root:${GITLAB_TOKEN}@localhost:9444/root/${REPO_NAME}.git"

echo "===== [1/3] Ensuring GitLab project exists ====="
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "${GITLAB_URL}/api/v4/projects/root%2F${REPO_NAME}")

if [ "$STATUS" != "200" ]; then
  echo "Creating project..."
  curl -sf -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    --data-urlencode "name=${REPO_NAME}" \
    --data-urlencode "path=${REPO_NAME}" \
    --data-urlencode "visibility=public" \
    --data-urlencode "initialize_with_readme=true" \
    --data-urlencode "default_branch=main" \
    "${GITLAB_URL}/api/v4/projects" >/dev/null
else
  echo "Project already exists."
fi

echo "===== [2/3] Preparing local repo ====="
if [ ! -d "$REPO_DIR/.git" ]; then
  git clone "$REMOTE_URL" "$REPO_DIR"
else
  git -C "$REPO_DIR" pull origin main
fi

mkdir -p "$REPO_DIR/manifests"
cat > "$REPO_DIR/manifests/deployment.yaml" << EOF
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
          image: wil42/playground:${VERSION}
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

echo "===== [3/3] Pushing to GitLab ====="
cd "$REPO_DIR"
git add manifests/deployment.yaml
git commit -m "Deploy ${VERSION}" || echo "Nothing changed (already at ${VERSION})"
git push origin main

echo ""
echo "===== Done: pushed ${VERSION} ====="
echo "Argo CD auto-syncs within ~3 minutes. To force it now:"
echo "  kubectl -n argocd annotate application wil-playground argocd.argoproj.io/refresh=hard --overwrite"