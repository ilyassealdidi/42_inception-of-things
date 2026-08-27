#!/bin/bash

set -e

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --bind-address=192.168.56.110 \
  --advertise-address=192.168.56.110 \
  --node-ip=192.168.56.110 \
  --flannel-iface=eth1" sh -

sleep 10

cp /var/lib/rancher/k3s/server/node-token /vagrant/node-token

chmod o+r /etc/rancher/k3s/k3s.yaml
cp /etc/rancher/k3s/k3s.yaml /vagrant/k3s.yaml
