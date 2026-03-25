#!/bin/bash
set -e   # Stop on any error

echo "===== [SERVER] Installing K3s in controller mode ====="

# ── 1. Install K3s as server ──
# --write-kubeconfig-mode 644  → makes kubectl usable without sudo
# --node-ip                    → advertise on the private network, not Vagrant's NAT
# --flannel-iface              → tells the CNI (network plugin) which interface to use
#                                 Vagrant creates eth1/enp0s8 for the private network
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --write-kubeconfig-mode 644 \
  --node-ip ${NODE_IP} \
  --flannel-iface eth1" sh -

# ── 2. Wait for K3s to be ready ──
echo "Waiting for K3s to start..."
sleep 10

# Verify the node is up
kubectl get nodes

# ── 3. Export the node token to the shared folder ──
# The agent VM will read this file to join the cluster
echo "Exporting node token to /vagrant/shared/node-token..."
mkdir -p /vagrant/shared
cp /var/lib/rancher/k3s/server/node-token /vagrant/shared/node-token

echo "===== [SERVER] K3s server installation complete ====="
