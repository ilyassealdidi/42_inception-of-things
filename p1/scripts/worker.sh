#!/bin/bash

set -e

while [ ! -f /vagrant/node-token ]; do
  sleep 5
done

TOKEN=$(cat /vagrant/node-token)

curl -sfL https://get.k3s.io | K3S_URL="https://192.168.56.110:6443" \
  K3S_TOKEN="$TOKEN" \
  INSTALL_K3S_EXEC="agent --node-ip=192.168.56.111 --flannel-iface=eth1" sh -
