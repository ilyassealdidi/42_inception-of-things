#!/bin/bash
set -e   # Stop on any error

echo "===== [AGENT] Installing K3s in agent mode ====="

# ── 1. Read the token from shared folder ──
# The server wrote this during its provisioning
TOKEN_FILE="/vagrant/shared/node-token"

if [ ! -f "$TOKEN_FILE" ]; then
  echo "ERROR: node-token not found at $TOKEN_FILE"
  echo "Make sure the server VM was provisioned first."
  exit 1
fi

K3S_TOKEN=$(cat "$TOKEN_FILE")
echo "Token retrieved successfully."

# ── 2. Install K3s as agent ──
# K3S_URL      → tells the agent where the server API is
# K3S_TOKEN    → authentication token to join the cluster
# --node-ip    → advertise on the private network
# --flannel-iface → use the correct network interface
curl -sfL https://get.k3s.io | K3S_URL="https://${SERVER_IP}:6443" \
  K3S_TOKEN="$K3S_TOKEN" \
  INSTALL_K3S_EXEC="agent \
    --node-ip ${NODE_IP} \
    --flannel-iface eth1" sh -

echo "===== [AGENT] K3s agent installation complete ====="
echo "Run 'kubectl get nodes' on the server to verify."
