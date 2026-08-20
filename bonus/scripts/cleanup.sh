#!/bin/bash

echo "===== Cleaning up GitLab namespace ====="

# Uninstall Helm releases first
helm uninstall gitlab -n gitlab 2>/dev/null || true
helm uninstall gitlab-postgresql -n gitlab 2>/dev/null || true
helm uninstall gitlab-redis -n gitlab 2>/dev/null || true

echo "Helm releases uninstalled."

# Delete all resources in the namespace
kubectl delete all --all -n gitlab 2>/dev/null || true
kubectl delete serviceaccount --all -n gitlab 2>/dev/null || true
kubectl delete configmap --all -n gitlab 2>/dev/null || true
kubectl delete secret --all -n gitlab 2>/dev/null || true
kubectl delete networkpolicy --all -n gitlab 2>/dev/null || true
kubectl delete pvc --all -n gitlab 2>/dev/null || true
kubectl delete rolebinding --all -n gitlab 2>/dev/null || true
kubectl delete role --all -n gitlab 2>/dev/null || true
kubectl delete ingress --all -n gitlab 2>/dev/null || true
kubectl delete endpoints --all -n gitlab 2>/dev/null || true

echo "All resources deleted."

# Delete and recreate namespace
kubectl delete namespace gitlab --force --grace-period=0 2>/dev/null || true

echo "Waiting for namespace to be fully deleted..."
while kubectl get namespace gitlab 2>/dev/null; do
  echo "  Still deleting..."
  sleep 3
done

kubectl create namespace gitlab
echo "Namespace recreated."

echo "===== Cleanup complete ====="
echo "You can now run the setup script."