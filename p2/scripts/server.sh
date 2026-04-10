#!/bin/bash
set -e

curl -sfL https://get.k3s.io | sh -

chmod 644 /etc/rancher/k3s/k3s.yaml

echo ">>> Waiting for K3s to be ready..."
until kubectl get nodes 2>/dev/null | grep -q "Ready"; do
  echo "    K3s not ready yet, waiting..."
  sleep 5
done

echo ">>> Applying manifests..."
kubectl apply -f /vagrant/confs/