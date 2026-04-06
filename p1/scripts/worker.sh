#!/bin/bash

set -e

echo ">>> Waiting for server token to be available..."
# The server might still be provisioning when this script starts.
# We loop until the token file appears in the shared folder.
while [ ! -f /vagrant/node-token ]; do
  echo "    Token not yet available, waiting 5 seconds..."
  sleep 5
done

# Read the token that the server script deposited into the shared folder
TOKEN=$(cat /vagrant/node-token)

echo ">>> Installing K3s in agent (worker) mode..."

# K3S_URL tells the agent where the control plane API server is listening
# K3S_TOKEN is the shared secret to authenticate with the server
# --node-ip ensures this worker registers with its private network IP
curl -sfL https://get.k3s.io | K3S_URL="https://192.168.56.110:6443" \
  K3S_TOKEN="$TOKEN" \
  INSTALL_K3S_EXEC="agent --node-ip=192.168.56.111 --flannel-iface=eth1" sh -

echo ">>> Worker provisioning complete."
echo ">>> Worker IP: 192.168.56.111"