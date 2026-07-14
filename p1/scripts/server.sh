#!/bin/bash

# Exit immediately if any command fails
set -e

echo ">>> Installing K3s in server (controller) mode..."

# The official K3s install script detects the OS and installs the right binary.
# INSTALL_K3S_EXEC lets us pass arguments to the k3s server command.
# --bind-address and --advertise-address tell K3s to use the static private IP
# we assigned in the Vagrantfile, not the default NAT interface (eth0).
# --node-ip does the same for the node's registered IP in the cluster.
# Without these, K3s might register itself on the wrong interface and the
# worker won't be able to reach it.
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --bind-address=192.168.56.110 \
  --advertise-address=192.168.56.110 \
  --node-ip=192.168.56.110 \
  --flannel-iface=eth1" sh -

echo ">>> Waiting for K3s to be ready..."
# K3s takes a few seconds to fully start and generate the node token
sleep 10

echo ">>> Copying node token to shared folder so the worker can read it..."
# /vagrant is automatically mounted from your project directory on the host
# This is the bridge between the two VMs
cp /var/lib/rancher/k3s/server/node-token /vagrant/node-token

echo ">>> Copying kubeconfig so kubectl works from the host too (optional but useful)..."
chmod o+r /etc/rancher/k3s/k3s.yaml
cp /etc/rancher/k3s/k3s.yaml /vagrant/k3s.yaml

echo ">>> Server provisioning complete."
echo ">>> Server IP: 192.168.56.110"