#!/bin/bash

set -e

curl -sfL https://get.k3s.io | sh -

chmod 644 /etc/rancher/k3s/k3s.yaml

until kubectl get nodes 2>/dev/null | grep -q "Ready"; do
  sleep 5
done

kubectl apply -f /vagrant/confs/

kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=traefik -n kube-system --timeout=300s
